-module(lep_consume_sm).

-behaviour(gen_statem).
-include_lib("amqp_client/include/amqp_client.hrl").
-include("leporidae.hrl").

%% API
-export([
    start_link/1,
    state/1,
    % consume/1,
    get/1
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

state(NameOrPid) ->
    sys:get_state(NameOrPid).

% consume(NameOrPid) ->
%     gen_statem:call(NameOrPid, consume, 1000).

get(NameOrPid) ->
    gen_statem:call(NameOrPid, get, 1000).

% publish(NameOrPid, Data) ->
%     gen_statem:call(NameOrPid, {publish, Data}).

% @doc 3 possible states:
% - connected_and_chan   - connection established and channel established
% - connected_notchannel - connection established and channel failed
% - notconnection        - connection failed and channel failed
% @end
% Return: {ok, StateName, _Data = #{}}.
init({AMQPArgs}) ->
    {queue, QueueOpts} = proplists:lookup(queue, AMQPArgs),
    {queue, Queue} = proplists:lookup(queue, QueueOpts),
    Consume = [{queue, Queue} | proplists:get_value(consume, AMQPArgs, [])],
    Get = [{queue, Queue} | proplists:get_value(get, AMQPArgs, [])],
    ConsType = proplists:get_value(consume_type, AMQPArgs, ?CONSUME_TYPE_GET),
    ConnectedActions =
        case ConsType of
            ?CONSUME_TYPE_CONSUME ->
                % TODO: should we have mulitple consumers
                [{timeout, 0, start_consumer}];
            ?CONSUME_TYPE_GET ->
                [];
            ?CONSUME_TYPE_SUB ->
                [{timeout, 0, establish_subscription}]
        end,
    StateData =
        #{ amqp_args => AMQPArgs,
           consume_type => ConsType,
           consume => Consume,
           get => Get,
           amqp_connection => undefined,
           amqp_channel => undefined,
           conn_ref => undefined,
           chan_ref => undefined,
           amqp_queue => undefined,
           amqp_exchange => undefined,
           last_error => undefined,
           connected_actions => ConnectedActions,
           consume_worker_mod => proplists:get_value(consume_worker_mod, AMQPArgs)
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
      amqp_channel := undefined,
      connected_actions := Actions } = StateData,
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
            }, Actions};
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
      amqp_channel := undefined,
      connected_actions := Actions} = StateData,
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
            }, Actions};
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
%% ---  Consumer
handle_event(timeout, start_consumer, connected_and_chan, StateData) ->
    #{ amqp_channel := Chan,
       consume := Consume
    } = StateData,
    lep_common:do_consume(Chan, list_to_binary(pid_to_list(self())), Consume),
    {next_state, consuming, StateData};
handle_event(info, M=#'basic.consume_ok'{consumer_tag = CT}, consuming, StateData) ->
    lep_common:log(" === ~p CONSUME_OK === ~n~p~n", [self(), M]),
    % Consumer started on server...
    % TODO: should we reuse this consumer, or keep creating consumers ?
    {keep_state, StateData#{ consumer_tag => CT }};
handle_event(info, {BasicDeliver, AmqpMsg}, consuming, StateData) ->
    %lep_common:log(" === ~p consuming DELIVERY === ~n~p~n", [self(), BasicDeliver]),
    %lep_common:log(" === ~p consuming AMQP MSG === ~n~p~n", [self(), AmqpMsg]),
    #{ amqp_channel := Chan,
       consumer_tag := CT,
       consume_worker_mod := Mod
       } = StateData,
    #'basic.deliver'{
        consumer_tag = CT,
        delivery_tag = DT
    } = BasicDeliver,
    % TODO: how do we prevent the consume function
    % from hanging ?
    try
        ok = Mod:consume(AmqpMsg),
        Ack = [{delivery_tag, DT}, {multiple, false}],
        ok = lep_common:do_acknowledge(Chan, Ack)
    catch
        C:E ->
            NAck = [{delivery_tag, DT}, {multiple, false}, {requeue, true}],
            ok = lep_common:do_no_acknowledge(Chan, NAck),
            lep_common:log("Message consume failed ~p ~p ", [C, E])
    end,
    {keep_state, StateData};
