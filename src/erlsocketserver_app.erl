-module(erlsocketserver_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).


start(_StartType, _StartArgs) ->
    lager:start(),
    lager:set_loglevel(lager_console_backend, debug),
    erlsocketserver_sup:start_link().

stop(_State) ->
    ok.