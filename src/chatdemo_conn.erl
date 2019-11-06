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

-record(state, {conn, ref, stream, apikey, ip, status = <<"not_logged_on">>, user, pass}).

%%%===================================================================
%%% API
%%%===================================================================
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
init([IpAddress, Apikey]) ->
    {ok, Ip} = convert_ip(IpAddress),
    case connect(Ip, Apikey) of
        {ok, {MRef, ConnPid, StreamRef}} ->
            erlang:send_after(10000, self(), ping),
            {ok, #state{conn = ConnPid, ref = MRef, stream = StreamRef, apikey = Apikey, ip = Ip}};
        Error ->
            {stop, Error}
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
handle_call({user, register, {Username, Password}}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"user_register">>},
           {<<"data">>, [{<<"username">>, Username},
                         {<<"password">>, Password}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({user, login, {Username, Password}}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"cmd">>, <<"user_login">>},
           {<<"data">>, [{<<"username">>, Username},
                         {<<"password">>, Password}]}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call(_Cmd, _From, #state{status = <<"not_logged_on">>} = State) ->
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
handle_cast(_Request, State) ->
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
handle_info({gun_ws, Pid, SRef, {close,1000,<<>>}}, #state{conn = Pid, stream = SRef, ref = Ref, ip = Ip, apikey = ApiKey} = State) ->
    erlang:demonitor(Ref),
    gun:close(Pid),
    case connect(Ip, ApiKey) of
        {ok, {MRef, ConnPid, StreamRef}} ->
            io:format("Connection went down. Reconnected.~n"),
            {noreply, State#state{conn = ConnPid, ref = MRef, stream = StreamRef}};
        Error ->
            {stop, Error}
    end;
handle_info({gun_down, Pid, _Proto, _Reason, _Refs0, _Refs1}, #state{conn = Pid, ref = Ref, ip = Ip, apikey = ApiKey} = State) ->
    io:format("Connection ~p down, reconnecting~n", [Pid]),
    erlang:demonitor(Ref),
    {ok, {NRef, NPid, NStream}} = connect(Ip, ApiKey),
    {noreply, State#state{conn = NPid, ref = NRef, stream = NStream}};
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
    connect(Ip, Apikey, 10).

connect(_Ip, _Apikey, 0) ->
    {error, max_reconnects_exceeded};
connect(Ip, Apikey, Rem) ->
    Opts = #{retry => 0},
    io:format("connecting to ~p~n", [Ip]),
    case gun:open(inet_parse:ntoa(Ip), ?SERVER_PORT, Opts) of
        {ok, ConnPid} ->
            case gun:await_up(ConnPid) of
                {ok, _Proto} ->
                    MRef = monitor(process, ConnPid),
                    %% Now we upgrade to websocket
                    Headers = [{<<"x-apikey">>, Apikey}],
                    _StreamRef =  gun:ws_upgrade(ConnPid, ?BASE_PATH, Headers, #{compress => true}),
                    confirm_upgrade(MRef, ConnPid);
                _AwaitError ->
                    gun:close(ConnPid),
                    timer:sleep(timer:seconds(5)),
                    connect(Ip, Apikey, Rem - 1)
            end;
        {error, timeout} ->
            io:format("Connection timeout~n"),
            timer:sleep(timer:seconds(5)),
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
            {error, fucked_conn}
    end.

send(Conn, Packet) ->
    gun:ws_send(Conn, {text, Packet}).

encode(Message) ->
    Json = mochijson2:encode(Message),
    BinMsg = iolist_to_binary(Json),
    {ok, BinMsg}.