%% ---  Get
handle_event({call, From}, get, connected_and_chan, StateData) ->
    #{ amqp_channel := Chan,
       get := Get} = StateData,
    Payload = lep_common:do_get(Chan, Get),
    ok = gen_statem:reply({reply, From, Payload}),
    keep_state_and_data;
%% ---  Subscribe
handle_event(timeout, establish_subscription, connected_and_chan, StateData) ->
    #{amqp_channel := Chan,
      amqp_queue := Queue} = StateData,
    % TODO: fail when subs fail...
    _R = lep_common:do_subscribe(Chan, Queue, self()),
    {next_state, subscribed, StateData};
handle_event(info, M=#'basic.consume_ok'{consumer_tag = CT}, subscribed, StateData) ->
    lep_common:log(" === ~p CONSUME_OK === ~n~p~n", [self(), M]),
    % Consumer started on server...
    % TODO: should we reuse this consumer, or keep creating consumers ?
    {keep_state, StateData#{ consumer_tag => CT }};
handle_event(info, {BasicDeliver, AmqpMsg}, subscribed, StateData) ->
    %lep_common:log(" === ~p subscribed DELIVERY === ~n~p~n", [self(), BasicDeliver]),
    %lep_common:log(" === ~p subscribed AMQP MSG === ~n~p~n", [self(), AmqpMsg]),
    #{ amqp_channel := Chan,
       consumer_tag := CT,
       consume_worker_mod := Mod
       } = StateData,
    #'basic.deliver'{
        consumer_tag = CT,
        delivery_tag = DT
    } = BasicDeliver,
    % TODO: how do we prevent the consume function
    % from hanging ?
    try
        ok = Mod:consume(AmqpMsg),
        Ack = [{delivery_tag, DT}, {multiple, false}],
        ok = lep_common:do_acknowledge(Chan, Ack)
    catch
        C:E ->
            NAck = [{delivery_tag, DT}, {multiple, false}, {requeue, true}],
            ok = lep_common:do_no_acknowledge(Chan, NAck),
            lep_common:log("Message consume failed ~p ~p ", [C, E])
    end,
    % ok = lep_common:do_acknowledge(Chan, [{delivery_tag, DT}, {multiple, false}]),
    {keep_state, StateData};
%% --- DOWN
handle_event(info, D={'DOWN', Ref, process, Pid, DownReason}, CurentState, StateData) ->
    #{ amqp_connection := Conn,
       amqp_channel := Chan,
       conn_ref := ConnRef,
       chan_ref := ChanRef } = StateData,
    % What has gone 'DOWN' ?
    case {Ref, Pid} of
        % Connection DOWN
        {ConnRef, Conn} ->
            lep_common:log(" === ~p Conn {'DOWN'} State:~p ~p ~n",
                [self(), CurentState, DownReason]),
            NewStateData = StateData#{
                amqp_connection => undefined,
                amqp_channel => undefined,
                conn_ref => undefined,
                chan_ref => undefined,
                amqp_queue => undefined,
                amqp_exchange => undefined,
                last_error => D
            },
            {next_state, notconnection, NewStateData,
                [{timeout, 0, establish_connection}]
            };
        % Channel DOWN
        {ChanRef, Chan} ->
            lep_common:log(" === ~p Chan {'DOWN'} State:~p ~p ~n",
                [self(), CurentState, DownReason]),
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
            lep_common:log(" === ~p Unknown DOWN! ~p in state ~p ~p~n", [self(), D, CurentState, StateData]),
            keep_state_and_data
    end;
handle_event(EventType, EventContent, CurentState, Data) ->
    lep_common:log("~p handle_event(~p, ~p, ~p, ~p)~n",
        [?MODULE, EventType, EventContent, CurentState, Data]),
    keep_state_and_data.

terminate(Reason, State, Data) ->
    % true = lep_load_spread:del_producer_pid(self()),
    lep_common:log("~p terminate(~p, ~p, ~p)~n",
        [?MODULE, Reason, State, Data]),
    ok.