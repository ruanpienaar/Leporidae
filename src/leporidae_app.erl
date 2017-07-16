-module(leporidae_app).

-behaviour(application).

%% Application callbacks
-export([start/0, start/2,
         stop/1
]).

-include("leporidae.hrl").

%% ===================================================================
%% Application callbacks
%% ===================================================================

start() ->
    application:ensure_all_started(leporidae).

start(_StartType, _StartArgs) ->
    leporidae_sup:start_link().

stop(_State) ->
    ok.
