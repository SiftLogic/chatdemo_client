%%%-------------------------------------------------------------------
%%% @doc
%%%     Supervise the connection to the server
%%% @end
%%%-------------------------------------------------------------------
-module(chatdemo_conn_sup).

-behaviour(supervisor).

%% API
-export([start_link/1]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

start_link(Args) ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, Args).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

init([ServerIpAddress, ApiKey]) ->
    Worker = {chatdemo_conn,
              {chatdemo_conn, start_link, [ServerIpAddress, ApiKey]},
              permanent,
              10000,
              worker,
              [chatdemo_conn]},
    {ok, {{one_for_one, 1000, 10}, [Worker]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
