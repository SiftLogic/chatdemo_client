-module(chatdemo_conn).

-behaviour(gen_server).

%% API
-export([start_link/2]).

-export([set_username/1,
         send_global/1,
         send_user/2]).

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

-record(state, {conn, ref, stream, apikey, ip, user}).

%%%===================================================================
%%% API
%%%===================================================================
set_username(Username) ->
    gen_server:call(?SERVER, {set_username, Username}).

send_global(Message) ->
    gen_server:call(?SERVER, {send_global, Message}).

send_user(User, Message) ->
    gen_server:call(?SERVER, {send_user, User, Message}).

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
    {ok, {MRef, ConnPid, StreamRef}} = connect(Ip, Apikey),
    {ok, #state{conn = ConnPid, ref = MRef, stream = StreamRef, apikey = Apikey, ip = Ip}}.

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
handle_call({set_username, Username}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"set_user">>, Username}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({send_global, Message}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"to">>, <<"all">>},
           {<<"msg">>, Message}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call({send_user, User, _Message}, _From, #state{user = User} = State) ->
    Reply = {error, <<"Why are you trying to send to yourself??">>},
    {reply, Reply, State};
handle_call({send_user, User, Message}, _From, #state{conn = Conn} = State) ->
    Msg = [{<<"to">>, User},
           {<<"msg">>, Message}],
    {ok, Packet} = encode(Msg),
    ok = send(Conn, Packet),
    {reply, ok, State};
handle_call(_Request, _From, State) ->
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
handle_info({gun_down, Pid, _Proto, normal, _Refs0, _Refs1}, #state{conn = Pid, ref = Ref, ip = Ip, apikey = ApiKey} = State) ->
    io:format("Connection ~p down, reconnecting~n", [Pid]),
    erlang:demonitor(Ref),
    {ok, {NRef, NPid, NStream}} = connect(Ip, ApiKey),
    {noreply, State#state{conn = NPid, ref = NRef, stream = NStream}};
handle_info({gun_ws, _ConnPid, _StreamRef, Frame}, State) ->
    Body = mochijson2:decode(Frame),
    From = proplists:get_value(<<"from">>, Body, <<"anonymous">>),
    Msg = proplists:get_value(<<"msg">>, Body, <<"hmmm: empty message">>),
    Private = proplists:get_value(<<"private">>, Body, false),
    case Private of
        true ->
            io:format("~s whispers: ~s~n", [From, Msg]);
        false ->
            io:format("~s says: ~s~n", [From, Msg])
    end,
    {noreply, State};
handle_info(_Info, State) ->
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
    Opts = #{retry => 0},
    io:format("connecting to ~p~n", [Ip]),
    case gun:open(Ip, ?SERVER_PORT, Opts) of
        {ok, ConnPid} ->
            case gun:await_up(ConnPid) of
                {ok, http} ->
                    MRef = monitor(process, ConnPid),
                    %% Now we upgrade to websocket
                    Headers = [{<<"x-apikey">>, Apikey}],
                    StreamRef =  gun:ws_upgrade(ConnPid, ?BASE_PATH, Headers, #{compress => true}),
                    receive
                        {gun_upgrade, ConnPid, StreamRef, [<<"websocket">>], _} ->
                            {ok, {MRef, ConnPid, StreamRef}};
                        Msg ->
                            io:format("Unexpected message in socket upgrade ~p", [Msg]),
                            {error, connect_failed}
                    end;
                AwaitError ->
                    gun:close(ConnPid),
                    io:format("Await error: ~p~n", [AwaitError]),
                    {error, connect_failed}
            end;
        {error, timeout} ->
            io:format("Connection timeout~n"),
            {error, connect_timeout}
    end.

send(Conn, Packet) ->
    gun:ws_send(Conn, {text, Packet}).

encode(Message) ->
    Json = mochijson2:encode(Message),
    BinMsg = iolist_to_binary(Json),
    {ok, BinMsg}.
