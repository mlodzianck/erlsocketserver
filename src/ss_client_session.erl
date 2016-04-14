-module(ss_client_session).
-author("maciejtokarski").

-behaviour(gen_server).

%% API
-export([start/2,
  send_to_socket/2,
  receive_from_socket/2,
  set_poll_pid/2,
  set_poll_pid/1,
  unset_poll_pid/1,
  unset_poll_pid/2,
  close_socket/1]).

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
  poll_pid,
  counter=0}).
set_poll_pid(Pid)->
  Caller = self(),
  gen_server:cast(Pid,{set_poll_pid,Caller}).
set_poll_pid(Pid,PollPid) ->
  gen_server:cast(Pid,{set_poll_pid,PollPid}).

unset_poll_pid(Pid)->
  Caller = self(),
  gen_server:cast(Pid,{unset_poll_pid,Caller}).
unset_poll_pid(Pid,PollPid) ->
  gen_server:cast(Pid,{unset_poll_pid,PollPid}).


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

handle_call({close_socket}, _From, State=#state{type = tcp_client,socket_pid = SocketPid,to_client_queue = Queue }) ->
  ok =gen_tcp:close(SocketPid),
  {stop,normal, Queue++[socked_closed_event()], State};

handle_call({send_to_socket,Bin}, _From, State=#state{type = tcp_client,socket_pid = SocketPid }) ->
  {reply, tcp_client_socket:send(SocketPid,Bin), State}.

handle_cast({set_poll_pid,PollPid}, State=#state{to_client_queue = []}) ->
  link(PollPid),
  {noreply, State#state{poll_pid = PollPid}};

handle_cast({set_poll_pid,PollPid}, State=#state{to_client_queue = Queue,terminate_after_next_poll = true}) ->
  PollPid ! Queue,
  {stop,normal, State#state{to_client_queue = [],poll_pid = undefined}};

handle_cast({set_poll_pid,PollPid}, State=#state{to_client_queue = Queue}) ->
  PollPid ! Queue,
  {noreply, State#state{to_client_queue = [],poll_pid = undefined}};

handle_cast({unset_poll_pid,PollPid}, State=#state{poll_pid = OurPollPid}) when OurPollPid =/= PollPid  ->
  error_logger:warning_msg("Request for unset poll pid with invalid value our = ~p , requested = ~p",[PollPid,OurPollPid]),
  {noreply, State};

handle_cast({unset_poll_pid,PollPid}, State=#state{poll_pid = PollPid}) ->
  error_logger:warning_msg("Unsetting poll_pid= ~p",[PollPid]),
  unlink(PollPid),
  {noreply, State#state{to_client_queue = [],poll_pid = undefined}};



handle_cast({soket_closed}, State = #state{poll_pid  = undefined, to_client_queue = ToClientQueue}) ->
  error_logger:info_msg("Got soket_closed directly but no poll, queueing it "),
  Msg = socked_closed_event(),
  {noreply, State#state{to_client_queue = ToClientQueue++[Msg],terminate_after_next_poll= true}};

handle_cast({soket_closed}, State=#state{poll_pid  = PollPid,to_client_queue = ToClientQueue}) ->
  error_logger:info_msg("Forwarding soket_closed directly form socket to poll"),
  Msg = socked_closed_event(),
  PollPid ! ToClientQueue ++ [Msg],
  unlink(PollPid),
  {stop, normal,State#state{poll_pid = undefined}};


handle_cast({receive_from_socket,{data,Bin}}, State = #state{poll_pid = undefined, to_client_queue = ToClientQueue,counter = Cnt}) ->
  error_logger:info_msg("Got data from socket but no poll fun, queueing ~p bytes",[byte_size(Bin)]),
  Msg = data_event(Bin),
  {noreply, State#state{counter = Cnt+1,to_client_queue = ToClientQueue++[Msg]}};

handle_cast({receive_from_socket,{data,Bin}}, State=#state{poll_pid = PollPid,to_client_queue = ToClientQueue,counter = Cnt})->
  error_logger:info_msg("Forwarding data directly form socket to poll fun, data len  = ~p",[byte_size(Bin)]),
  Msg = data_event(Bin),
  PollPid ! ToClientQueue ++ [Msg],
  unlink(PollPid),
  {noreply, State#state{counter = Cnt+1,poll_pid = undefined}}.


handle_info({'EXIT',SocketPid,normal}, State=#state{socket_pid = SocketPid}) ->
  error_logger:info_msg("Socket process died due to ~p, but we already know about it",[normal]),
  {noreply, State#state{socket_pid = undefined}};
handle_info({'EXIT',PollPid,Reason}, State=#state{poll_pid  = PollPid}) ->
  error_logger:info_msg("poll_pid process died due to ~p",[Reason]),
  {noreply, State#state{poll_pid  = undefined}};
handle_info(Info, State) ->
  error_logger:info_msg("Got other Info ~p",[Info]),
  {noreply, State}.

terminate(Reason, #state{id = Id,socket_pid = SocketPid,counter = Counter} ) ->
  ss_client_session_mapper:delete(Id),
  case SocketPid of
    Pid when is_pid(Pid) -> tcp_client_socket:stop(SocketPid);
    _ -> noop
  end,
  error_logger:info_msg("Terminating ss_client_session with id ~s due to ~p, counter = ~p",[Id,Reason,Counter]),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


data_event(Bin) when is_binary(Bin) -> #{event_type => data,payload => Bin}.
socked_closed_event()  -> #{event_type => socket_closed}.