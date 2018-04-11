-module(lep_produce).

% -export([
%     start/1,
%     start_link/1,
%     publish/2
% ]).

% -behaviour(gen_server).
% -include_lib("../amqp_client/include/amqp_client.hrl").

% -export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

% -define(STATE, lep_produce_state).
% -record(?STATE, {
%     amqp_args,
%     queue,
%     amqp_connection,
%     amqp_channel,
%     last_error
% }).

% % @doc
% % init:
% %   declare AMQP queue if not exists
% %   declare AMQP exchange if not exists
% %   IF AMPQ exchange != ""
% %     bind to AMQP queue
% %
% % publish:
% %   amqp_call (Publish AMQP)
% % @end

% start(AMQPArgs) ->
%     gen_server:start(?MODULE, {AMQPArgs}, []).

% start_link(AMQPArgs) ->
%     gen_server:start_link(?MODULE, {AMQPArgs}, []).

% publish(Pid, Payload) when is_binary(Payload) ->
%     gen_server:call(Pid, {publish, Payload}).

% init({AMQPArgs}) ->
%     case do_estb_conn(AMQPArgs) of
%         {ok, Conn, Chan} ->
%             do_rest_init(Conn, Chan, AMQPArgs);
%         {error, Reason} ->
%             self() ! reconnect,
%             {ok, #?STATE{
%                 amqp_args = AMQPArgs,
%                 last_error = Reason
%             }}
%     end.

% do_rest_init(Conn, Chan, AMQPArgs) ->
%     {queue, QueueOpts} = proplists:lookup(queue, AMQPArgs),
%     Queue = proplists:get_value(queue, QueueOpts, <<"queue">>),
%     DQ =
%         #'queue.declare'{
%             ticket = proplists:get_value(ticket, QueueOpts, 0),
%             queue = Queue,
%             passive = proplists:get_value(passive, QueueOpts, false),
%             durable = proplists:get_value(durable, QueueOpts, true),
%             exclusive = proplists:get_value(exclusive, QueueOpts, false),
%             auto_delete = proplists:get_value(auto_delete, QueueOpts, false),
%             nowait = proplists:get_value(nowait, QueueOpts, false),
%             arguments = proplists:get_value(arguments, QueueOpts, [])
%         },
%     #'queue.declare_ok'{} = amqp_channel:call(Chan, DQ),
%     {exchange, ExchangeOpts} = proplists:lookup(exchange, AMQPArgs),
%     Exchange = proplists:get_value(exchange, ExchangeOpts, ""),
%     DE = #'exchange.declare'{
%         ticket = proplists:get_value(ticket, ExchangeOpts, 0),
%         exchange = Exchange,
%         type = proplists:get_value(type, ExchangeOpts, <<"direct">>),
%         passive = proplists:get_value(passive, ExchangeOpts, false),
%         durable = proplists:get_value(durable, ExchangeOpts, false),
%         auto_delete = proplists:get_value(auto_delete, ExchangeOpts, false),
%         internal = proplists:get_value(internal, ExchangeOpts, false),
%         nowait = proplists:get_value(nowait, ExchangeOpts, false),
%         arguments = proplists:get_value(arguments, ExchangeOpts, [])
%     },
%     #'exchange.declare_ok'{} = amqp_channel:call(Chan, DE),
%     case Exchange of
%         "" ->
%             ok;
%         _ -> % Mandatory for non "" Exchange
%             RoutingKey =
%                 proplists:get_value(routing_key, AMQPArgs),
%             QB = #'queue.bind'{
%                 queue = Queue,
%                 exchange = Exchange,
%                 routing_key = RoutingKey
%             },
%             #'queue.bind_ok'{} = amqp_channel:call(Chan, QB)
%     end,
%     true = lep_load_spread:add_producer_pid(self()),
%     {ok, #?STATE{
%         amqp_args = AMQPArgs,
%         queue = Queue,
%         amqp_connection = Conn,
%         amqp_channel = Chan
%     }}.

% handle_call({publish, Payload}, _From, #?STATE{
%         amqp_args = AMQPArgs,
%         amqp_channel = Chan } = State) ->
%     % case do_publish(Chan, Queue, Data) of
%     RoutingKey =
%         proplists:get_value(routing_key, AMQPArgs),
%     case do_publish(Chan, [{routing_key, RoutingKey}], [], Payload) of
%         ok ->
%             {reply, ok, State};
%         {error, ErrorState} ->
%             {stop, normal, ErrorState}
%     end;
% handle_call(Request, _From, State) ->
%     io:format("unknown_call ~p~n", [Request]),
%     print_state(State),
%     {reply, {error, unknown_call}, State}.

% handle_cast(Msg, State) ->
%     io:format("unknown_cast ~p~n", [Msg]),
%     print_state(State),
%     {noreply, State}.

