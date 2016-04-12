%%%-------------------------------------------------------------------
%%% @author maciejtokarski
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 15. mar 2016 18:07
%%%-------------------------------------------------------------------
-module(mochi_server).
-author("maciejtokarski").
-define(LOOP, {?MODULE, loop}).
%% API
-compile(export_all).
start() ->
  mochiweb_http:start([{name, ?MODULE}, {loop, ?LOOP},{nodelay, true} | [{port, 9900}]]).



loop(Req) ->
    "/" ++ Path = Req:get(path),
  try
    case Req:get(method) of
      'GET' ->
        handle_get(Req);
      'POST' ->
        case Path of
          _ ->
            Req:not_found()
        end;
      _ ->
        Req:respond({501, [], []})
    end
  catch
    Why:Err -> error_logger:info_msg("Exception ~p ~p", [Why, Err])
  end.


handle_get(Req) ->
  Fun = fun() ->
          receive
            _-> Req:respond({200, [], "200 OK\r\n"++pid_to_list(self())})
          end
        end,
  Pid  = spawn(Fun),
  erlang:send_after(5000,Pid,msg).

