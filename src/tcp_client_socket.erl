-module(tcp_client_socket).
-author("maciejtokarski").

-behaviour(gen_server).

-export([start/3]).

-define(CONNECT_TIMEOUT,1000).

-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {socket,client_session_pid}).

start(IpAddr,Port,ClientSessionPid) ->
  gen_server:start(?MODULE, {IpAddr,Port,ClientSessionPid}, []).

init({IpAddr,Port,ClientSessionPid}) ->
  case gen_tcp:connect(IpAddr, Port, [{active, once}, {mode, binary}], ?CONNECT_TIMEOUT) of
    {ok, Socket}->  {ok, #state{socket = Socket,client_session_pid = ClientSessionPid}};
    {error,Reason} -> {stop,{connect_error,Reason}}
  end.


handle_call(_Request, _From, State) ->
  {reply, ok, State}.

handle_cast(_Request, State) ->
  {noreply, State}.
handle_info({tcp, _, Bin}, State ) ->
  inet:setopts(State#state.socket, [{active, once}]),
  {noreply, State};
handle_info(_Info, State) ->
  {noreply, State}.

terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
