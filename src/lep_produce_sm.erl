-module(lep_produce_sm).

-behaviour(gen_statem).
-include_lib("../amqp_client/include/amqp_client.hrl").

%% API
-export([
    start_link/1,
    publish/2
]).

%% State M exports
-export([
    init/1, callback_mode/0, handle_event/4, terminate/3
]).

%% optional_callbacks:
% format_status/2 -> Has got a default implementation
% terminate/3,    -> Has got a default implementation
% code_change/4,  -> Only needed by advanced soft upgrade
% state_name/3,   -> Example for callback_mode() =:= state_functions:
%                 there has to be a StateName/3 callback function
%                 for every StateName in your state machine but the state name
%                 'state_name' does of course not have to be used.
% handle_event/4 -> For callback_mode() =:= handle_event_function

start_link(AMQPArgs) ->
    gen_statem:start_link(?MODULE, {AMQPArgs}, []).

publish(Pid, Data) ->
    gen_statem:call(Pid, {publish, Data}).

% @doc 3 possible states:
% - connected_and_chan   - connection established and channel established
% - connected_notchannel - connection established and channel failed
% - notconnection        - connection failed and channel failed
% @end
% Return: {ok, StateName, _Data = #{}}.
init({AMQPArgs}) ->
    % log("init~n~n"),
    StateData =
    #{ amqp_args => AMQPArgs,
       amqp_connection => undefined,
       amqp_channel => undefined,
       conn_ref => undefined,
       chan_ref => undefined,
       amqp_queue => undefined,
       amqp_exchange => undefined,
       last_error => undefined
    },
    {ok, notconnection, StateData, [{timeout, 0, establish_connection} ]}.

%% 'state_functions' | 'handle_event_function'
callback_mode() ->
    'handle_event_function'.

%% {next_state, NextState, NewData} % {next_state,NextState,NewData,[]} |
%% {next_state, NextState, NewData, ActionsList | action()}
%% {keep_state, NewData} % {keep_state, NewData, []} |
%% {keep_state, NewData, ActionsList} |
%% keep_state_and_data % {keep_state_and_data,[]} |
%% {keep_state_and_data, ActionsList} |
%% {repeat_state, NewData} % {repeat_state,NewData,[]} |
%% {repeat_state, NewData, ActionsList} |
%% repeat_state_and_data % {repeat_state_and_data,[]} |
%% {repeat_state_and_data, ActionsList} |
%% stop % {stop,normal} |
%% {stop, Reason} |
%% {stop, Reason, NewData} |
%% {stop_and_reply, Reason, Replies} |
%% {stop_and_reply, Reason, Replies, NewData}.

handle_event(timeout, EventContent=establish_connection, notconnection, StateData) ->
    #{amqp_args := AMQPArgs,
      amqp_connection := undefined,
      amqp_channel := undefined
    } = StateData,
    case lep_common:establish_connection_channel(AMQPArgs) of
        {ok, Conn, Chan} ->
            ConnRef = erlang:monitor(process, Conn),
            ChanRef = erlang:monitor(process, Chan),
            {ok, Queue, Exchange} =
                lep_common:bind_queue_exchange(Chan, AMQPArgs),
            {next_state, connected_and_chan, StateData#{
                amqp_connection => Conn,
                amqp_channel => Chan,
                conn_ref => ConnRef,
                chan_ref => ChanRef,
                amqp_queue => Queue,
                amqp_exchange => Exchange,
                last_error => undefined
            }};
        {error, {conn_error, ConnError}} ->
            {keep_state,
                StateData#{
                    amqp_args => AMQPArgs,
                    amqp_connection => undefined,
                    amqp_channel => undefined,
                    conn_ref => undefined,
                    chan_ref => undefined,
                    amqp_queue => undefined,
                    amqp_exchange => undefined,
                    last_error => {error, {conn_error, ConnError}}
                },
                [{timeout, 100, EventContent}]
            };
        {error, {chan_error, ChanError, Conn}} ->
            ConnRef = erlang:monitor(process, Conn),
            {next_state, connected_notchannel,
                StateData#{
                    amqp_args => AMQPArgs,
                    amqp_connection => Conn,
                    amqp_channel => undefined,
                    conn_ref => ConnRef,
                    chan_ref => undefined,
                    amqp_queue => undefined,
                    amqp_exchange => undefined,
                    last_error => {error, {chan_error, ChanError, Conn}}
                },
                [{timeout, 100, establish_channel}]
            }
    end;
