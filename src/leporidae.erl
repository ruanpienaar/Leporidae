-module(leporidae).

%% Escript 
-export([
    main/1
]).

main(["-c"|Rest]) ->
    timer:sleep(500),
    start_lep(consume, Rest);
main(["-p", Payload | Rest]) ->
    start_lep({publish, list_to_binary(Payload)}, Rest);
main(_) ->
    help().

help() ->
    io:format("./~p -c Msg / -p Msg~n", [?MODULE]),
    io:format(" -c ( Consume ) OR -p ( publish ) -t TIMEOUT (ms)~n"),
    io:format(
        "procucer and consumer connectivity details read from sys.config~n"),
    erlang:halt(0).

start_lep(Type, RestArgs) ->
    Timeout = get_timeout(RestArgs),
    % {ok,_} = net_kernel:start([somename, longnames]),
    % dbg:tracer(),
    % dbg:p(all, call),
    % dbg:tpl(leporidae_app, cx),
    % dbg:tpl(leporidae_sup, cx),
    % dbg:tpl(lep_cons_sup, cx),
    % dbg:tpl(lep_prod_sup, cx),
    % dbg:tpl(lep_consumer, cx),
    % dbg:tpl(lep_producer, cx),
    true = code:add_patha("amqp_client/ebin"),
    true = code:add_patha("amqp_client/deps/rabbit_common/ebin"),
    true = code:add_patha("amqp_client/deps/ranch/ebin"),
    true = code:add_patha("amqp_client/deps/ranch_proxy_protocol/ebin"),
    true = code:add_patha("amqp_client/deps/jsx/ebin"),
    true = code:add_patha("amqp_client/deps/goldrush/ebin"),
    true = code:add_patha("amqp_client/deps/lager/ebin"),
    true = code:add_patha("amqp_client/deps/recon/ebin"),
    ok = application:load(leporidae),
    {ok, [ConfigTerms]} = file:consult("sys.config"),
    {leporidae,LeporidaeConfig} = lists:keyfind(leporidae, 1, ConfigTerms),
    case Type of
        consume ->
            print("Setting consumers ....~n", []),
            {consumers, Consumers} =
                lists:keyfind(consumers, 1, LeporidaeConfig),
            ok = application:set_env(leporidae, consumers, Consumers),
            ok = application:set_env(leporidae, producers, []);
        {publish, Payload} ->
            true = register(producer,
                spawn(fun() -> payload_sender_loop(Payload) end)
            ),
            print("Setting producers ....~n", []),
            {producers, Producers} =
                lists:keyfind(producers, 1, LeporidaeConfig),
            ok = application:set_env(leporidae, consumers, []),
            ok = application:set_env(leporidae, producers, Producers)
    end,
    {ok, _} = application:ensure_all_started(leporidae),
    print("Sleeping for ~p~n", [Timeout]),
    case whereis(producer) of
        undefined ->
            ok;
        _ ->
            {ok, _} = timer:send_interval(50, producer, produce)
    end,
    timer:sleep(Timeout),
    print("halting", []),
    erlang:halt(0).

print(Fmt, Args) ->
    io:format(Fmt, Args),
    % To allow printing to the shell.
    timer:sleep(50).

get_timeout([]) ->
    infinity;
get_timeout(["-t", Timeout | _Rest]) ->
    list_to_integer(Timeout);
get_timeout([_Rest]) ->
    infinity.

payload_sender_loop(Payload) ->
    receive
        produce ->
            ok = lep_produce:publish(Payload),
            payload_sender_loop(Payload)
    end.