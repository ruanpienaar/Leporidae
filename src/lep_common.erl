-module(lep_common).

-include_lib("../amqp_client/include/amqp_client.hrl").

-export([
    establish_connection_channel/1,
    establish_channel/1,
    do_producer_rest_init/3
]).

-spec establish_connection_channel(proplists:proplist()) 
        -> {ok, pid(), pid()} |
           {error, {conn_error, term()}} |
           {error, {chan_error, term(), pid()}}.

establish_connection_channel(AMQPArgs) ->
    {connection, ConnOpts} = proplists:lookup(connection,AMQPArgs),
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
    case amqp_connection:start(ConnParams) of
        {error, ConnError} ->
            {error, {conn_error, ConnError}};
        {ok, Conn} ->
            establish_channel(Conn)
    end.

establish_channel(Conn) ->
    case amqp_connection:open_channel(Conn) of
        {ok, Chan} ->
            {ok, Conn, Chan};
        {error, ChanError} ->
            {error, {chan_error, ChanError, Conn}}
    end.

do_producer_rest_init(Conn, Chan, AMQPArgs) ->
    {queue, QueueOpts} = proplists:lookup(queue, AMQPArgs),
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
    {exchange, ExchangeOpts} = proplists:lookup(exchange, AMQPArgs),
    Exchange = proplists:get_value(exchange, ExchangeOpts, ""),
    DE = #'exchange.declare'{
        ticket = proplists:get_value(ticket, ExchangeOpts, 0),
        exchange = Exchange,
        type = proplists:get_value(type, ExchangeOpts, <<"direct">>),
        passive = proplists:get_value(passive, ExchangeOpts, false),
        durable = proplists:get_value(durable, ExchangeOpts, false),
        auto_delete = proplists:get_value(auto_delete, ExchangeOpts, false),
        internal = proplists:get_value(internal, ExchangeOpts, false),
        nowait = proplists:get_value(nowait, ExchangeOpts, false),
        arguments = proplists:get_value(arguments, ExchangeOpts, [])
    },
    #'exchange.declare_ok'{} = amqp_channel:call(Chan, DE),
    case Exchange of
        "" ->
            ok;
        _ -> % Mandatory for non "" Exchange
            RoutingKey =
                proplists:get_value(routing_key, AMQPArgs),
            QB = #'queue.bind'{
                queue = Queue,
                exchange = Exchange,
                routing_key = RoutingKey
            },
            #'queue.bind_ok'{} = amqp_channel:call(Chan, QB)
    end,
    true = lep_load_spread:add_producer_pid(self()),
    % {ok, #?STATE{
    %     amqp_args = AMQPArgs,
    %     queue = Queue,
    %     amqp_connection = Conn,
    %     amqp_channel = Chan
    % }}.
    {ok, Queue, Exchange}.