handle_event(timeout, EventContent=establish_channel, connected_notchannel, StateData) ->
    #{amqp_args := AMQPArgs,
      amqp_connection := Conn,
      amqp_channel := undefined} = StateData,
    case lep_common:establish_channel(Conn) of
        {ok, Conn, Chan} ->
            ChanRef = erlang:monitor(process, Chan),
            {ok, Queue, Exchange} =
                lep_common:bind_queue_exchange(Chan, AMQPArgs),
            {next_state, connected_and_chan, StateData#{
                amqp_channel => Chan,
                chan_ref => ChanRef,
                amqp_queue => Queue,
                amqp_exchange => Exchange,
                last_error => undefined
            }};
        {error, {chan_error, ChanError, Conn}} ->
            ConnRef = erlang:monitor(process, Conn),
            {keep_state,
                StateData#{
                    amqp_args => AMQPArgs,
                    amqp_connection => Conn,
                    amqp_channel => undefined,
                    conn_ref => ConnRef,
                    chan_ref => undefined,
                    amqp_queue => undefined,
                    amqp_exchange => undefined,
                    last_error => {error, {chan_error, ChanError, Conn}}
                },
                [{timeout, 100, EventContent}]
            }
    end;
handle_event(info, D={'DOWN', Ref, process, Pid, DownReason}, CurentState, StateData) ->
    #{ amqp_connection := Conn,
       amqp_channel := Chan,
       conn_ref := ConnRef,
       chan_ref := ChanRef } = StateData,
    case {Ref, Pid} of
        {ConnRef, Conn} ->
            log("CONNECTION DOWN IN STATE ~p REASON ~p in state ~p~n",
                [StateData, DownReason, CurentState]),
            NewStateData = StateData#{
                amqp_connection => undefined,
                last_error => D,
                conn_ref => undefined
            },
            {next_state, notconnection, NewStateData,
                [{timeout, 0, establish_connection}]
            };
        {ChanRef, Chan} ->
            log("CHANNEL DOWN IN STATE ~p REASON ~p in state ~p~n",
                [StateData, DownReason, CurentState]),
            NewStateData = StateData#{
                amqp_channel => undefined,
                last_error => D,
                chan_ref => undefined
            },
            case {Conn, ConnRef} of
                {undefined, undefined} ->
                    % Connection dies first, conn is this case is gone. ignore this DOWN.
                    {next_state, notconnection, NewStateData,
                        [{timeout, 0, establish_connection}]
                    };
                _ ->
                    {next_state, connected_notchannel, NewStateData,
                        [{timeout, 0, establish_channel}]
                    }
            end;
        _ ->
            %%log("Unknown DOWN! ~p in state ~p~n", [D, CurentState]),
            keep_state_and_data
    end;
handle_event({call, From}, {publish, Payload}, connected_and_chan, StateData) ->
    #{ amqp_args := AMQPArgs,
       amqp_channel := Chan,
       amqp_exchange := Exchange } = StateData,
    RoutingKey = proplists:get_value(routing_key, AMQPArgs),
    case do_publish(Chan, [{routing_key, RoutingKey},{exchange, Exchange}], [], Payload) of
        ok ->
            ok = gen_statem:reply({reply, From, ok});
        {error, ErrorState} ->
            ok = gen_statem:reply({reply, From, {publish_error, ErrorState}})
    end,
    keep_state_and_data;
handle_event({call, From}, {publish, _Payload}, OtherState, _StateData) ->
    ok = gen_statem:reply({reply, From, {in_wrong_state_error, OtherState}}),
    keep_state_and_data;
handle_event(EventType, EventContent, CurentState, Data) ->
    log("~p handle_event(~p, ~p, ~p, ~p)~n",
        [?MODULE, EventType, EventContent, CurentState, Data]),
    {next_state, initial_state, _NewData = Data}.

