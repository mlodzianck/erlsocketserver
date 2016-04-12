-module(ss_client_session_mapper).
-author("maciejtokarski").

-behaviour(gen_server).

-export([start_link/0,put/2,get/1,delete/1]).

-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {mappings}).


put(Id,Pid) ->
  gen_server:call(?MODULE,{put,Id,Pid}).

get(Id) ->
  gen_server:call(?MODULE,{get,Id}).

delete(Id) ->
  gen_server:call(?MODULE,{delete,Id}).

start_link() ->
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

init([]) ->
  {ok, #state{mappings=#{}}}.



handle_call({put,Id,Pid}, _From, State=#state{mappings = M}) ->
  case maps:is_key(Id,M) of
    false ->   {reply, ok, State#state{mappings = M#{Id => Pid}}};
    _ -> {reply, {error,already_exist}, State}
  end;


handle_call({get,Id}, _From, State=#state{mappings =  M}) ->
  case maps:is_key(Id,M) of
    true ->   {reply, maps:get(Id,M), State};
    _ -> {reply, {error,not_exist}, State}
  end;

handle_call({delete,Id}, _From, State=#state{mappings = M}) ->
  case maps:is_key(Id,M) of
    true ->   {reply, ok, State#state{mappings = maps:remove(Id,State#state.mappings)}};
    _ -> {reply, {error,not_exist}, State}
  end;


handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Request, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
