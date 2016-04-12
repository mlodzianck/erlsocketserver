-module(ss_client_session).
-author("maciejtokarski").

-behaviour(gen_server).

%% API
-export([start/2]).

%% gen_server callbacks
-export([init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {type,socket_pid,id}).

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

handle_call(_Request, _From, State) ->
  {reply, ok, State}.


handle_cast(_Request, State) ->
  {noreply, State}.

handle_info(_Info, State) ->
  {noreply, State}.

terminate(Reason, State = #state{id = Id} ) ->
  ss_client_session_mapper:delete(Id),
  error_logger:info_msg("Terminating ss_client_session with id ~s due to ~p",[Id,Reason]),
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.


