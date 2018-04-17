# Leporidae
Leporidae is built on top of amqp_client.
configuring your consuming and producing is done per config file.

# Configuration Sections:
## Producers

Producers are started as a lep_produce_sm process that connects and creates a channel to rabbitmq.
You can produce/publish messages to a rabbitmq queue with the api call.
```
ok = lep_produce_sm:publish(Pid, BinaryData).
```
where Pid is the lep_produce_sm process id.

You can list all active producers with
```
lep_prod_sup:producers().
```

### Producers Config Options:
Minimal:
```
{leporidae, [
    {producers,[
        {amqp, [
            {connection, [
                {type, network},
                {username, <<"root">>},
                {passwd, <<"root">>},
                {vhost, <<"/">>},
                {host, "localhost"},
                {port, 5672}
            ]},
            {queue, [
                {queue, <<"queue1">>},
                {durable, true}
            ]}
        ]}
    ]}
]}
```

Queue bound to exchange example:
```
{leporidae, [
    {producers,[
        {amqp, [
            {routing_key, <<"xxx">>},
            {basic, [
                {delivery_mode, 2} % non­persistent (1) or persistent (2)
            ]},
            % TODO: change to use global_connection
            {connection, [
                {type, network},
                {username, <<"root">>},
                {passwd, <<"root">>},
                {vhost, <<"/">>},
                {host, "localhost"},
                {port, 5672}
            ]},
            {exchange,[
                {exchange, <<"exchange1">>},
                {type, <<"direct">>},
                {durable, true}
            ]},
            {queue, [
                {ticket, 0},
                {queue, <<"queue1">>},
                {passive, false},
                {durable, true},
                {exclusive, false},
                {auto_delete, false},
                {nowait, false},
                {arguments, []}
            ]}
        ]}
    ]}
]}
```

## Consumers

There are 3 types of consumer types: consume/get/subscribe.
Consumers are started as a lep_consume_sm process that connects and creates a channel to rabbitmq.

##### Get
A get consumer connects and creates a channel, and waits for a caller to get messages.

Example get call:
```
lep_consume_sm:get(Pid)
```
where Pid is the lep_consume_sm process id of consume type get.

Example:
```
(start-dev@host)3> lep_produce_sm:publish(pid(0,85,0), <<"1">>).
ok
(start-dev@host)6> lep_consume_sm:get(pid(0,82,0)).
<<"1">>
```

##### Consume/Subscribe.
A Consume/Subscribe consumer connects and creates a channel.
The Subscribe consumer uses amqp_channel:subscribe(..).
Whereas the Consume consumer sends a Basic.consume message to the rabbitmq server.

Consume/Subscribe needs a worker module when consuming messages.
the worker module should export consume/1, where the Argument is the #amqp_message{}.
( lep_example_consumer_worker.erl is a example )

You can list all active consumers with
```
lep_cons_sup:consumers().
```

### Consumers Config Options:
Get Example:
```
{leporidae, [
    {consumers, [
        {amqp, [
            {consume_type, get},
            {routing_key, <<"xxx">>},
            {get, [
                {no_ack, false}
            ]},
            {connection, [
                {type, network},
                {username, <<"root">>},
                {passwd, <<"root">>},
                {vhost, <<"/">>},
                {host, "localhost"},
                {port, 5672}
            ]},
            {queue, [
                {queue, <<"queue1">>}
            ]}
        ]}
    ]}
]}
```

Consume Example:
```
{leporidae, [
    {consumers, [
        {amqp, [
            {consume_type, consume},
            {consume_worker_mod, lep_example_consumer_worker},
            {routing_key, <<"xxx">>},
            {consume, [
                {no_ack, false},
                {exclusive, false},
                {nowait, false},
                {arguments, []}
            ]},
            {connection, [
                {type, network},
                {username, <<"root">>},
                {passwd, <<"root">>},
                {vhost, <<"/">>},
                {host, "localhost"},
                {port, 5672}
            ]},
            {exchange,[
                {exchange, <<"exchange1">>},
                {type, <<"direct">>},
                {durable, true}
            ]},
            {queue, [
                {ticket, 0},
                {queue, <<"leporidae">>},
                {passive, false},
                {durable, true},
                {exclusive, false},
                {auto_delete, false},
                {nowait, false},
                {arguments, []}
            ]}
        ]}
    ]}
]}
```

Subscribe example:
```
{leporidae, [
    {consumers, [
        {amqp, [
            {consume_type, subscription},
            {consume_worker_mod, lep_example_consumer_worker},
            {routing_key, <<"yyy">>},
            {get, [
                {no_ack, false}
            ]},
            {connection, [
                {type, network},
                {username, <<"root">>},
                {passwd, <<"root">>},
                {vhost, <<"/">>},
                {host, "localhost"},
                {port, 5672}
            ]},
            {queue, [
                {queue, <<"queue1">>}
            ]}
        ]}
    ]}
]}
```

## Config Defaults
Most defaults can be found in lep_common.erl

## Logging
lep_common:log is currently using io:format, which can be changed to lager/error_logger, or any other logging calls later.