%%%-------------------------------------------------------------------
%%% @author mtokarski
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 20. Apr 2016 11:39
%%%-------------------------------------------------------------------
-module(erlsocketserver_sup).
-author("mtokarski").

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
  MaxRestarts = 1000,
  MaxSecondsBetweenRestarts = 3600,

  SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

  Sup_ss_client_session_mapper = #{id => ss_client_session_mapper,
    start => {ss_client_session_mapper, start_link, []},
    restart => permanent,
    shutdown => brutal_kill,
    type => worker,
    modules => [ss_client_session_mapper]},

  Sup_ss_client_session= #{id => ss_client_session_sup,
    start => {ss_client_session_sup, start_link, []},
    restart => permanent,
    shutdown => brutal_kill,
    type => worker,
    modules => [ss_client_session_sup]},


  Mochi_sup= #{id => mochi_server,
    start => {mochi_server, start_link, []},
    restart => permanent,
    shutdown => brutal_kill,
    type => worker,
    modules => [mochi_server]},


  Sup_ss_client_msg_silo= #{id => ss_client_msg_silo,
    start => {ss_client_msg_silo, start_link, []},
    restart => permanent,
    shutdown => brutal_kill,
    type => worker,
    modules => [ss_client_msg_silo]},

  Sup_rnd_gen= #{id => rnd_gen,
    start => {rnd_gen, start_link, []},
    restart => permanent,
    shutdown => brutal_kill,
    type => worker,
    modules => [rnd_gen]},

  {ok, {SupFlags, [Sup_ss_client_session,Sup_ss_client_session_mapper,Mochi_sup,Sup_ss_client_msg_silo,Sup_rnd_gen]}}.
