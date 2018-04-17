-module(lep_example_consumer_worker).
-include_lib("amqp_client/include/amqp_client.hrl").
-export([consume/1]).

consume(AMQPMsg = #amqp_msg{
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
            payload = _Payload
        }) ->
    io:format("~p -> consume -> ~p~n", [?MODULE, AMQPMsg]).