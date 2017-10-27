-module(lep_produce).

-export([
    start/1,
    start_link/1,
    produce/1
]).

-behaviour(gen_server).
-include_lib("../amqp_client/include/amqp_client.hrl").

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(STATE, lep_produce_state).
-record(?STATE, {
    connected = false,
    queue,
    amqp_connection_opts,
    amqp_connection,
    amqp_channel
}).

start(AMQPArgs) ->
    gen_server:start(?MODULE, {AMQPArgs}, []).

start_link(AMQPArgs) ->
    gen_server:start_link(?MODULE, {AMQPArgs}, []).

produce(Data) when is_binary(Data) ->
    case lep_load_spread:next_producer_pid() of
        Pid when is_pid(Pid) ->
            gen_server:call(Pid, {produce, Data});
        false ->
            {error, no_producers}
    end.

init({AMQPArgs}) ->
    {connection,ConnOpts} = proplists:lookup(connection,AMQPArgs),
    ConnParams =
        case proplists:lookup(type, ConnOpts) of
            {type,network} ->
                {username,U}  = proplists:lookup(username, ConnOpts),
                {passwd,Pw} = proplists:lookup(passwd, ConnOpts),
                {host,H}  = proplists:lookup(host, ConnOpts),
                {port,Po} = proplists:lookup(port, ConnOpts),
                #amqp_params_network{username=U, password=Pw, host=H, port=Po};
            {type,direct} ->
                {username,U}  = proplists:lookup(username, ConnOpts),
                {passwd,Pw} = proplists:lookup(passwd, ConnOpts),
                {node,Node} = proplists:lookup(node, ConnOpts),
                #amqp_params_direct{username=U, password=Pw, node=Node}
        end,
    {ok, Conn} = amqp_connection:start(ConnParams),
    erlang:monitor(process, Conn),
    {ok, Chan} = amqp_connection:open_channel(Conn),
    erlang:monitor(process, Chan),
    {connection,ConnOpts} = proplists:lookup(connection,AMQPArgs),
    {exchange, ExchangeOpts} = proplists:lookup(exchange, AMQPArgs),
    DE = #'exchange.declare'{
        ticket = proplists:get_value(ticket, ExchangeOpts, 0),
        exchange = proplists:get_value(exchange, ExchangeOpts, ""),
        type = proplists:get_value(type, ExchangeOpts, <<"direct">>),
        passive = proplists:get_value(passive, ExchangeOpts, false),
        durable = proplists:get_value(durable, ExchangeOpts, false),
        auto_delete = proplists:get_value(auto_delete, ExchangeOpts, false),
        internal = proplists:get_value(internal, ExchangeOpts, false),
        nowait = proplists:get_value(nowait, ExchangeOpts, false),
        arguments = proplists:get_value(arguments, ExchangeOpts, [])
    },
    #'exchange.declare_ok'{} = amqp_channel:call(Chan, DE),
    {queue,QueueOpts} = proplists:lookup(queue,AMQPArgs),
    Queue = proplists:get_value(queue, QueueOpts, <<"queue">>),
    DQ =
        #'queue.declare'{
            ticket = proplists:get_value(ticket, QueueOpts, 0),
            queue = Queue,
            passive = proplists:get_value(passive, QueueOpts, false),
            durable = proplists:get_value(durable, QueueOpts, true),
            exclusive = proplists:get_value(exclusive, QueueOpts, false),
            auto_delete = proplists:get_value(auto_delete, QueueOpts, false),
            nowait = proplists:get_value(nowait, QueueOpts, false),
            arguments = proplists:get_value(arguments, QueueOpts, [])
        },
    #'queue.declare_ok'{} = amqp_channel:call(Chan, DQ),
    true = lep_load_spread:add_producer_pid(self()),
    {ok, #?STATE{
        connected = true,
        queue = Queue,
        amqp_connection_opts = ConnOpts,
        amqp_connection = Conn,
        amqp_channel = Chan
    }}.

handle_call({produce, Data}, _From, #?STATE{ queue = Queue, amqp_channel = Chan } = State) ->
    case produce(Chan, Queue, Data) of
        ok ->
            {reply, ok, State};
        {error, ErrorState} ->
            {stop, normal,State}
    end;
handle_call(Request, _From, State) ->
    io:format("unknown_call ~p~n", [Request]),
    print_state(State),
    {reply, {error, unknown_call}, State}.

handle_cast(Msg, State) ->
    io:format("unknown_cast ~p~n", [Msg]),
    print_state(State),
    {noreply, State}.

handle_info(Info, State) ->
    print_state(State),
    io:format("~p handle_info ~p", [?MODULE, Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    true = lep_load_spread:del_producer_pid(self()),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

produce(Chan, Queue, Data) ->
    P = #'P_basic'{ content_type = <<"text/plain">> },
    Pub = #'basic.publish'{
        % exchange = Exchange,
        routing_key = Queue
    },
    AMQPMsg = #amqp_msg{props = P,
                        payload = Data},
    try
        % io:format("produce ~p #amqp_msg{props = ~p,payload = ~p}~n",
        %     [?MODULE, P, Data]
        % ),
        ok = amqp_channel:call(Chan, Pub, AMQPMsg)
    catch
        C:E ->
            io:format("Failed publishing message:~p ~p ~p\n",[C, E, erlang:get_stacktrace()]),
            %% TODO: maybe check the status of those pids:
            {error, {C,E,erlang:get_stacktrace()}}
    end.

print_state(State) ->
    [?STATE | FieldValues] = tuple_to_list(State),
    io:format(
        "State:~p~n",
        [lists:zip(record_info(fields, ?STATE), FieldValues)]
    ).