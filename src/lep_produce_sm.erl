-module(lep_produce_sm).

%% API
-export([start_link/1]).

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

-define(REG_NAME, {local, ?MODULE}).

start_link(AMQPArgs) ->
    gen_statem:start_link(?REG_NAME, ?MODULE, {AMQPArgs}, []).

% @doc 3 possible states:
% - connected_and_chan   - connection established and channel established
% - connected_notchannel - connection established and channel failed
% - notconnection        - connection failed and channel failed
% @end
% Return: {ok, StateName, _Data = #{}}.
init({AMQPArgs}) ->
    % log("init~n~n"),
    % {NextState, StateData} = do_conn_and_chan(AMQPArgs, #{}),
    StateData =
    #{
        amqp_args => AMQPArgs,
        amqp_queue => undefined,
        amqp_exchange => undefined,
        amqp_connection => undefined,
        amqp_channel => undefined,
        last_error => undefined,
        conn_ref => undefined,
        chan_ref => undefined
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

handle_event(timeout, EventContent=establish_connection, S=notconnection, StateData) ->
    % How would you do matching on maps?
    % I remove the lines below from a pattern match on the function declaration.
    % Cause it's picky on the size of the map ???
    % #{amqp_args := AMQPArgs,
    %   amqp_connection := undefined,
    %   amqp_channel := undefined} = StateData,
    #{amqp_args := AMQPArgs} = StateData,
    % log("S ~p EventContent ~p~n", [S, EventContent]),
    % log("CONNECTING~n"),
    case do_conn_and_chan(AMQPArgs, StateData) of
        {S, NewStateData} ->
            %log("NO CONNECTION~n"),
            {keep_state, NewStateData,
                [{timeout, 100, EventContent}]
            };
        {NextState=connected_notchannel, NewStateData} ->
            %log("CONNECTION NO CHANNEL~n"),
            {next_state, NextState, NewStateData,
                [{timeout, 100, establish_channel}]
            };
        {NextState=connected_and_chan, NewStateData} ->
            %log("CONNECTION & CHANNEL~n"),
            {next_state, NextState, NewStateData}
    end;
handle_event(timeout, EventContent=establish_channel, S=connected_notchannel, StateData) ->
    % #{amqp_connection := Conn,
    %   amqp_channel := undefined} = StateData,
    #{amqp_connection := Conn} = StateData,
    % log("S ~p EventContent ~p~n", [S, EventContent]),
    %%log("OPENING CHANNEL~n"),
    case lep_common:establish_channel(Conn) of
        {ok, Conn, Chan} ->
            %%log("Conn ~p Chan ~p~n", [Conn, Chan]),
            %%log("CHANNEL OPEN~n"),
            NewStateData = StateData#{
                amqp_channel := Chan,
                last_error => undefined
            },
            {next_State, connected_and_chan, NewStateData};
        {error, {chan_error, ChanError, Conn}} ->
            %%log("CHANNEL ERROR~n"),
            NewStateData = StateData#{
                last_error => {error, {chan_error, ChanError}}
            },
            {keep_state, NewStateData, [{timeout, 100, establish_channel}]}
    end;
handle_event(info, D={'DOWN', Ref, process, Pid, DownReason}, CurentState, StateData) ->
    #{ amqp_connection := Conn,
       amqp_channel := Chan,
       conn_ref := ConnRef,
       chan_ref := ChanRef } = StateData,
    case {Ref, Pid} of
        {ConnRef, Conn} ->
            %%log("CONNECTION DOWN IN STATE ~p REASON ~p in state ~p~n",
                %%[StateData, DownReason, CurentState]),
            NewStateData = StateData#{
                amqp_connection => undefined,
                last_error => D,
                conn_ref => undefined
            },
            {next_state, notconnection, NewStateData,
                [{timeout, 0, establish_connection}]
            };
        {ChanRef, Chan} ->
            %%log("CHANNEL DOWN IN STATE ~p REASON ~p in state ~p~n",
                %%[StateData, DownReason, CurentState]),
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
handle_event(EventType, EventContent, CurentState, Data) ->
    log("~p handle_event(~p, ~p, ~p, ~p)~n",
        [?MODULE, EventType, EventContent, CurentState, Data]),
    {next_state, initial_state, _NewData = Data}.

terminate(Reason, State, Data) ->
    log("~p terminate(~p, ~p, ~p)~n",
        [?MODULE, Reason, State, Data]),
    ok.

-spec do_conn_and_chan(proplists:proplist(), map()) ->
    {NextState :: connected_and_chan | connected_notchannel | notconnection,
     StateData :: map()
    }.
do_conn_and_chan(AMQPArgs, StateData) ->
    case lep_common:establish_connection_channel(AMQPArgs) of
        {ok, Conn, Chan} ->
            %%log("Conn ~p Chan ~p~n", [Conn, Chan]),
            ConnRef = erlang:monitor(process, Conn),
            %%log("ConnRef ~p~n", [ConnRef]),
            ChanRef = erlang:monitor(process, Chan),
            %%log("ChanRef ~p~n", [ChanRef]),
            {ok, Queue, Exchange} =
                lep_common:do_producer_rest_init(Conn, Chan, AMQPArgs),
            {connected_and_chan, StateData#{
                amqp_args => AMQPArgs,
                amqp_queue => Queue,
                amqp_exchange => Exchange,
                amqp_connection => Conn,
                amqp_channel => Chan,
                last_error => undefined,
                conn_ref => ConnRef,
                chan_ref => ChanRef
            }};
        {error, {chan_error, ChanError, Conn}} ->
            {connected_notchannel, StateData#{
                amqp_args => AMQPArgs,
                amqp_connection => Conn,
                last_error => {error, {chan_error, ChanError}}
            }};
        {error, {conn_error, ConnError}} ->
            {notconnection, StateData#{
                amqp_args => AMQPArgs,
                last_error => {error, {conn_error, ConnError}}
            }}
    end.

log(X) ->
    log(X, []).

log(X, Y) ->
    io:format(X, Y).