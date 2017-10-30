-module(lep_common).

-include_lib("../amqp_client/include/amqp_client.hrl").

-export([
    establish_channel/1
]).

establish_channel(AMQPArgs) ->
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
    {ok, Conn} = amqp_connection:start(ConnParams),
    {ok, Chan} = amqp_connection:open_channel(Conn),
    {ok, Conn, Chan}.    
