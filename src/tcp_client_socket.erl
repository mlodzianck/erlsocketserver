-module(tcp_client_socket).
-author("maciejtokarski").

-behaviour(gen_server).

-export([start/3,send/2,stop/1]).

-define(CONNECT_TIMEOUT,1000).

-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {socket,client_session_pid}).

stop(Pid) ->
  gen_server:cast(Pid,{stop}).

send(Pid,Bin) ->
  gen_server:call(Pid,{send,Bin}).

start(IpAddr,Port,ClientSessionPid) ->
  gen_server:start(?MODULE, {IpAddr,Port,ClientSessionPid}, []).

init({IpAddr,Port,ClientSessionPid}) ->
  case gen_tcp:connect(IpAddr, Port, [{active, once}, {mode, binary}], ?CONNECT_TIMEOUT) of
    {ok, Socket}->  {ok, #state{socket = Socket,client_session_pid = ClientSessionPid}};
    {error,Reason} -> {stop,{connect_error,Reason}}
  end.


handle_call({send,Bin}, _From, State=#state{socket = Socket}) ->
  {reply, gen_tcp:send(Socket,Bin), State}.

handle_cast({stop}, State) ->
  {stop,normal, State};
handle_cast(_Request, State) ->
  {noreply, State}.


handle_info({tcp, _, Bin}, State = #state{client_session_pid = SSPid}) ->
  inet:setopts(State#state.socket, [{active, once}]),
  ss_client_session:receive_from_socket(SSPid,{data,Bin}),
  {noreply, State};

handle_info({tcp_closed,Socket}, State=#state{socket= Socket,client_session_pid = SSPid}) ->
  lager:debug("Socket closed (by remote??)"),
  ss_client_session:receive_from_socket(SSPid,{soket_closed}),
  {stop,normal, State};

handle_info(Info, State) ->
 lager:debug("Got other info from socket ~p",[Info]),
  {noreply, State}.

terminate(_Reason, _State) ->
 lager:debug("Terminating tcp_client_socket process"),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
