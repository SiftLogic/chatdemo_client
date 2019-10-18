-module(chatdemo).

-define(APIKEY, <<"0b0b9027-9d31-471f-a57e-b0fd2b32ceb7">>).

%% API exports
-export([main/1]).

%%====================================================================
%% API functions
%%====================================================================

%% escript Entry point
main(Help) when Help =:= ["-h"] orelse Help =:= ["--help"] ->
    usage(),
    erlang:halt(0);
main([ServerIpAddress]) ->
    {ok, _Pid} = chatdemo_conn:start_link(ServerIpAddress, ?APIKEY),
    quit = loop(),
    erlang:halt(0).

%%====================================================================
%% Internal functions
%%====================================================================

usage() ->
    io:format("/q - Exit~n"
              "/u USERNAME - set your username~n"
              "/USERNAME MESSAGE - send a message to a specific USERNAME~n"
              "MESSAGE - broadcast a message to all users~n").

loop() ->
    case io:get_line(">") of
        "/q\n" ->
            quit;
        "/h\n" ->
            usage(),
            loop();
        Data0 ->
            Data1 = re:replace(Data0, "(^\\s+)|(\\s+$)", "", [global, {return, binary}]),
            case handle_command(Data1) of
                ok ->
                    ok;
                {error, Msg} ->
                    io:format("Error: ~s~n", [Msg])
            end,
            loop()
    end.

handle_command(<<"/u ", Username/binary>>) ->
    chatdemo_conn:set_username(Username);
handle_command(<<"/", Rest/binary>>) ->
    [User | Message] = binary:split(Rest, <<" ">>),
    chatdemo_conn:send_user(User, Message);
handle_command(Message) ->
    chatdemo_conn:send_global(Message).


