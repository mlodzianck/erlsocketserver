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
  error_logger:info_msg("~p ",[ss_client_session:start(tcp_client,#{ipaddr => "wp.pl",port => 81 })]).