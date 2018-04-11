-module(lep_cons_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([
    init/1,
    consumers/0
]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Mod, Type), {I, {Mod, start_link, []}, permanent, 100, Type, [Mod]}).
-define(CHILD(I, Mod, Type, Args), {I, {Mod, start_link, [Args]}, permanent, 100, Type, [Mod]}).

-include("leporidae.hrl").

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, {}).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init({}) ->
    ConsumersConfig = application:get_env(leporidae, consumers, []),
    {Consumers, _} = lists:foldl(fun({amqp, CArgs}, {C, Count}) ->
        {
         [?CHILD(
            list_to_atom("consumer_"++integer_to_list(Count)),
            lep_consume,
            worker,
            CArgs
         )|C],
         Count+1
        }
    end, {[], 1}, ConsumersConfig),
    RestartStrategy = {one_for_one, 100, 60},
    {ok, {RestartStrategy, Consumers}}.

-spec consumers() -> proplists:proplist().
consumers() ->
    [ {Id, Pid} || {Id, Pid, _, _} <- supervisor:which_children(?MODULE) ].
