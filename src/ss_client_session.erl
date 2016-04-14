-module(ss_client_session).
-author("maciejtokarski").

-behaviour(gen_server).

%% API
-export([start/2,send_to_socket/2,receive_from_socket/2,poll/2]).

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
  poll_fun = undefined,
  to_client_queue = [], terminate_after_next_poll=false}).
poll(Pid,Fun) ->
  gen_server:cast(Pid,{poll,Fun}).

send_to_socket(Pid,Bin) ->
  gen_server:call(Pid,{send_to_socket,Bin}).

receive_from_socket(Pid,{data,Bin}) ->
  gen_server:cast(Pid,{receive_from_socket,{data,Bin}});
receive_from_socket(Pid,{soket_closed}) ->
  gen_server:cast(Pid,{soket_closed}).

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




handle_call({send_to_socket,Bin}, _From, State=#state{type = tcp_client,socket_pid = SocketPid }) ->
  {reply, tcp_client_socket:send(SocketPid,Bin), State}.

handle_cast({poll,Fun}, State=#state{to_client_queue = [],poll_fun = undefined}) ->
  {noreply, State#state{poll_fun = Fun}};

handle_cast({poll,PollFun}, State=#state{to_client_queue = Queue,terminate_after_next_poll = true,poll_fun = undefined}) ->
  PollRet = (catch PollFun(Queue)),
  case PollRet of
    ok ->  {stop,normal, State#state{to_client_queue = [],poll_fun = undefined}};
    _->
      error_logger:info_msg("Failed to invoke poll fun, it exited with result ~p",[PollRet]),
      {noreply, State#state{terminate_after_next_poll= true,poll_fun = undefined}}
  end;

handle_cast({poll,PollFun}, State=#state{to_client_queue = Queue,poll_fun = undefined}) ->
  PollRet = (catch PollFun(Queue)),
  case PollRet of
    ok ->{noreply, State#state{to_client_queue = [],poll_fun = undefined}};
    _ ->
      error_logger:info_msg("Failed to invoke poll fun, it exited with result ~p",[PollRet]),
      {noreply, State#state{poll_fun = undefined}}
  end;




handle_cast({soket_closed}, State = #state{poll_fun = undefined, to_client_queue = ToClientQueue}) ->
  error_logger:info_msg("Got soket_closed directly but no poll, queueing it "),
  Msg = {event,#{event_type => socket_closed}},
  {noreply, State#state{to_client_queue = ToClientQueue++[Msg],terminate_after_next_poll= true}};

handle_cast({soket_closed}, State=#state{poll_fun = PollFun,to_client_queue = ToClientQueue}) when is_function(PollFun)->
  error_logger:info_msg("Forwarding soket_closed directly form socket to poll"),
  Msg = {event,#{event_type => socket_closed}},
  PollRet = (catch PollFun([Msg])),
  case PollRet of
    ok ->  {stop, normal,State#state{poll_fun = undefined}};
    _->
      error_logger:info_msg("Failed to invoke poll fun, it exited with result ~p",[PollRet]),
      {noreply, State#state{to_client_queue = ToClientQueue++[Msg],terminate_after_next_poll= true,poll_fun = undefined}}
  end;



handle_cast({receive_from_socket,{data,Bin}}, State = #state{poll_fun = undefined, to_client_queue = ToClientQueue}) ->
  error_logger:info_msg("Got data from socket but no poll fun, queueing ~p bytes",[byte_size(Bin)]),
  {noreply, State#state{to_client_queue = ToClientQueue++[{data,Bin}]}};

handle_cast({receive_from_socket,{data,Bin}}, State=#state{poll_fun = PollFun,to_client_queue = ToClientQueue}) when is_function(PollFun)->
  error_logger:info_msg("Forwarding data directly form socket to poll fun, data len  = ~p",[byte_size(Bin)]),
  PollRet = (catch PollFun([{data,Bin}])),
  case PollRet of
    ok ->  {noreply, State#state{poll_fun = undefined}};
    _->
      error_logger:info_msg("Failed to invoke poll fun, it exited with result ~p",[PollRet]),
      {noreply, State#state{to_client_queue = ToClientQueue++[{data,Bin}],poll_fun = undefined}}
  end.


handle_info({'EXIT',SocketPid,Reason}, State=#state{socket_pid = SocketPid}) ->
  error_logger:info_msg("Socket process died due to ~p",[Reason]),
  {noreply, State#state{socket_pid = undefined}};
handle_info(Info, State) ->
  error_logger:info_msg("Got other Info ~p",[Info]),
  {noreply, State}.

terminate(Reason, #state{id = Id,socket_pid = SocketPid} ) ->
  ss_client_session_mapper:delete(Id),
  case SocketPid of
    Pid when is_pid(Pid) -> tcp_client_socket:stop(SocketPid);
    _ -> noop
  end,
  error_logger:info_msg("Terminating ss_client_session with id ~s due to ~p",[Id,Reason]),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.
