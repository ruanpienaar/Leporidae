#!/bin/sh
cd `dirname $0`
exec erl -sname start-dev -config $PWD/sys.config \
-pa $PWD/amqp_client/deps/*/ebin -pa $PWD/amqp_client/ebin -pa $PWD/_build/default/lib/*/ebin \
$PWD/test -boot start_sasl -setcookie start-dev -run leporidae_app start