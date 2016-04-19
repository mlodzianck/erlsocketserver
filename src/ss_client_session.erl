-module(ss_client_session).
-author("maciejtokarski").

-behaviour(gen_server).

%% API
-export([start/2,
  send_to_socket/2,
  receive_from_socket/2,
  close_socket/1,
  set_poll_fun/2]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {type,
  socket_pid,
  id,
  to_client_queue = [],
  poll_fun = undefined,
  counter = 0, rcvd_cnt = 0}).
set_poll_fun(Pid, Fun) ->
  gen_server:cast(Pid, {set_poll_fun, Fun}).

send_to_socket(Pid, Bin) ->
  gen_server:call(Pid, {send_to_socket, Bin}).

receive_from_socket(Pid, {data, Bin}) ->
  gen_server:cast(Pid, {receive_from_socket, {data, Bin}});
receive_from_socket(Pid, {soket_closed}) ->
  gen_server:cast(Pid, {soket_closed}).

close_socket(Pid) ->
  gen_server:call(Pid, {close_socket}).

start(Type, Opts) ->
  Id = utils:generate_random_str(10),
  {ok, Pid} = gen_server:start(?MODULE, {Type, Id}, []),
  ok = ss_client_session_mapper:put(Id, Pid),
  case gen_server:call(Pid, {bootstrap, Opts}) of
    ok -> {ok, Id};
    {error, Err} -> {error, Err}
  end.



init({tcp_client, Id}) ->
  process_flag(trap_exit, true),
  {ok, #state{type = tcp_client, id = Id}}.


handle_call({bootstrap, #{ipaddr := IpAddr, port := Port}}, _From, State = #state{type = tcp_client}) ->
  Self = self(),
  case tcp_client_socket:start(IpAddr, Port, Self) of
    {ok, SocketPid} ->
      link(SocketPid),
      {reply, ok, State#state{socket_pid = SocketPid}};
    {error, Err} ->
      lager:debug("Got error ~p while starting tcp_client_socket ipaddr = ~p , port = ~p", [Err, IpAddr, Port]),
      {stop, normal, {error, {tcp_client_err, Err}}, State}
  end;


handle_call({close_socket}, _From, State = #state{type = tcp_client, socket_pid = undefined, to_client_queue = Queue}) ->
  lager:debug("Client close_socket request while there's no socket bound"),
  {stop, normal, Queue, State#state{to_client_queue = []}};

handle_call({close_socket}, _From, State = #state{type = tcp_client, socket_pid = SocketPid, to_client_queue = Queue, rcvd_cnt = RCnt}) ->
  lager:debug("Client close_socket request"),
  tcp_client_socket:stop(SocketPid),
  {stop, normal,ok, State#state{to_client_queue =  Queue ++ [socked_closed_event(RCnt)]}};


handle_call({send_to_socket, Bin}, _From, State = #state{type = tcp_client, socket_pid = SocketPid}) ->
  {reply, tcp_client_socket:send(SocketPid, Bin), State}.


handle_cast({set_poll_fun, PollFun}, State = #state{to_client_queue = []}) ->
  {noreply, State#state{poll_fun = PollFun}};


handle_cast({set_poll_fun, PollFun}, State = #state{to_client_queue = ToClientQueue, counter = Cnt}) ->
  case invoke_poll_fun(PollFun, ToClientQueue) of
    ok -> {noreply, State#state{to_client_queue = [], poll_fun = undefined, counter = Cnt + length(ToClientQueue)}};
    fail -> {noreply, State#state{poll_fun = undefined}}
  end;


handle_cast({soket_closed}, State = #state{poll_fun = undefined, to_client_queue = ToClientQueue, rcvd_cnt = RCnt, id = Id}) ->
  lager:debug("Socket reported close, storing queue in silo, since we don't have poll fun present"),
  Queue = ToClientQueue ++ [socked_closed_event(RCnt)],
  ss_client_msg_silo:store(Id, Queue),
  {stop, normal, State#state{to_client_queue = []}};

handle_cast({soket_closed}, State = #state{poll_fun = PollFun, to_client_queue = ToClientQueue, rcvd_cnt = RCnt, id = Id}) ->
  Queue = ToClientQueue ++ [socked_closed_event(RCnt)],
  case invoke_poll_fun(PollFun, Queue) of
    fail ->
      lager:debug("Socket reported close, storing queue in silo, since poll fn returned error"),
      ss_client_msg_silo:store(Id, Queue);
    _ -> noop
  end,
  {stop, normal, State#state{poll_fun = undefined, to_client_queue = []}};


handle_cast({receive_from_socket, {data, Bin}}, State = #state{poll_fun = undefined, to_client_queue = ToClientQueue, counter = Cnt, rcvd_cnt = RCnt}) ->
  Msg = [data_event(Bin)],
  {noreply, State#state{to_client_queue = ToClientQueue ++ Msg, rcvd_cnt = RCnt + 1}};

handle_cast({receive_from_socket, {data, Bin}}, State = #state{poll_fun = PollFun, to_client_queue = ToClientQueue, counter = Cnt, rcvd_cnt = RCnt}) ->
  Msg = [data_event(Bin)],
  case invoke_poll_fun(PollFun, Msg) of
    ok -> {noreply, State#state{rcvd_cnt = RCnt + 1, counter = Cnt + 1, poll_fun = undefined}};
    fail -> {noreply, State#state{rcvd_cnt = RCnt + 1, poll_fun = undefined, to_client_queue = ToClientQueue ++ [Msg]}}
  end.


handle_info({'EXIT', SocketPid, Reason}, State = #state{socket_pid = SocketPid, poll_fun = PollFun}) ->
  lager:debug("Socket process exited due to  ~p", [Reason]),
  {stop, normal, State#state{socket_pid = undefined}};
handle_info(Info, State) ->
  lager:debug("Other info received ~p", [Info]),
  {noreply, State}.

terminate(Reason, #state{id = Id, socket_pid = SocketPid, counter = Counter, to_client_queue = Queue, rcvd_cnt = Rcnt}) ->
  if
    length(Queue) > 0 -> error_logger:error_msg("Queue has len > 0 ( ~p ) storing to silo", [length(Queue)]),
                         ss_client_msg_silo:store(Id, Queue);
    true -> ok
  end,
  ss_client_session_mapper:delete(Id),
  case SocketPid of
    Pid when is_pid(Pid) -> tcp_client_socket:stop(SocketPid);
    _ -> noop
  end,
  lager:debug("Terminating ss_client_session with id ~s due to ~p, rcvd_cnt =  ~p", [Id, Reason, Rcnt]),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


data_event(Bin) when is_binary(Bin) -> #{event_type => data, payload => Bin}.
socked_closed_event(RCnt) -> #{event_type => socket_closed, total_rcvd =>RCnt}.

invoke_poll_fun(PollFun, Msg) ->
  case (catch PollFun(Msg)) of
    ok -> ok;
    Other -> lager:debug("Failed to invoke poll fun, result of invocation ~p", [Other]),
      fail
  end.