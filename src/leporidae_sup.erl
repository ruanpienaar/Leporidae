-module(leporidae_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(Mod), {Mod, {Mod, start_link, []}, permanent, 5000, supervisor, [Mod]}).
-define(CHILD(Mod, Type), {Mod, {Mod, start_link, []}, permanent, 5000, Type, [Mod]}).

-include("leporidae.hrl").

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok, {{one_for_one, 5, 10},[
        ?CHILD(lep_load_spread, worker),
        ?CHILD(lep_cons_sup),
        ?CHILD(lep_prod_sup)
    ]}}.
    