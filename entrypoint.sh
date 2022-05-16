#!/bin/sh

set -x

readonly EJABBERD_READY_FILE="$HOME/.ejabberd_ready"

if [ -e "$EJABBERD_READY_FILE" ]; then
    rm "$EJABBERD_READY_FILE"
fi

if [ -n "$ERLANG_COOKIE" ]; then
    printf "$ERLANG_COOKIE" > "$HOME/.erlang.cookie"
    chmod 400 "$HOME/.erlang.cookie"
fi

: ${EJABBERD_CONFIG:="/config/ejabberd.yml"}
envsubst < "${EJABBERD_CONFIG}" > $HOME/conf/ejabberd.yml

: ${ERLANG_NODE_PREFIX:="ejabberd"}
: ${ERLANG_DOMAIN:="$(hostname -d)"}
: ${HOSTNAME:="$(hostname)"}
: ${ERLANG_NODE:="${ERLANG_NODE_PREFIX}@${HOSTNAME}.${ERLANG_DOMAIN}"}
export ERLANG_NODE_ARG="$ERLANG_NODE"

: ${ELECTION_NAME:="ejabberd"}
: ${ELECTION_URL:="localhost:4040"}
: ${ELECTION_NAMESPACE:="$(cat /run/secrets/kubernetes.io/serviceaccount/namespace)"}

leader_erlang_node() {
    leader="$(curl "$ELECTION_URL" | jq -r .leader)"
    leader_fqdn="${leader}.${ERLANG_DOMAIN}"
    echo "${ERLANG_NODE_PREFIX}@${leader_fqdn}"
}

join_cluster() {
    while true; do
        if [ "$(curl "$ELECTION_URL" | jq .is_leader)" == "true" ]; then
            echo "[entrypoint_script] We are leader"

            if nslookup "${ERLANG_DOMAIN}"; then # needs headless service with publishNotReadyAddresses: false
                echo "[entrypoint_script] Found other healthy pods but we are leader. Exiting..."
                #TODO: Join healthy pods instead of failing
                return 1
            fi
            echo "[entrypoint_script] Getting ready and waiting for others to join..."
            return 0
        else
            leader_erlang_node="$(leader_erlang_node)"
            echo "[entrypoint_script] Trying to join ${leader_erlang_node}..."
            ejabberdctl join_cluster "${leader_erlang_node}" && return 0
            sleep 5
        fi
    done
}

## Termination
EJABBERD_PID=0

terminate() {
    kill -s TERM "$ELECTOR_PID"
    if [ "$EJABBERD_PID" -ne 0 ]; then
        # Leave the cluster before terminating
        echo "[entrypoint_script] Leaving cluster '$ERLANG_NODE'"
        NO_WARNINGS=true ejabberdctl leave_cluster "$ERLANG_NODE"
        ejabberdctl stop > /dev/null
        ejabberdctl stopped > /dev/null

        kill -s TERM "$EJABBERD_PID"
        exit $1
    fi
}

trap "terminate" SIGTERM

## Start ejabberd
ejabberdctl foreground &
EJABBERD_PID=$!
elector -election "${ELECTION_NAME}" -namespace "${ELECTION_NAMESPACE}" \
    -http "${ELECTION_URL}"&
ELECTOR_PID=$!
ejabberdctl started
join_cluster && touch "$EJABBERD_READY_FILE" || terminate $?
wait "$EJABBERD_PID" "$ELECTOR_PID"
