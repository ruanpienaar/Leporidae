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
        last_error => undefined
    },
    {ok, notconnection, StateData, [{conn_timeout_name,0,establish_connection}]}.

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

handle_event(conn_timeout_name, establish_connection, notconnection, 
        #{amqp_args := AMQPArgs,
          amqp_connection := undefined,
          amqp_channel := undefined} = StateData) ->
    log("~p handle_event(~p, ~p, ~p, ...)~n",
        [?MODULE, info, establish_connection, notconnection]),
    log("reconnect~n"),
    case do_conn_and_chan(AMQPArgs, StateData) of
        {NextState=notconnection, NewStateData} ->
            log("NO CONNECTION~n"),
            % {next_state, notconnection, NewStateData, [{state_timeout, 100, notconnection}]};
            {keep_state, NewStateData, 
                [{conn_timeout_name,1000,establish_connection}]
            };
        {NextState=connected_notchannel, NewStateData} ->
            ok;
        {NextState, NewStateData} ->
            ok
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
            _Ref1 = erlang:monitor(process, Conn),
            _Ref2 = erlang:monitor(process, Chan),
            {ok, Queue, Exchange} =
                lep_common:do_producer_rest_init(Conn, Chan, AMQPArgs),
            {connected_and_chan, StateData#{
                amqp_args => AMQPArgs,
                amqp_queue => Queue,
                amqp_exchange => Exchange,
                amqp_connection => Conn,
                amqp_channel => Chan,
                last_error => undefined
            }};
        {error, {chan_error, ChanError, Conn}} ->
            %self() ! establish_channel,
            {connected_notchannel, StateData#{
                amqp_args => AMQPArgs,
                amqp_queue => undefined,
                amqp_exchange => undefined,
                amqp_connection => Conn,
                amqp_channel => undefined,
                last_error => {error, {chan_error, ChanError}}
            }};
        {error, {conn_error, ConnError}} ->
            %self() ! establish_connection,
            {notconnection, StateData#{
                amqp_args => AMQPArgs,
                amqp_queue => undefined,
                amqp_exchange => undefined,
                amqp_connection => undefined,
                amqp_channel => undefined,
                last_error => {error, {conn_error, ConnError}}
            }}
    end.

log(X) ->
    log(X, []).

log(X, Y) ->
    io:format(X, Y).