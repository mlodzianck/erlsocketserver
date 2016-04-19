%%%-------------------------------------------------------------------
%%% @author maciejtokarski
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 20. kwi 2016 00:51
%%%-------------------------------------------------------------------
-module(mochiserver_sup).
-author("maciejtokarski").

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

start_link() ->
  supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
  RestartStrategy = one_for_one,
  MaxRestarts = 3,
  MaxSecondsBetweenRestarts = 3600,

  SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

  Restart = permanent,
  Shutdown = 2000,
  Type = worker,

  AChild = {mochi_server, {mochi_server, start_link, []},
    Restart, Shutdown, Type, [mochi_server]},

  {ok, {SupFlags, [AChild]}}.