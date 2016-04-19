-module(ss_client_msg_silo).

-behaviour(gen_server).

-export([start_link/0, store/2, fetch/1]).

-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).
-define(CLEANUP_INTERVAL, 1000*60).
-define(EVICT_AFTER, 1000 * 60 * 5). %%5 mins

-record(state, {
  silo = #{},
  silo_meta = #{}
}).

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

store(Key, Term) ->
  gen_server:call(?SERVER, {store, Key, Term}).

fetch(Key) ->
  gen_server:call(?SERVER, {fetch, Key}).

init([]) ->
  erlang:send_after(?CLEANUP_INTERVAL, self(), cleanup),
  {ok, #state{}}.

handle_call({store, Key, Term}, _From, State = #state{silo = Silo, silo_meta = Meta}) ->
  lager:debug("Storing key ~p in silo", [Key]),
  case maps:find(Key,Silo) of
    error -> noop;
    {ok,V}-> lager:warning("Already have data for key ~p, data =~p",[Key,V])
  end,
  NewSilo = Silo#{Key => Term},
  NewMeta = Meta#{Key => #{creation_time => erlang:system_time(milli_seconds)}},
  {reply, ok, State#state{silo = NewSilo, silo_meta = NewMeta}};
handle_call({fetch, Key}, _From, State = #state{silo = Silo}) ->
  case maps:find(Key, Silo) of
    {ok, Term} ->
      lager:debug("Fetching key ~p from silo", [Key]),
      NewSilo = maps:remove(Key, State#state.silo),
      NewMeta = maps:remove(Key, State#state.silo_meta),
      {reply, Term, State#state{silo = NewSilo, silo_meta = NewMeta}};
    _ ->
      lager:debug("Key ~p not found in silo", [Key]),
      {reply, {error, not_found}, State}
  end.

handle_cast(_Request, State) ->
  {noreply, State}.

handle_info(cleanup, State = #state{silo = Silo, silo_meta = Meta}) ->
  lager:debug("Running cleanup procedure"),
  Now = erlang:system_time(milli_seconds),

  MetaPred = fun(_, #{creation_time := V}) -> Now - V < ?EVICT_AFTER end,
  NewMeta = maps:filter(MetaPred, Meta),

  SiloPred = fun(K, _) -> maps:find(K, NewMeta) =/= error end,
  NewSilo = maps:filter(SiloPred, Silo),

  lager:debug("Cleanup  evicted ~p keys", [maps:size(Silo) - maps:size(NewSilo)]),
  erlang:send_after(?CLEANUP_INTERVAL, self(), cleanup),
  {noreply, State#state{silo_meta = NewMeta, silo = NewSilo}};
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.