%%%-------------------------------------------------------------------
%%% @author maciejtokarski
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 10. kwi 2016 21:47
%%%-------------------------------------------------------------------
-module(t).
-author("maciejtokarski").

%% API
-export([]).
-compile(export_all).

setup() ->

  observer:start(),
  application:start(erlsocketserver).


t() ->
  lager:debug("mochi started with pid ~p", [mochiserver_sup:start_link()]).

t1() ->

  {ok, SSPid} = ss_client_session_sup:start_ss_client_session(tcp_client, #{ipaddr => "wp.pl", port => 80}),
  Id = ss_client_session:get_id(SSPid),
  lager:debug("~p ", [Id]),
  Pid = ss_client_session_mapper:get(Id),
  lager:debug("Pid for id ~p = ~p",[Id,Pid]),
  ss_client_session:send_to_socket(Pid, list_to_binary("GET / HTTP/1.1\r\nHost: www.wp.pl\r\n\r\n")),
%%  ss_client_session:close_socket(Pid),


  receive
  after 6000 ->ok
  end,

  Pid2 = ss_client_session_mapper:get(Id),
  lager:debug("Pid2 for id ~p = ~p",[Id,Pid2]),
  case Pid2 of
    P when is_pid(P) -> poll(Pid2),
      receive_msg(Pid2, 0);
    _ -> lager:debug("Can't find client session, falling back to silo"),
          case ss_client_msg_silo:fetch(Id) of
            {error, not_found} -> lager:debug("Not found in silo .... :-(");
            L -> lager:debug("Found in silo ~p",[L])
          end
  end.

receive_msg(Pid, Cnt) ->
  lager:debug("Waiting for msg cnt = ~p", [Cnt]),
  receive
    Msg ->
      lager:debug("Rcvd ~p from poll(?)",[Msg]),
      [H | _] = lists:reverse(Msg),
      lager:debug("Got poll data  with len ~p", [length(Msg)]),
      case H of
        #{event_type := socket_closed} -> lager:debug("Not Polling, by, cnt =  ~p ", [Cnt + length(Msg)]);
        _ -> poll(Pid), receive_msg(Pid, Cnt + length(Msg))
      end
  end.



poll(SSClientSessionPid) ->
  Self = self(),
  PollProcessFun = fun() ->
    link(Self),
    PollFun = fun(Msg) ->
      lager:debug("Poll fun rcvd ~p",[Msg]),
      Self ! Msg,
      ok
              end,
    ss_client_session:set_poll_fun(SSClientSessionPid, PollFun)
                   end,
  Pid = spawn(PollProcessFun),
  lager:debug("Poll fn spawned with pid ~p",[Pid]).