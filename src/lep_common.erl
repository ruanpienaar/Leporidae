-module(lep_common).

-include_lib("../amqp_client/include/amqp_client.hrl").
-include("leporidae.hrl").

-export([
    establish_connection_channel/1,
    establish_channel/1,
    bind_queue_exchange/2,
    do_publish/4,
    do_consume/3,
    do_get/2,
    do_acknowledge/2,
    do_no_acknowledge/2,
    do_subscribe/3,
    log/1,
    log/2
]).

-spec establish_connection_channel(proplists:proplist())
        -> {ok, pid(), pid()} |
           {error, {conn_error, term()}} |
           {error, {chan_error, term(), pid()}}.

establish_connection_channel(AMQPArgs) ->
    {connection, ConnOpts} = proplists:lookup(connection, AMQPArgs),
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
            log(" === ~p CONNECTED === ~n", [self()]),
            establish_channel(Conn)
    end.

establish_channel(Conn) ->
    case amqp_connection:open_channel(Conn) of
        {ok, Chan} ->
            log(" === ~p CHANNEL === ~n", [self()]),
            {ok, Conn, Chan};
        {error, ChanError} ->
            {error, {chan_error, ChanError, Conn}};
        closing ->
            {error, {chan_error, closing, Conn}}
    end.

bind_queue_exchange(Chan, AMQPArgs) ->
    EX =
    case proplists:lookup(exchange, AMQPArgs) of
        none ->
            % I think rabbitmq
            ?DEFAULT_EXCHANGE; % Default Exchange for all queues
        {exchange, ExchangeOpts} ->
            % Mandatory for non "" Exchange. Bind the queue to the exchange.
            {exchange, Exchange} = proplists:lookup(exchange, ExchangeOpts),
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
            log(" === ~p DECLARE EXCHANGE === ~n~p~n", [self(), DE]),
            #'exchange.declare_ok'{} = amqp_channel:call(Chan, DE),
            Exchange
    end,
    {queue, QueueOpts} = proplists:lookup(queue, AMQPArgs),
    {queue, Queue} = proplists:lookup(queue, QueueOpts),
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
    log(" === ~p DECLARE QUEUE === ~n~p~n", [self(), DQ]),
    #'queue.declare_ok'{} = amqp_channel:call(Chan, DQ),
    case EX of
        ?DEFAULT_EXCHANGE ->
            ok;
        _ ->
            RoutingKey = proplists:get_value(routing_key, AMQPArgs),
            QB = #'queue.bind'{
                queue = Queue,
                exchange = EX,
                routing_key = RoutingKey
            },
            #'queue.bind_ok'{} = amqp_channel:call(Chan, QB)
    end,
    {ok, Queue, EX}.

do_publish(Chan, Publish, Basic, Payload) when is_pid(Chan) andalso
                                               is_list(Publish) andalso
                                               is_list(Basic) andalso
                                               is_binary(Payload) ->
    % Routing Key = Queue name, when bound to default queue.
    % Routing Key needs distinct value when queue bound to exchange.
    % Routing Key should be filled in the Publish proplist.
    BasicPublish = #'basic.publish'{
        ticket = proplists:get_value(ticket, Publish, 0),
        exchange = proplists:get_value(exchange, Publish, ?DEFAULT_EXCHANGE),
        routing_key = proplists:get_value(routing_key, Publish),
        mandatory = proplists:get_value(mandatory, Publish, false),
        immediate = proplists:get_value(immediate, Publish, false)
    },
    P_basic = #'P_basic'{
        content_type =
            proplists:get_value(content_type, Basic, <<"text/plain">>),
        content_encoding =
            proplists:get_value(content_encoding, Basic),
        headers =
            proplists:get_value(headers, Basic),
        delivery_mode =
            proplists:get_value(delivery_mode, Basic, 1), % non­persistent (1) or persistent (2)
        priority =
            proplists:get_value(priority, Basic),
        correlation_id =
            proplists:get_value(correlation_id, Basic),
        reply_to =
            proplists:get_value(reply_to, Basic),
        expiration =
            proplists:get_value(expiration, Basic),
        message_id =
            proplists:get_value(message_id, Basic),
        timestamp =
            proplists:get_value(timestamp, Basic),
        type =
            proplists:get_value(type, Basic),
        user_id =
            proplists:get_value(user_id, Basic),
        app_id =
            proplists:get_value(app_id, Basic),
        cluster_id =
            proplists:get_value(cluster_id, Basic)
    },
    AMQPMsg = #amqp_msg{
        props = P_basic,
        payload = Payload
    },
    try
        %% TODO: maybe not try_catch, and let the gen_statem, crash/go-into-another state ?
        %log(" === ~p PUBLISH === ~n~p~n~p~n", [self(), BasicPublish, AMQPMsg]),
        ok = amqp_channel:call(Chan, BasicPublish, AMQPMsg)
    catch
        C:E ->
            log("Failed publishing message:~p ~p ~p\n",[C, E, erlang:get_stacktrace()]),
            %% TODO: maybe check the status of those pids:
            {error, {C,E,erlang:get_stacktrace()}}
    end.

