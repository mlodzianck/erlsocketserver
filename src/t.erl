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

t() ->
  ss_client_session_mapper:start_link(),
  mochi_server:start().


t1() ->
  spawn(fun() -> tt1() end).
tt1() ->

  error_logger:info_msg("~p ",[ss_client_session_mapper:start_link()]),
  {ok,Id} = ss_client_session:start(tcp_client,#{ipaddr => "wp.pl",port => 80 }),
  error_logger:info_msg("~p ",[Id]),
  Pid = ss_client_session_mapper:get(Id),
  ss_client_session:send_to_socket(Pid,list_to_binary("GET / HTTP/1.1\r\nHost: www.wp.pl\r\n\r\n")),
  poll(Pid),
  receive_msg(Pid,0).

receive_msg(Pid,Cnt) ->
  error_logger:info_msg("Waiting for msg cnt = ~p",[Cnt]),
  receive
    Msg -> [H|_] = lists:reverse(Msg),
      error_logger:info_msg("Got poll data  with len ~p",[length(Msg)]),
      case H of
        #{event_type := socket_closed} ->    error_logger:info_msg("Not Polling, by, cnt =  ~p ",[Cnt+length(Msg)]);
        _-> poll(Pid),receive_msg(Pid,Cnt+length(Msg))
      end
  end.



poll(SSClientSessionPid) ->
  Self = self(),
  PollProcessFun  = fun() ->
                      link(Self),
                      PollFun = fun(Msg) ->
                                  Self ! Msg,
                                  ok
                                end,
                      ss_client_session:set_poll_fun(SSClientSessionPid,PollFun)
                    end,
  spawn(PollProcessFun).