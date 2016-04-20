-module(ss_client_session_sup).
-author("mtokarski").

-behaviour(supervisor).

%% API
-export([start_link/0,start_ss_client_session/2]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

start_ss_client_session(Type,Opts) ->
  supervisor:start_child(?SERVER, [Type,Opts]).

start_link() ->
  lager:debug("Starting ss_client_session_sup"),
  supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
  SupFlags = #{strategy => simple_one_for_one,
    intensity => 0,
    period => 1},
  ChildSpecs = [#{id => ss_client_session,
    restart =>transient,
    start => {ss_client_session, start_link, []},
    shutdown => brutal_kill}],
  {ok, {SupFlags, ChildSpecs}}.