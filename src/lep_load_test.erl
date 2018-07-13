-module(lep_load_test).

-export([
    run/0,
    pp/0,
    stop/0
]).

run() ->
    run(1000).

run(TimeToLoadTest) ->
    spawn_link(fun() -> run_proc(TimeToLoadTest) end).

run_proc(TimeToLoadTest) ->
    case application:start(ponos) of
        ok ->
            ok;
        {error,{already_started,ponos}} ->
            ok
    end,

    % Publish
    ok = lists:foreach(fun(_) ->
        % Create child
        {ok, _Child} = lep_prod_sup:add_child([
            {connection, [
                {type, network},
                {username, <<"root">>},
                {passwd, <<"root">>},
                {vhost, <<"/">>},
                {host, "localhost"},
                {port, 5672}
            ]},
            {queue, [
                {queue, <<"queue1">>},
                {durable, true}
            ]}
        ])

        % check that children seem ok
        % keep_checking_for(connected_and_chan,

        % Start load generator
        % [ok] = add_load_test_generator(Name, Pid)
    end, lists:seq(1, 1)),

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
    % [ok] = ponos:init_load_generators(PublishName1),
    % [ok] = ponos:init_load_generators(PublishName2),
    % [ok] = ponos:init_load_generators(PublishName3),
    %[ok] = ponos:init_load_generators(ConsName),

    receive
        _ ->
            ok
    after
        TimeToLoadTest ->
            ok
    end.

add_load_test_generator(Name, Pid) ->
    Spec = ponos_load_specs:make_constant(5000.0),
    Task =
        fun() ->
            Data = term_to_binary({erlang:system_time(), erlang:time_offset()}),
            lep_produce_sm:publish(Pid, Data)
        end,
    LoadGenOpts = [{name, Name},
                   {load_spec, Spec},
                   {task, Task}],
    [ok] = ponos:add_load_generators(LoadGenOpts).

pp() ->
    ptop:pp().

stop() ->
    [ok] = ponos:remove_load_generators(rabbit_publish_load_test),
    %[ok] = ponos:remove_load_generators(rabbit_consume_load_test).
    ok.