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
          Pid = self(),
          erlang:send_after(5000,Pid,msg),
          receive

            msg ->
              error_logger:info_msg("sending response, my pid is = ~p",[Pid]),
              Ret = (catch Req:respond({200, [], "200 OK\r\n"++pid_to_list(self())})),
              error_logger:info_msg("Result from Req:respond = ~p",[Ret]);
            Other -> error_logger:info_msg("Received ~p",[Other])
          end
        end,
  Pid  = spawn(Fun),
  error_logger:info_msg("spawned delayed response with pid ~p",[Pid]).