terminate(Reason, State, Data) ->
    % true = lep_load_spread:del_producer_pid(self()),
    log("~p terminate(~p, ~p, ~p)~n",
        [?MODULE, Reason, State, Data]),
    ok.

% -spec do_conn_and_chan(proplists:proplist(), map()) ->
%     {NextState :: connected_and_chan | connected_notchannel | notconnection,
%      StateData :: map()
%     }.
% do_conn_and_chan(AMQPArgs, StateData) ->
%     case lep_common:establish_connection_channel(AMQPArgs) of
%         {ok, Conn, Chan} ->
%             %%log("Conn ~p Chan ~p~n", [Conn, Chan]),
%             ConnRef = erlang:monitor(process, Conn),
%             %%log("ConnRef ~p~n", [ConnRef]),
%             ChanRef = erlang:monitor(process, Chan),
%             %%log("ChanRef ~p~n", [ChanRef]),
%             {connected_and_chan, StateData#{
%                 amqp_args => AMQPArgs,
%                 amqp_queue => Queue,
%                 amqp_exchange => Exchange,
%                 amqp_connection => Conn,
%                 amqp_channel => Chan,
%                 last_error => undefined,
%                 conn_ref => ConnRef,
%                 chan_ref => ChanRef
%             }};
%         {error, {chan_error, ChanError, Conn}} ->
%             {connected_notchannel, StateData#{
%                 amqp_args => AMQPArgs,
%                 amqp_connection => Conn,
%                 last_error => {error, {chan_error, ChanError}}
%             }};
%         {error, {conn_error, ConnError}} ->
%             {notconnection, StateData#{
%                 amqp_args => AMQPArgs,
%                 last_error => {error, {conn_error, ConnError}}
%             }}
%     end.

do_publish(Chan, BasicPub, AmqpProps, Payload) ->
    Pub = #'basic.publish'{
        ticket = proplists:get_value(ticket, BasicPub, 0),
        exchange = proplists:get_value(exchange, BasicPub, <<"">>),
        routing_key = proplists:get_value(routing_key, BasicPub, <<"">>),
        mandatory = proplists:get_value(mandatory, BasicPub, false),
        immediate = proplists:get_value(immediate, BasicPub, false)
    },
    Props = #'P_basic'{
        content_type =
            proplists:get_value(content_type, AmqpProps, <<"text/plain">>),
        content_encoding =
            proplists:get_value(content_encoding, AmqpProps),
        headers =
            proplists:get_value(headers, AmqpProps),
        delivery_mode =
            proplists:get_value(delivery_mode, AmqpProps),
        priority =
            proplists:get_value(priority, AmqpProps),
        correlation_id =
            proplists:get_value(correlation_id, AmqpProps),
        reply_to =
            proplists:get_value(reply_to, AmqpProps),
        expiration =
            proplists:get_value(expiration, AmqpProps),
        message_id =
            proplists:get_value(message_id, AmqpProps),
        timestamp =
            proplists:get_value(timestamp, AmqpProps),
        type =
            proplists:get_value(type, AmqpProps),
        user_id =
            proplists:get_value(user_id, AmqpProps),
        app_id =
            proplists:get_value(app_id, AmqpProps),
        cluster_id =
            proplists:get_value(cluster_id, AmqpProps)
    },
    AMQPMsg = #amqp_msg{
        props = Props,
        payload = Payload
    },
    try
        %% TODO: maybe not try_catch, and let the gen_statem, crash/go-into-another state ?
        log("amqp_channel:call(~p, ~p, ~p)~n", [Chan, Pub, AMQPMsg]),
        ok = amqp_channel:call(Chan, Pub, AMQPMsg)
    catch
        C:E ->
            log("Failed publishing message:~p ~p ~p\n",[C, E, erlang:get_stacktrace()]),
            %% TODO: maybe check the status of those pids:
            {error, {C,E,erlang:get_stacktrace()}}
    end.

log(X) ->
    log(X, []).

log(X, Y) ->
    io:format(X, Y).