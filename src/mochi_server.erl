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
start_link() ->
  mochiweb_http:start([{name, ?MODULE}, {loop, ?LOOP},{nodelay, true} | [{port, 9900}]]).



loop(Req) ->
  runmonitor(),
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
      lager:debug("Exception ~p ~p", [Why, Err]),
      Req:respond({501, [], []})
  end.



get_from_silo(Id,Req) ->
  lager:debug("Can't find client session, falling back to silo"),
  case ss_client_msg_silo:fetch(Id) of
    {error, not_found} -> lager:debug("Not found in silo .... :-("),Req:not_found();
    L -> lager:debug("Found in silo queue with len ~p",[length(L)]),
      JSon = mochijson2:encode(encode_msg(L)),
      Req:respond({200, [{"Content-Type", "application/json"}], [JSon]})

  end.



handle_post(Req, "poll/"++Id) ->
  Pid = ss_client_session_mapper:get(Id),
  case Pid of
    {error,_}->  get_from_silo(Id,Req);
    _ ->
      poll(Pid,Req)
%%      receive
%%          Msg ->
%%            JSon = mochijson2:encode(encode_msg(Msg)),
%%            Req:respond({200, [{"Content-Type", "application/json"}], [JSon]})
%%        after 400 -> Req:respond({200, [], "200 OK\r\n"++Id++":"++pid_to_list(Pid)++" No data"})
%%        end
  end;

handle_post(Req,_) -> Req:not_found().

handle_get(Req,[]) -> Req:serve_file("index.html", "web/");

handle_get(Req,"long") ->
  receive
    after 5000 -> Req:not_found()
  end;

handle_get(Req,"create") ->
  {ok, CSPid} = ss_client_session_sup:start_ss_client_session(tcp_client, #{ipaddr => "wp.pl", port => 80}),
  Id = ss_client_session:get_id(CSPid),
  ss_client_session:send_to_socket(CSPid,list_to_binary("GET / HTTP/1.1\r\nHost: www.wp.pl\r\n\r\n")),
  Reply =  mochijson2:encode({struct, [{<<"id">>,list_to_binary(Id)}]}),
  Req:respond({200, [{"Content-Type", "application/json"}], [Reply]});

handle_get(Req,_) -> Req:not_found().

poll(SSClientSessionPid,Req) ->
  PollFun = fun(Msg) ->
              JSon = mochijson2:encode(encode_msg(Msg)),
              Req:respond({200, [{"Content-Type", "application/json"}], [JSon]}),
              ok
            end,


  ss_client_session:set_poll_fun(SSClientSessionPid,PollFun).







%%handle_get(Req) ->
%%  Fun = fun() ->
%%          Pid = self(),
%%          erlang:send_after(5000,Pid,msg),
%%          receive
%%
%%            msg ->
%%             lager:debug("sending response, my pid is = ~p",[Pid]),
%%              Ret = (catch Req:respond({200, [], "200 OK\r\n"++pid_to_list(self())})),
%%             lager:debug("Result from Req:respond = ~p",[Ret]);
%%            Other ->lager:debug("Received ~p",[Other])
%%          end
%%        end,
%%  Pid  = spawn(Fun),
%% lager:debug("spawned delayed response with pid ~p",[Pid]).









encode_msg(List) ->
  encode_msg(List,[]).
encode_msg([#{event_type := data,payload := Bin}|Rest],Acc) ->
  encode_msg(Rest,Acc++[{struct, [{"e",<<"d">>},{<<"data">>,base64:encode(Bin)}]}]);
encode_msg([#{event_type := socket_closed,total_rcvd := Cnt}|Rest],Acc) ->
  encode_msg(Rest,Acc++[{struct, [{"e",<<"e">>},{"total_rcvd",Cnt},{<<"event">>,<<"closed">>}]}]);
encode_msg([],Acc) -> Acc.




runmonitor() ->
  lager:debug("Running req monitor"),
  Self = self(),
  F = fun() -> process_flag(trap_exit,true),
              link(Self),
              receive
                Msg ->   lager:debug("req monitor rcvd msg ~p",[Msg])


              end
      end,
  spawn(F).