do_consume(Chan, ConsumerTag, Consume) ->
    BasicConsume = #'basic.consume'{
        consumer_tag = ConsumerTag,
        queue = proplists:get_value(queue, Consume),
        no_ack = proplists:get_value(no_ack, Consume, false),
        exclusive = proplists:get_value(exclusive, Consume, false),
        nowait = proplists:get_value(nowait, Consume, false),
        arguments = proplists:get_value(arguments, Consume, [])
    },
    log(" === ~p CONSUME === ~n~p~n", [self(), BasicConsume]),
    amqp_channel:call(Chan, BasicConsume).

do_get(Chan, Get) ->
    BasicGet = #'basic.get'{
        queue = proplists:get_value(queue, Get),
        no_ack = true
    },
    {GetOk, AmqpMsg} = amqp_channel:call(Chan, BasicGet),
    log(" === ~p GET === ~n~p~n~p~n", [self(), GetOk, AmqpMsg]),
    case AmqpMsg of
        <<>> ->
            <<>>;
        #amqp_msg{
            props = #'P_basic'{
                content_type = _ContentType,
                content_encoding = _ContentEncoding,
                headers = _Headers,
                delivery_mode = _DeliveryMode,
                priority = _Priority,
                correlation_id = _CorrelationId,
                reply_to = _ReplyTo,
                expiration = _Expiration,
                message_id = _MessageId,
                timestamp = _Timestamp,
                type = _Type,
                user_id = _UserId,
                app_id = _AppId,
                cluster_id = _ClusterId
            },
            payload = Payload
        } = AmqpMsg ->
            Payload
    end.

do_acknowledge(Chan, Ack) ->
    BasicAck = #'basic.ack'{
        delivery_tag = proplists:get_value(delivery_tag, Ack),
        multiple = proplists:get_value(multiple, Ack, false)
    },
    %log(" === ~p ACK === ~n~p~n", [self(), BasicAck]),
    amqp_channel:call(Chan, BasicAck).

do_no_acknowledge(Chan, NAck) ->
    BasicNAck = #'basic.nack'{
        delivery_tag = proplists:get_value(delivery_tag, NAck),
        multiple = proplists:get_value(multiple, NAck, false),
        requeue = proplists:get_value(requeue, NAck, true)
    },
    log(" === ~p NACK === ~n~p~n", [self(), BasicNAck]),
    amqp_channel:call(Chan, BasicNAck).

do_subscribe(Chan, Queue, SubscriberPid) ->
    BasicConsume = #'basic.consume'{
        queue = Queue
    },
    log(" === ~p SUBSCRIBE === ~n~p~n", [self(), BasicConsume]),
    #'basic.consume_ok'{} = amqp_channel:subscribe(Chan, BasicConsume, SubscriberPid).

log(X) ->
    log(X, []).

log(X, Y) ->
    io:format(X, Y).