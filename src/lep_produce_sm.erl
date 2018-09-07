-module(lep_produce_sm).

-behaviour(gen_statem).
-include("leporidae.hrl").

%% API
-export([
    start_link/1,
    state/1,
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
    case proplists:get_value(name, AMQPArgs, []) of
        [] ->
            gen_statem:start_link(?MODULE, {AMQPArgs}, []);
        Name ->
            gen_statem:start_link({local, Name}, ?MODULE, {AMQPArgs}, [])
    end.

state(NameOrPid) ->
    sys:get_state(NameOrPid).

publish(NameOrPid, Data) ->
    gen_statem:call(NameOrPid, {publish, Data}).

% @doc 3 possible states:
% - connected_and_chan   - connection established and channel established
% - connected_notchannel - connection established and channel failed
% - notconnection        - connection failed and channel failed
% @end
% Return: {ok, StateName, _Data = #{}}.
init({AMQPArgs}) ->
    ExchangeOpts = proplists:get_value(exchange, AMQPArgs, []),
    Exchange = proplists:get_value(exchange, ExchangeOpts, ?DEFAULT_EXCHANGE),
    RoutingKey =
        case Exchange of
            ?DEFAULT_EXCHANGE ->
                {queue, QueueOpts} = proplists:lookup(queue, AMQPArgs),
                {queue, Queue} = proplists:lookup(queue, QueueOpts),
                Queue;
            _ ->
                {routing_key, R} = proplists:lookup(routing_key, AMQPArgs),
                R
        end,
    Publish = [{routing_key, RoutingKey}, {exchange, Exchange}],
    Basic = proplists:get_value(basic, AMQPArgs, []),
    StateData =
        #{ amqp_args => AMQPArgs,
           publish => Publish,
           basic => Basic,
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
            lep_common:log("CONNECTION DOWN IN STATE ~p REASON ~p in state ~p~n",
                [StateData, DownReason, CurentState]),
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
        {ChanRef, Chan} ->
            lep_common:log("CHANNEL DOWN IN STATE ~p REASON ~p in state ~p~n",
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
    #{publish := Publish,
       basic := Basic,
       amqp_channel := Chan} = StateData,
    case lep_common:do_publish(Chan, Publish, Basic, Payload) of
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
    lep_common:log("~p handle_event(~p, ~p, ~p, ~p)~n",
        [?MODULE, EventType, EventContent, CurentState, Data]),
    keep_state_and_data.

terminate(Reason, State, Data) ->
    % true = lep_load_spread:del_producer_pid(self()),
    lep_common:log("~p terminate(~p, ~p, ~p)~n",
        [?MODULE, Reason, State, Data]),
    ok.