% handle_info(reconnect, #?STATE{amqp_connection = undefined, 
%                                amqp_channel = undefined,
%                                last_error = LE} = State) ->
%     io:format("Trying to reconnect last_error : ~p~n", [LE]),
%     NewState = do_re_estb_conn(AMQPArgs, State),
%     {noreply, NewState};
% handle_info(reconnect, #?STATE{amqp_connection = Conn, 
%                                amqp_channel = Chan} = State) ->
%     io:format("Tried reconnecting when already connected.", []),
%     {noreply, State};
% % DOWN Reason : 
% % {socket_error,timeout}
% % socket_closed_unexpectedly
% % killed
% handle_info(D={'DOWN', _Ref, process, _Pid, Reason}, #?STATE{ amqp_args = AMQPArgs,
%                         amqp_connection = C,
%                         amqp_channel = CH } = State) ->
%     io:format("Reason     : ~p~n", [Reason]),
%     io:format("Connection : ~p~n", [C]),
%     io:format("Channel    : ~p~n", [CH]),
%     io:format("Reason     : ~p~n", [D]),
%     print_state(State),
%     NewState = do_re_estb_conn(AMQPArgs, State),
%     {noreply, NewState};
% handle_info(Info, State) ->
%     io:format("~p handle_info ~p", [?MODULE, Info]),
%     print_state(State),
%     {noreply, State}.

% terminate(_Reason, _State) ->
%     true = lep_load_spread:del_producer_pid(self()),
%     ok.

% code_change(_OldVsn, State, _Extra) ->
%     {ok, State}.

% do_publish(Chan, BasicPub, AmqpProps, Payload) ->
%     Pub = #'basic.publish'{
%         ticket = proplists:get_value(content_encoding, BasicPub, 0),
%         exchange = proplists:get_value(exchange, BasicPub, <<"">>),
%         routing_key = proplists:get_value(routing_key, BasicPub, <<"">>),
%         mandatory = proplists:get_value(mandatory, BasicPub, false),
%         immediate = proplists:get_value(immediate, BasicPub, false)
%     },
%     Props = #'P_basic'{
%         content_type =
%             proplists:get_value(content_type, AmqpProps, <<"text/plain">>),
%         content_encoding =
%             proplists:get_value(content_encoding, AmqpProps),
%         headers =
%             proplists:get_value(headers, AmqpProps),
%         delivery_mode =
%             proplists:get_value(delivery_mode, AmqpProps),
%         priority =
%             proplists:get_value(priority, AmqpProps),
%         correlation_id =
%             proplists:get_value(correlation_id, AmqpProps),
%         reply_to =
%             proplists:get_value(reply_to, AmqpProps),
%         expiration =
%             proplists:get_value(expiration, AmqpProps),
%         message_id =
%             proplists:get_value(message_id, AmqpProps),
%         timestamp =
%             proplists:get_value(timestamp, AmqpProps),
%         type =
%             proplists:get_value(type, AmqpProps),
%         user_id =
%             proplists:get_value(user_id, AmqpProps),
%         app_id =
%             proplists:get_value(app_id, AmqpProps),
%         cluster_id =
%             proplists:get_value(cluster_id, AmqpProps)
%     },
%     AMQPMsg = #amqp_msg{
%         props = Props,
%         payload = Payload
%     },
%     try
%         % io:format("publish ~p #amqp_msg{props = ~p,payload = ~p}~n",
%         %     [?MODULE, P, Data]
%         % ),
%         ok = amqp_channel:call(Chan, Pub, AMQPMsg)
%     catch
%         C:E ->
%             io:format("Failed publishing message:~p ~p ~p\n",[C, E, erlang:get_stacktrace()]),
%             %% TODO: maybe check the status of those pids:
%             {error, {C,E,erlang:get_stacktrace()}}
%     end.

% print_state(State) ->
%     [?STATE | FieldValues] = tuple_to_list(State),
%     io:format(
%         "State:~p~n",
%         [lists:zip(record_info(fields, ?STATE), FieldValues)]
%     ).

% do_estb_conn(AMQPArgs) ->
%     case lep_common:establish_channel(AMQPArgs) of
%         {ok, Conn, Chan} ->
%             _Ref1 = erlang:monitor(process, Conn),
%             _Ref2 = erlang:monitor(process, Chan),
%             {ok, Conn, Chan};
%         {error, Reason} ->
%             io:format("Producer could not establish Connection Reason ~p~n", [Reason]),
%             {error, Reason}
%     end.

% do_re_estb_conn(AMQPArgs, State) ->
%     case do_estb_conn(AMQPArgs) of
%         {ok, Conn, Chan} ->
%             State#?STATE{
%                 amqp_connection = Conn,
%                 amqp_channel = Chan
%             };
%         {error, Reason} ->
%             {ok, Wait} = application:get_env(leporidae, reconnect_attempt_interval, 100),
%             {ok, _TRef} = timer:apply_after(Wait, erlang, send, [self(), reconnect]),
%             State#?STATE{
%                 amqp_connection = undefined, 
%                 amqp_channel = undefined,
%                 last_error = Reason
%             }
%     end.