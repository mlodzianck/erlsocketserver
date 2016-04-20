-module(rnd_gen).
-author("mtokarski").

-behaviour(gen_server).

%% API
-export([start_link/0]).
-export([gen_random_id/0]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).
-define(DEF_ID_LEN, 10).

-record(state, {}).

start_link() ->
  <<A:32, B:32, C:32>> = crypto:strong_rand_bytes(12),
  random:seed({A,B,C}),
  gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).
gen_random_id() ->
  gen_server:call(?SERVER,{gen_random_id}).

init([]) ->
  {ok, #state{}}.

handle_call({gen_random_id}, _From, State) ->
  {reply, generate_random_str(?DEF_ID_LEN), State}.


handle_cast(_Request, State) ->
  {noreply, State}.


handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


get_random_string(Length, AllowedChars) ->
  [lists:nth(rand:uniform(length(AllowedChars)),AllowedChars) ||  _ <- lists:seq(0,Length-1) ].


generate_random_str(Len) ->
  get_random_string(Len,"QWERTYUIOPASDFGHJKLZXCVBNMqwertyuiopasdfghjklzxcvbnm1234567890").