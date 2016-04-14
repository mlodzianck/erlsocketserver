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
  mochi_server:start().



t1() ->

  error_logger:info_msg("~p ",[ss_client_session_mapper:start_link()]),
  {ok,Id} = ss_client_session:start(tcp_client,#{ipaddr => "wp.pl",port => 80 }),
  error_logger:info_msg("~p ",[Id]),
  Pid = ss_client_session_mapper:get(Id),
  ss_client_session:send_to_socket(Pid,list_to_binary("GET / HTTP/1.1\r\nHost: www.wp.pl\r\n\r\n")),
  DoPoll = fun(F) ->
    error_logger:info_msg("Polling..."),
    PollFun = fun(Data) ->
                [H|_] = lists:reverse(Data),
                error_logger:info_msg("Got poll data len is ~p",[length(Data)]),
                case H of
                  {event,#{event_type := socket_closed}} ->    error_logger:info_msg("Not Polling, bye");
                  _-> F(F)
                end
              end,

              ss_client_session:poll(Pid,PollFun)
           end,




  DoPoll(DoPoll).