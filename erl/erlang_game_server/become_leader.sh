#!/bin/bash

IP=$1
NODES_LIST=$2
CONFIG_FILE="temp_nodes.config"

cd ../nodes_supervisor || exit 1

# Creiamo il contenuto del file di configurazione Erlang
# Il formato deve essere: [{app_name, [{key, value}]}].
echo "[{myapp, [{nodes_list, $NODES_LIST}]}]." > "$CONFIG_FILE"

# Trap per cancellare il file alla chiusura dello script
trap 'rm -f "$CONFIG_FILE"' EXIT INT TERM

echo "Avvio rebar3 con configurazione dinamica: $CONFIG_FILE"

# Eseguiamo rebar3 usando il flag --config
exec rebar3 shell \
  --name nodes_supervisor@"$IP" \
  --setcookie mycookie \
  --config "$CONFIG_FILE"