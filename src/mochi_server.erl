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
        handle_get(Req,Path);
      'POST' ->
          handle_post(Req,Path);
      _ ->
        Req:respond({501, [], []})
    end
  catch
    Why:Err ->
      erlang:display(erlang:get_stacktrace()),
      error_logger:info_msg("Exception ~p ~p", [Why, Err])
  end.


handle_post(Req, "poll/"++Id) ->
  Pid = ss_client_session_mapper:get(Id),
  case Pid of
    {error,_}->  Req:not_found();
    _ ->
      ss_client_session:set_poll_pid(Pid),

      receive
          Msg ->
            JSon = mochijson2:encode(encode_msg(Msg)),
            Req:respond({200, [{"Content-Type", "application/json"}], [JSon]})
        after 400 -> Req:respond({200, [], "200 OK\r\n"++Id++":"++pid_to_list(Pid)++" No data"})
        end
  end;

handle_post(Req,_) -> Req:not_found().


handle_get(Req,"create") ->
  {ok,Id} = ss_client_session:start(tcp_client,#{ipaddr => "wp.pl",port => 80 }),
  Pid = ss_client_session_mapper:get(Id),
  ss_client_session:send_to_socket(Pid,list_to_binary("GET / HTTP/1.1\r\nHost: www.wp.pl\r\n\r\n")),
  Reply =  mochijson2:encode({struct, [{<<"id">>,list_to_binary(Id)}]}),
  Req:respond({200, [{"Content-Type", "application/json"}], [Reply]});

handle_get(Req,_) -> Req:not_found().



%%handle_get(Req) ->
%%  Fun = fun() ->
%%          Pid = self(),
%%          erlang:send_after(5000,Pid,msg),
%%          receive
%%
%%            msg ->
%%              error_logger:info_msg("sending response, my pid is = ~p",[Pid]),
%%              Ret = (catch Req:respond({200, [], "200 OK\r\n"++pid_to_list(self())})),
%%              error_logger:info_msg("Result from Req:respond = ~p",[Ret]);
%%            Other -> error_logger:info_msg("Received ~p",[Other])
%%          end
%%        end,
%%  Pid  = spawn(Fun),
%%  error_logger:info_msg("spawned delayed response with pid ~p",[Pid]).









encode_msg(List) ->
  encode_msg(List,[]).
encode_msg([#{event_type := data,payload := Bin}|Rest],Acc) ->
  encode_msg(Rest,Acc++[{struct, [{"e",<<"d">>},{<<"data">>,base64:encode(Bin)}]}]);
encode_msg([#{event_type := socket_closed}|Rest],Acc) ->
  encode_msg(Rest,Acc++[{struct, [{"e",<<"e">>},{<<"event">>,<<"closed">>}]}]);
encode_msg([],Acc) -> Acc.


