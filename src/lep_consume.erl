-module(lep_consume).

-export([
    start/1,
    start_link/1,
    consume/0
]).

-behaviour(gen_server).
-include_lib("../amqp_client/include/amqp_client.hrl").

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-define(STATE, lep_consume_state).
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

consume() ->
    Children = supervisor:which_children(leporidae_sup),
    {consumer_1,Pid,worker,[consumer_1]} = lists:keyfind(consumer_1, 1, Children),
    gen_server:call(Pid, consume).

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
    BC = #'basic.consume'{ queue = Queue },
    #'basic.consume_ok'{} = amqp_channel:subscribe(Chan, BC, self()),

    % ok = amqp_channel:register_default_consumer(Chan, self()),

    {ok, #?STATE{
        connected = true,
        queue = Queue,
        amqp_connection_opts = ConnOpts,
        amqp_connection = Conn,
        amqp_channel = Chan
    }}.

handle_call(consume, _From, #?STATE{queue = Queue, amqp_channel = Chan} = State) ->
    BC = #'basic.consume'{
        consumer_tag = list_to_binary(pid_to_list(self())),
        queue = Queue,
        no_ack = false,
        exclusive = false,
        nowait = false,
        arguments = []
    },
    R = #'basic.consume_ok'{consumer_tag = CT} = amqp_channel:call(Chan, BC),
    io:format("handle_call ~p ~p ~n", [?MODULE, R]),
    {reply, ok, State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({#'basic.deliver'{delivery_tag = DT}, #amqp_msg{ payload = Data }},
            #?STATE{amqp_channel = Chan} = State) ->
    % io:format("handle_info ~p #'basic.deliver' delivery_tag = ~p ~p~n", [?MODULE, DT, Data]),
    %% Acknoledge
    ACK = #'basic.ack'{
        delivery_tag = DT,
        multiple = false
    },
    ok = amqp_channel:call(Chan, ACK),
    {noreply, State};
handle_info(#'basic.consume_ok'{consumer_tag = CT}, State) ->
    io:format("handle_info ~p #'basic.consume_ok' consumer_tag = ~p ~n", [?MODULE, CT]),
    {noreply, State};
handle_info(Info, State) ->
    io:format("handle_info ~p handle_info ~p", [?MODULE, Info]),
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.