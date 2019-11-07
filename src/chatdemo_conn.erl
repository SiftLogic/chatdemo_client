-module(chatdemo_conn).

-behaviour(gen_server).

%% API
-export([start/2]).
-export([start_link/2]).

-export([handle_command/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).
-define(SERVER_PORT, 8181).
-define(BASE_PATH, "/chat").

-define(DISCONNECTED, <<"disconnected">>).
-define(NOT_LOGGED_ON, <<"not_logged_on">>).

%% Records are 'syntactic sugar'. They are converted into tuples during compilation
-record(state,
        {
         conn                   :: undefined | port(),
         ref                    :: undefined | reference(),
         stream                 :: undefined | reference(),
         apikey                 :: undefined | binary(),
         ip                     :: undefined | inet:ip_address(),
         status = ?DISCONNECTED :: binary(),
         user                   :: undefined | binary(),
         pass                   :: undefined | binary()
        }).

%%%===================================================================
%%% API
%%%===================================================================
handle_command({network, _, _} = Command) ->
    gen_server:cast(?SERVER, Command);
handle_command(Command) ->
    gen_server:call(?SERVER, Command).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link(term(), term()) ->
             {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link(Ip, Apikey) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [Ip, Apikey], []).

-spec(start(term(), term()) ->
             {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start(Ip, Apikey) ->
    gen_server:start({local, ?SERVER}, ?MODULE, [Ip, Apikey], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
             {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
             {stop, Reason :: term()} | ignore).
init([IpAddress, ApiKey]) ->
    {ok, Ip} = convert_ip(IpAddress),
    case connect(Ip, ApiKey) of
        {ok, {MRef, ConnPid, StreamRef}} ->
            erlang:send_after(10000, self(), ping),
            {ok, #state{status = ?NOT_LOGGED_ON, conn = ConnPid, ref = MRef, stream = StreamRef, apikey = ApiKey, ip = Ip}};
        _Error ->
            reconnect_msg(),
            {ok, #state{ip = Ip, apikey = ApiKey}}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
                  State :: #state{}) ->
             {reply, Reply :: term(), NewState :: #state{}} |
             {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
             {noreply, NewState :: #state{}} |
             {noreply, NewState :: #state{}, timeout() | hibernate} |
             {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
             {stop, Reason :: term(), NewState :: #state{}}).
handle_call(_, _From, #state{status = ?DISCONNECTED} = State) ->
    io:format("You're not connected to the server. Use '/connect IPADDRESS' or '/connect' to connect.~n"),
    {reply, ok, State};
handle_call({user, register, {Username, Password}}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"user_register">>},
           {<<"data">>, [{<<"username">>, Username},
                         {<<"password">>, Password}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State#state{user = Username, pass = Password}};
handle_call({user, login, {Username, Password}}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"user_login">>},
           {<<"data">>, [{<<"username">>, Username},
                         {<<"password">>, Password}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State#state{user = Username, pass = Password}};
handle_call({user, logoff, undefined}, _From, #state{conn = Conn,
                                                     stream = SRef,
                                                     ref = PRef} = State) ->
    catch demonitor(SRef),
    catch demonitor(PRef),
    catch gun:close(Conn),
    io:format("Logged off~n"),
    NState = State#state{user = undefined,
                         pass = undefined,
                         conn = undefined,
                         ref = undefined,
                         stream = undefined,
                         status = ?DISCONNECTED},
    {reply, ok, NState};
handle_call(_Cmd, _From, #state{status = ?NOT_LOGGED_ON} = State) ->
    %% We put this case here to stop other commands
    %% from being processed if the user is not logged on
    io:format("Error: ~s~n", [<<"You're not logged on. Please login and/or register">>]),
    {reply, ok, State};
handle_call({user, password, {Old, New}}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"user_password">>},
           {<<"data">>, [{<<"old">>, Old},
                         {<<"new">>, New}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({user, channels, undefined}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"user_channels">>}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({user, list, undefined}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"user_list">>}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({channel, list, undefined}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"channel_list">>}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({channel, members, Channel}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"channel_members">>},
           {<<"data">>, [{<<"channel">>, Channel}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({channel, create, {Channel, Access}}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"channel_create">>},
           {<<"data">>, [{<<"channel">>, Channel},
                         {<<"access">>, Access}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({channel, delete, Channel}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"channel_delete">>},
           {<<"data">>, [{<<"channel">>, Channel}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({channel, join, Channel}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"channel_join">>},
           {<<"data">>, [{<<"channel">>, Channel}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({channel, leave, Channel}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"channel_leave">>},
           {<<"data">>, [{<<"channel">>, Channel}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({channel, adduser, {Channel, User, Role}}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"channel_adduser">>},
           {<<"data">>, [{<<"channel">>, Channel},
                         {<<"user">>, User},
                         {<<"role">>, Role}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({channel, kickuser, {Channel, User}}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"channel_kickuser">>},
           {<<"data">>, [{<<"channel">>, Channel},
                         {<<"user">>, User}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({channel, message, {Channel, Message}}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"channel_message">>},
           {<<"data">>, [{<<"channel">>, Channel},
                         {<<"message">>, Message}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({msg, _To, <<>>}, _From, #state{} = State) ->
    io:format("Error: We don't send empty messages~n"),
    {reply, ok, State};
handle_call({msg, global, Message}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"message">>},
           {<<"data">>, [{<<"to">>, <<"global">>},
                         {<<"message">>, Message}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({msg, _User, <<>>}, _From, #state{} = State) ->
    io:format("Error: We don't send empty messages~n"),
    {reply, ok, State};
handle_call({msg, User, Message}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"private_message">>},
           {<<"data">>, [{<<"to">>, User},
                         {<<"message">>, Message}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call(_Request, _From, State) ->
    Error = <<"Unknown Command: ~p",
              (io_lib:format("~p", [_Request]))/binary>>,
    io:format("Error: ~s~n", [Error]),
    {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
             {noreply, NewState :: #state{}} |
             {noreply, NewState :: #state{}, timeout() | hibernate} |
             {stop, Reason :: term(), NewState :: #state{}}).
handle_cast({network, connect, undefined}, #state{ip = Ip,
                                                  apikey = ApiKey,
                                                  conn = Conn,
                                                  stream = SRef,
                                                  ref = PRef} = State) ->
    catch demonitor(SRef),
    catch demonitor(PRef),
    catch gun:close(Conn),
    case connect(Ip, ApiKey) of
        {ok, {MRef, ConnPid, StreamRef}} ->
            erlang:send_after(10000, self(), ping),
            NState = State#state{status = ?NOT_LOGGED_ON,
                                 conn = ConnPid,
                                 ref = MRef,
                                 stream = StreamRef},
            gen_server:cast(?SERVER, reauth),
            {noreply, NState};
        _Error ->
            reconnect_msg(),
            NState = State#state{status = ?DISCONNECTED,
                                 conn = undefined,
                                 stream = undefined,
                                 ref = undefined},
            {noreply, NState}
    end;
handle_cast({network, connect, {_,_,_,_} = NewIp}, #state{apikey = ApiKey,
                                                          conn = Conn,
                                                          stream = SRef,
                                                          ref = PRef} = State) ->
    catch demonitor(SRef),
    catch demonitor(PRef),
    catch gun:close(Conn),
    case connect(NewIp, ApiKey) of
        {ok, {MRef, ConnPid, StreamRef}} ->
            erlang:send_after(10000, self(), ping),
            NState = State#state{status = ?NOT_LOGGED_ON,
                                 ip = NewIp,
                                 conn = ConnPid,
                                 ref = MRef,
                                 stream = StreamRef},
            gen_server:cast(?SERVER, reauth),
            {noreply, NState};
        _Error ->
            reconnect_msg(),
            NState = State#state{status = ?DISCONNECTED,
                                 ip = NewIp,
                                 conn = undefined,
                                 stream = undefined,
                                 ref = undefined},
            {noreply, NState}
    end;
handle_cast(reauth, #state{conn = Conn, user = Username, pass = Password} = State)
  when Username =/= undefined andalso Password =/= undefined ->
    Msg = [{<<"cmd">>, <<"user_login">>},
           {<<"data">>, [{<<"username">>, Username},
                         {<<"password">>, Password}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {noreply, State};
handle_cast(_Request, State) ->
    %% io:format("~p~n", [State]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
             {noreply, NewState :: #state{}} |
             {noreply, NewState :: #state{}, timeout() | hibernate} |
             {stop, Reason :: term(), NewState :: #state{}}).
handle_info(ping, #state{status = ?DISCONNECTED} = State) ->
    {noreply, State};
handle_info(ping, #state{conn = Conn} = State) ->
    ok = send(Conn, <<"ping">>),
    {noreply, State};
handle_info({gun_ws, _ConnPid, _StreamRef, {text, <<"pong">>}}, State) ->
    %% io:format("pong~n"),
    erlang:send_after(10000, self(), ping),
    {noreply, State};
handle_info({gun_ws, _ConnPid, _StreamRef, {text, Frame}}, State) ->
    Body    = mochijson2:decode(Frame, [{format, proplist}]),
    Channel = proplists:get_value(<<"channel">>,    Body, <<"GLOBAL">>),
    From    = proplists:get_value(<<"from">>,       Body, <<"anonymous">>),
    Msg     = proplists:get_value(<<"msg">>,        Body, <<"hmmm: empty message">>),
    Class   = proplists:get_value(<<"class">>,      Body, <<"user">>),
    case Class of
        <<"private">> ->
            io:format("~s whispers: ~s~n", [From, Msg]);
        <<"user">> ->
            io:format("~s: ~s says: ~s~n", [Channel, From, Msg]);
        <<"response">> ->
            io:format("~s~n", [Msg]);
        <<"system">> ->
            io:format("SYSTEM MESSAGE: ~s~n", [Msg]);
        <<"error">> ->
            io:format("ERROR: ~s~n", [Msg])
    end,
    NState = case proplists:get_value(<<"status">>, Body, undefined) of
                 undefined ->
                     State;
                 Status ->
                     State#state{status = Status}
             end,
    {noreply, NState};
handle_info({gun_ws, Pid, SRef, {close,1000,<<>>}}, #state{conn = Pid,
                                                           stream = SRef,
                                                           ref = Ref,
                                                           ip = Ip,
                                                           apikey = ApiKey} = State) ->
    erlang:demonitor(Ref),
    gun:close(Pid),
    case connect(Ip, ApiKey) of
        {ok, {MRef, ConnPid, StreamRef}} ->
            NState = State#state{status = ?NOT_LOGGED_ON,
                                 conn = ConnPid,
                                 ref = MRef,
                                 stream = StreamRef},
            ok = gen_server:cast(?SERVER, reauth),
            {noreply, NState};
        _Error ->
            io:format("Failed to reconnect. Try again later with '/connect'.~n"),
            NState = State#state{status = ?DISCONNECTED,
                                 conn = undefined,
                                 ref = undefined,
                                 stream = undefined},
            {noreply, NState}
    end;
handle_info({gun_down, Pid, _Proto, _Reason, _Refs0, _Refs1}, #state{conn = Pid,
                                                                     ref = Ref,
                                                                     ip = Ip,
                                                                     apikey = ApiKey} = State) ->
    io:format("Connection ~p down, reconnecting~n", [Pid]),
    erlang:demonitor(Ref),
    case connect(Ip, ApiKey) of
        {ok, {NRef, NPid, NStream}} ->
            NState = State#state{status = ?NOT_LOGGED_ON,
                                 conn = NPid,
                                 ref = NRef,
                                 stream = NStream},
            ok = gen_server:cast(?SERVER, reauth),
            {noreply, NState};
        _Error ->
            io:format("Failed to reconnect. Try again later with '/connect'.~n"),
            {noreply, State#state{status = ?DISCONNECTED,
                                  conn = undefined,
                                  ref = undefined,
                                  stream = undefined}}
    end;
handle_info({'DOWN',_Ref, process,_Pid,_Reason}, State) ->
    %% We're just ignoring this here
    {noreply, State};
handle_info(_Info, State) ->
    io:format("Received unmatched message: ~p ~p ~n", [_Info, State]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
                State :: #state{}) -> term()).
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
                  Extra :: term()) ->
             {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
convert_ip(IpAddress) ->
    case inet_parse:address(IpAddress) of
        {ok, Ip} ->
            {ok, Ip};
        {error, einval} = Error ->
            io:format("~p is not a valid IP Address~n", [IpAddress]),
            Error
    end.

connect(Ip, Apikey) ->
    io:format("connecting to ~p~n", [Ip]),
    connect(Ip, Apikey, 2).

connect(_Ip, _Apikey, 0) ->
    {error, max_reconnects_exceeded};
connect(Ip, Apikey, Rem) ->
    Opts = #{retry => 0},
    case gun:open(inet_parse:ntoa(Ip), ?SERVER_PORT, Opts) of
        {ok, ConnPid} ->
            case gun:await_up(ConnPid) of
                {ok, _Proto} ->
                    MRef = monitor(process, ConnPid),
                    %% Now we upgrade to websocket
                    Headers = [{<<"x-apikey">>, Apikey}],
                    _StreamRef =  gun:ws_upgrade(ConnPid,
                                                 ?BASE_PATH,
                                                 Headers,
                                                 #{compress => true}),
                    io:format("Connected to ~s~n", [inet_parse:ntoa(Ip)]),
                    confirm_upgrade(MRef, ConnPid);
                _AwaitError ->
                    gun:close(ConnPid),
                    io:format("Connection Error: Retrying~n"),
                    timer:sleep(timer:seconds(1)),
                    connect(Ip, Apikey, Rem - 1)
            end;
        {error, timeout} ->
            io:format("Connection Error: timeout, Retrying~n"),
            timer:sleep(timer:seconds(1)),
            connect(Ip, Apikey, Rem - 1)
    end.

confirm_upgrade(MRef, ConnPid) ->
    receive
        {'DOWN', Ref, process, _Pid, _} ->
            erlang:demonitor(Ref),
            confirm_upgrade(MRef, ConnPid);
        {gun_upgrade, ConnPid, NStreamRef, [<<"websocket">>], _} ->
            {ok, {MRef, ConnPid, NStreamRef}};
        Msg ->
            io:format("Unexpected message in socket upgrade [~p] ~p~n", [ConnPid, Msg]),
            gun:close(ConnPid),
            {error, broken_upgrade}
    end.

send(Conn, Packet) ->
    gun:ws_send(Conn, {text, Packet}).

encode(Message) ->
    Json = mochijson2:encode(Message),
    BinMsg = iolist_to_binary(Json),
    {ok, BinMsg}.

reconnect_msg() ->
    io:format("Failed to connect to server. You can try again with '/connect'~n").
