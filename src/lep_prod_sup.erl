-module(lep_prod_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([
    init/1,
    producers/0
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
    ProducersConfig = application:get_env(leporidae, producers, []),
    {Producers, _} = lists:foldl(fun({amqp, PArgs}, {P, Count}) ->
        {
         [?CHILD(
            list_to_atom("producer_"++integer_to_list(Count)),
            lep_produce_sm, % lep_produce,
            worker,
            PArgs
         )|P],
         Count+1
        }
    end, {[], 1}, ProducersConfig),
    RestartStrategy = {one_for_one, 100, 60},
    {ok, {RestartStrategy, Producers}}.

-spec producers() -> proplists:proplist().
producers() ->
    [ {Id, Pid, lep_produce_sm:state(Pid)} || {Id, Pid, _, _} <- supervisor:which_children(?MODULE) ].
