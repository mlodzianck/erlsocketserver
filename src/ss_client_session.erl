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
  terminate_after_next_poll=false,
  poll_fun = undefined,
  counter=0,rcvd_cnt=0}).
set_poll_fun(Pid,Fun)->
  gen_server:cast(Pid,{set_poll_fun,Fun}).

send_to_socket(Pid,Bin) ->
  gen_server:call(Pid,{send_to_socket,Bin}).

receive_from_socket(Pid,{data,Bin}) ->
  gen_server:cast(Pid,{receive_from_socket,{data,Bin}});
receive_from_socket(Pid,{soket_closed}) ->
  gen_server:cast(Pid,{soket_closed}).

close_socket(Pid) ->
  gen_server:call(Pid,{close_socket}).

start(Type,Opts) ->
  Id = utils:generate_random_str(10),
  {ok,Pid} = gen_server:start(?MODULE, {Type,Id}, []),
  ok = ss_client_session_mapper:put(Id,Pid),
  case gen_server:call(Pid,{bootstrap,Opts}) of
    ok ->  {ok,Id};
    {error,Err} -> {error,Err}
  end.



init({tcp_client,Id}) ->
  process_flag(trap_exit,true),
  {ok, #state{type = tcp_client,id=Id}}.


handle_call({bootstrap,#{ipaddr := IpAddr, port := Port}}, _From, State = #state{type = tcp_client}) ->
  Self = self(),
  case tcp_client_socket:start(IpAddr,Port,Self) of
    {ok,SocketPid} ->
      link(SocketPid),
      {reply, ok, State#state{socket_pid = SocketPid}};
    {error,Err} ->
      error_logger:info_msg("Got error ~p while starting tcp_client_socket ipaddr = ~p , port = ~p",[Err,IpAddr,Port]),
      {stop,normal,{error,{tcp_client_err,Err}},State}
  end;


handle_call({close_socket}, _From, State=#state{type = tcp_client,socket_pid = undefined,to_client_queue = Queue }) ->
  {stop,normal, Queue, State};

handle_call({close_socket}, _From, State=#state{type = tcp_client,socket_pid = SocketPid,to_client_queue = Queue,rcvd_cnt = RCnt}) ->
  ok =gen_tcp:close(SocketPid),
  {stop,normal, Queue++[socked_closed_event(RCnt)], State};


handle_call({send_to_socket,Bin}, _From, State=#state{type = tcp_client,socket_pid = SocketPid }) ->
  {reply, tcp_client_socket:send(SocketPid,Bin), State}.


handle_cast({set_poll_fun,PollFun}, State=#state{to_client_queue = []}) ->
  error_logger:info_msg("Setting poll fun with empty Q"),
  {noreply, State#state{poll_fun = PollFun}};

handle_cast({set_poll_fun,PollFun}, State=#state{to_client_queue = ToClientQueue,counter = Cnt,terminate_after_next_poll = true}) ->
  error_logger:info_msg("Setting poll fun with  Q len ~p ",[length(ToClientQueue)]),

  case invoke_poll_fun(PollFun,ToClientQueue) of
    ok -> {stop,normal, State#state{to_client_queue = [],poll_fun = undefined,counter = Cnt+length(ToClientQueue)}};
    fail -> {noreply, State#state{poll_fun = undefined}}
  end;

handle_cast({set_poll_fun,PollFun}, State=#state{to_client_queue = ToClientQueue,counter = Cnt}) ->
  error_logger:info_msg("Setting poll fun with  Q len ~p ",[length(ToClientQueue)]),
  case invoke_poll_fun(PollFun,ToClientQueue) of
    ok -> {noreply, State#state{to_client_queue = [],poll_fun  = undefined,counter = Cnt+length(ToClientQueue)}};
    fail -> {noreply, State#state{poll_fun = undefined}}
  end;


handle_cast({soket_closed}, State = #state{poll_fun = undefined, to_client_queue = ToClientQueue,rcvd_cnt = RCnt}) ->
  error_logger:info_msg("Got soket_closed directly but no poll, queueing it "),
  Msg = [socked_closed_event(RCnt)],
  {noreply, State#state{to_client_queue = ToClientQueue++Msg,terminate_after_next_poll= true}};

handle_cast({soket_closed}, State=#state{poll_fun  = PollFun,to_client_queue = ToClientQueue,rcvd_cnt = RCnt}) ->
%%  error_logger:info_msg("Forwarding soket_closed directly form socket to poll"),
  Msg = [socked_closed_event(RCnt)],
  case invoke_poll_fun(PollFun,Msg) of
    ok -> {stop, normal,State#state{poll_fun = undefined}};
    fail -> {noreply, State#state{poll_fun = undefined,to_client_queue = ToClientQueue++Msg}}
  end;



handle_cast({receive_from_socket,{data,Bin}}, State = #state{poll_fun = undefined, to_client_queue = ToClientQueue,counter = Cnt,rcvd_cnt = RCnt}) ->
%%  error_logger:info_msg("Got data from socket but no poll fun, queueing ~p bytes",[byte_size(Bin)]),
  Msg = [data_event(Bin)],
  {noreply, State#state{to_client_queue = ToClientQueue++Msg,rcvd_cnt = RCnt+1}};

handle_cast({receive_from_socket,{data,Bin}}, State=#state{poll_fun  = PollFun,to_client_queue = ToClientQueue,counter = Cnt,rcvd_cnt = RCnt})->
  error_logger:info_msg("Forwarding data directly form socket to poll fun, data len  = ~p",[byte_size(Bin)]),
  Msg = [data_event(Bin)],
  case invoke_poll_fun(PollFun,Msg) of
    ok -> {noreply, State#state{rcvd_cnt = RCnt+1,counter = Cnt+1,poll_fun = undefined}};
    fail -> {noreply, State#state{rcvd_cnt = RCnt+1,poll_fun = undefined,to_client_queue = ToClientQueue++[Msg]}}
  end.


handle_info({'EXIT',SocketPid,normal}, State=#state{socket_pid = SocketPid}) ->
  error_logger:info_msg("Socket process died due to ~p, but we already know about it",[normal]),
  {noreply, State#state{socket_pid = undefined}};
handle_info(Info, State) ->
  error_logger:info_msg("Got other Info ~p",[Info]),
  {noreply, State}.

terminate(Reason, #state{id = Id,socket_pid = SocketPid,counter = Counter,to_client_queue = Queue,rcvd_cnt = Rcnt} ) ->
  if
    length(Queue) >0 -> error_logger:error_msg("Queue has len > 0 , ~p",[length(Queue)]);
    true -> ok
  end,
  ss_client_session_mapper:delete(Id),
  case SocketPid of
    Pid when is_pid(Pid) -> tcp_client_socket:stop(SocketPid);
    _ -> noop
  end,
  error_logger:info_msg("Terminating ss_client_session with id ~s due to ~p, rcvd_cnt =  ~p",[Id,Reason,Rcnt]),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


data_event(Bin) when is_binary(Bin) -> #{event_type => data,payload => Bin}.
socked_closed_event(RCnt)  -> #{event_type => socket_closed,total_rcvd =>RCnt }.



invoke_poll_fun(PollFun,Msg) ->
  case (catch PollFun(Msg)) of
    ok -> ok;
    Other -> error_logger:info_msg("Failed to invoke poll fun, result of invocation ~p",[Other]),
              fail
  end.