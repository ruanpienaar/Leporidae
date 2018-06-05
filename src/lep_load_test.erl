-module(lep_load_test).

-export([
    run/0,
    pp/0,
    stop/0
]).

run() ->
    spawn_link(fun() -> run_proc() end).

run_proc() ->
    case application:start(ponos) of
        ok ->
            ok;
        {error,{already_started,ponos}} ->
            ok
    end,

    % Publish
    [Pub1, Pub2, Pub3 | _] = lep_prod_sup:producers(),

    PubPid1 = element(2, Pub1),
    PublishName1 = rabbit_publish_load_test1,
    PublishLoadSpec1 = ponos_load_specs:make_constant(5000.0),
    PublishTask1 =
        fun() ->
            Data = term_to_binary({erlang:system_time(), erlang:time_offset()}),
            lep_produce_sm:publish(PubPid1, Data)
        end,
    PublishLoadGen1 = [{name, PublishName1},
                      {load_spec, PublishLoadSpec1},
                      {task, PublishTask1}],
    [ok] = ponos:add_load_generators(PublishLoadGen1),

    PubPid2 = element(2, Pub2),
    PublishName2 = rabbit_publish_load_test2,
    PublishLoadSpec2 = ponos_load_specs:make_constant(5000.0),
    PublishTask2 =
        fun() ->
            Data = term_to_binary({erlang:system_time(), erlang:time_offset()}),
            lep_produce_sm:publish(PubPid2, Data)
        end,
    PublishLoadGen2 = [{name, PublishName2},
                      {load_spec, PublishLoadSpec2},
                      {task, PublishTask2}],
    [ok] = ponos:add_load_generators(PublishLoadGen2),

    PubPid3 = element(2, Pub3),
    PublishName3 = rabbit_publish_load_test3,
    PublishLoadSpec3 = ponos_load_specs:make_constant(5000.0),
    PublishTask3 =
        fun() ->
            Data = term_to_binary({erlang:system_time(), erlang:time_offset()}),
            lep_produce_sm:publish(PubPid3, Data)
        end,
    PublishLoadGen3 = [{name, PublishName3},
                      {load_spec, PublishLoadSpec3},
                      {task, PublishTask3}],
    [ok] = ponos:add_load_generators(PublishLoadGen3),

    % TODO: manual Consume
    % ConsName = rabbit_consume_load_test,
    % ConsLoadSpec = ponos_load_specs:make_constant(100.0),
    % ConsTask =
    %     fun() ->
    %         {ok, mike}
    %     end,
    % ConsLoadGen = [{name, ConsName},
    %                {load_spec, ConsLoadSpec},
    %                {task, ConsTask}],
    % [ok] = ponos:add_load_generators(ConsLoadGen),

    % Init the load testers...
    [ok] = ponos:init_load_generators(PublishName1),
    [ok] = ponos:init_load_generators(PublishName2),
    [ok] = ponos:init_load_generators(PublishName3),
    %[ok] = ponos:init_load_generators(ConsName),

    receive
        _ ->
            ok
    end.

pp() ->
    ptop:pp().

stop() ->
    [ok] = ponos:remove_load_generators(rabbit_publish_load_test),
    %[ok] = ponos:remove_load_generators(rabbit_consume_load_test).
    ok.