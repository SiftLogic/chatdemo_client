-module(chatdemo_client).

-define(APIKEY, <<"0b0b9027-9d31-471f-a57e-b0fd2b32ceb7">>).

%% API exports
-export([main/1]).

%%====================================================================
%% API functions
%%====================================================================

%% escript Entry point
main([]) ->
    main(["-h"]);
main(Help) when Help =:= ["-h"] orelse Help =:= ["--help"] ->
    args(),
    usage(),
    erlang:halt(0);
main([ServerIpAddress]) ->
    application:ensure_all_started(gun),
    try chatdemo_conn_sup:start_link([ServerIpAddress, ?APIKEY]) of
        {ok, _Pid} ->
            quit = loop();
        Error ->
            io:format("Error connecting: ~p~n", [Error])
    catch
        E:M ->
            io:format("Error starting connection server: ~p~n", [{E,M}])
    end,
    erlang:halt(0).

%%====================================================================
%% Internal functions
%%====================================================================
args() ->
    io:format("Please provide an IP Address to connect to.~n"
              "EG: _build/default/bin/chatdemo_client 127.0.0.1~n~n").

usage() ->
    io:format(
      "Commands:~n"
      "+++++++++~n"
      "/help or /h - Help~n"
      "/quit or /q - Exit~n"
      "/connect - Reconnect to the server~n"
      "/register USERNAME PASSWORD - register your username/password~n"
      "/login USERNAME PASSWORD - Login~n"
      "/logoff - Logoff and disconnect~n"
      "/password OLDPASSWORD NEWPASSWORD - Change your password~n"
      "/channels - List all channels you're a member of~n"
      "/users - List all users~n"
      "/channel list - List all channels~n"
      "/channel create CHANNEL ACCESS - Register a new channel. ACCESS can be private or public.~n"
      "/channel join CHANNEL - Join a channel~n"
      "/channel leave CHANNEL - Leave a channel~n"
      "/channel members CHANNEL - List all members of a channel~n"
      "/channel delete CHANNEL - Delete the channel. Channel owner only~n"
      "/channel adduser CHANNEL USERNAME ROLE - Add a user to a private channel."
      " Channel owner only. ROLE can be admin or member.~n"
      "/channel kickuser CHANNEL USERNAME - Kick a user off a private channel. Channel owner only~n"
      "/channel CHANNEL MESSAGE - Send a message to a channel~n"
      "/whisper USERNAME MESSAGE - send a private message to a specific USERNAME~n"
      "MESSAGE - broadcast a message to all users~n").

loop() ->
    %% Blocking command waiting for user input. Returns when LF or CRLF received
    Input = io:get_line(">"),
    %% Converted the received line into a command or message
    case to_cmd(Input) of
        conn_kill ->
            exit(whereis(chatdemo_conn), kill),
            loop();
        sup_kill ->
            exit(whereis(chatdemo_conn_sup), kill),
            loop();
        quit ->
            quit;
        help ->
            usage(),
            loop();
        {error, Err} ->
            io:format("ERROR: ~s~n", [Err]),
            loop();
        {_, _, _} = Command ->
            %% Dispatch command to the chatdemo_conn process for handling
            ok = chatdemo_conn:handle_command(Command),
            loop()
    end.

-spec to_cmd(list() | binary()) -> atom() | {atom(), atom() | binary(), atom() | binary()}.
to_cmd(Cmd0) when is_list(Cmd0) ->
    %% Trim leading/trailing spaces
    Cmd1 = re:replace(Cmd0, "(^\\s+)|(\\s+$)", "", [global, {return, binary}]),
    %% Remove linefeed chars
    Cmd = binary:replace(Cmd1, [<<"\r">>,<<"\n">>], <<>>, [global]),
    to_cmd(Cmd);
to_cmd(<<"/conn-kill">>) ->
    conn_kill;
to_cmd(<<"/sup-kill">>) ->
    sup_kill;
to_cmd(Quit) when Quit =:= <<"/q">> orelse Quit =:= <<"/quit">> ->
    quit;
to_cmd(Help) when Help =:= <<"/h">> orelse Help =:= <<"/help">> ->
    help;
to_cmd(<<"/connect">>) ->
    {network, connect, undefined};
to_cmd(<<"/connect ", IpAddress0/binary>>) ->
    {ok, Ip} = inet_parse:address(binary_to_list(IpAddress0)),
    {network, connect, Ip};
to_cmd(<<"/register ", UserPass/binary>>) ->
    [Username, Password] = binary:split(UserPass, <<" ">>),
    {user, register, {Username, Password}};
to_cmd(<<"/login ", UserPass/binary>>) ->
    [Username, Password] = binary:split(UserPass, <<" ">>),
    {user, login, {Username, Password}};
to_cmd(<<"/logoff">>) ->
    {user, logoff, undefined};
to_cmd(<<"/password ", OldNew/binary>>) ->
    [Old, New] = binary:split(OldNew, <<" ">>),
    {user, password, {Old, New}};
to_cmd(<<"/users">>) ->
    {user, list, undefined};
to_cmd(<<"/channels">>) ->
    {user, channels, undefined};
to_cmd(<<"/channel list">>) ->
    {channel, list, undefined};
to_cmd(<<"/channel create ", ChannelAccess/binary>>) ->
    {Channel, Access} = case binary:split(ChannelAccess, <<" ">>) of
                            [Channel0] ->
                                {Channel0, <<"public">>};
                            [Channel0, Access0] ->
                                {Channel0, Access0}
                        end,
    {channel, create, {Channel, Access}};
to_cmd(<<"/channel delete ", Channel/binary>>) ->
    {channel, delete, Channel};
to_cmd(<<"/channel join ", Channel/binary>>) ->
    {channel, join, Channel};
to_cmd(<<"/channel leave ", Channel/binary>>) ->
    {channel, leave, Channel};
to_cmd(<<"/channel members ", Channel/binary>>) ->
    {channel, members, Channel};
to_cmd(<<"/channel adduser ", ChannelUserRole/binary>>) ->
    %% not documented in help
    {Channel, User, Role} =
        case binary:split(ChannelUserRole, <<" ">>, [global]) of
            [_Channel0] ->
                {error, <<"Usage is /channel adduser USERNAME ROLE">>};
            [Channel0, User0] ->
                {Channel0, User0, <<"user">>};
            [Channel0, User0, Role0]
              when Role0 =:= <<"member">> orelse
                   Role0 =:= <<"admin">> ->
                {Channel0, User0, Role0}
        end,
    {channel, adduser, {Channel, User, Role}};
to_cmd(<<"/channel kickuser ", ChannelUser/binary>>) ->
    [Channel, User] = binary:split(ChannelUser, <<" ">>),
    {channel, kickuser, {Channel, User}};
to_cmd(<<"/channel ", Rest/binary>>) ->
    [Channel, Message] = binary:split(Rest, <<" ">>),
    {channel, message, {Channel, Message}};
to_cmd(<<"/whisper ", Rest/binary>>) ->
    [User | Message] = binary:split(Rest, <<" ">>),
    {msg, User, Message};
to_cmd(<<"/", _/binary>>) ->
    {error, <<"Unknown command. See '/help'">>};
to_cmd(Message) ->
    {msg, global, Message}.
