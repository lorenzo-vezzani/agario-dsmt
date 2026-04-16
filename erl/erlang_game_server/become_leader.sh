#!/bin/bash

NAME=$1

cd ../nodes_supervisor || exit 1
exec rebar3 shell --name $NAME --setcookie mycookie
