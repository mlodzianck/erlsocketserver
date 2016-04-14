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

  error_logger:info_msg("~p ",[ss_client_session_mapper:start_link()]),
  {ok,Id} = ss_client_session:start(tcp_client,#{ipaddr => "wp.pl",port => 80 }),
  error_logger:info_msg("~p ",[Id]),
  Pid = ss_client_session_mapper:get(Id),
  ss_client_session:send_to_socket(Pid,list_to_binary("GET / HTTP/1.1\r\nHost: www.wp.pl\r\n\r\n")),
  PollFun = fun(Next,Counter) ->
                Self  = self(),
                error_logger:info_msg(" Polling...., counter = ~p, slef =~p",[Counter,Self]),

                ss_client_session:set_poll_pid(Pid),
                receive
                  Msg -> error_logger:info_msg("Poll pid received message with len ~p",[length(Msg)]),
                          [H|_] = lists:reverse(Msg),
                          case H of
                            #{event_type := socket_closed} ->    error_logger:info_msg("Not Polling, bye, counter = ~p",[Counter+length(Msg)]);
                            _-> spawn(fun() ->Next(Next,Counter+length(Msg)) end)
                          end

                end
             end,

%%  receive
%%    _ -> ok
%%    after 400 -> spawn(fun() -> PollFun(PollFun,0) end)
%%  end.


receive
  _-> noop
  after 400 -> Rep = ss_client_session:close_socket(Pid),
                error_logger:info_msg("Closed socket, reply len  = ~p",[length(Rep)])

end.