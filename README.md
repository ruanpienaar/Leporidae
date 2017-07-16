# Leporidae
Leporidae

## Getting started
( edit sys.config )
```
[
 {leporidae,
    [
        {producers,[
            {amqp, [
                %% Localhost
                {connection, [
                    {type, network},
                    {username, <<"root">>},
                    {passwd, <<"root">>},
                    {vhost, <<"/">>},
                    {host, "127.0.0.1"},
                    {port, 5672}
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
        ]},

        {consumers,[
            %% Localhost
            {amqp, [
                {connection, [
                    {type, network},
                    {username, <<"root">>},
                    {passwd, <<"root">>},
                    {vhost, <<"/">>},
                    {host, "127.0.0.1"},
                    {port, 5672}
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
].

```

### Running it
make
./satrt-dev.sh
rr(amqp_channel).

### Examples:

10 msgs per s
```
[ begin timer:sleep(100), lep_produce:produce(list_to_binary(integer_to_list(X))) end || X <- lists:seq(1, 60000) ].
```

500/s ( 6 mil messages )
```
[ begin timer:sleep(1), lep_produce:produce(list_to_binary(integer_to_list(X))) end || X <- lists:seq(1, 60000 * 100) ].
```