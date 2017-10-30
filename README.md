# Leporidae
Leporidae

## Getting started
( edit sys.config )
have a look at the example [sys.config](https://github.com/ruanpienaar/leporidae/blob/master/sys.config)

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