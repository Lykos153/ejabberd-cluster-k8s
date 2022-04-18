#!/bin/sh

# from https://github.com/processone/docker-ejabberd/issues/64#issuecomment-814310376

set -x

readonly EJABBERD_READY_FILE="$HOME/.ejabberd_ready"
readonly EJABBERD_CLUSTER_READY_FILE="$HOME/.ejabberd_cluster_ready"

# Mark ejabberd as not ready so the `ready-probe.sh` script would be able to know about it.
if [ -e "$EJABBERD_READY_FILE" ]; then
    rm "$EJABBERD_READY_FILE"
fi

if [ -n "$ERLANG_COOKIE" ]; then
    printf "$ERLANG_COOKIE" > "$HOME/.erlang.cookie"
    chmod 400 "$HOME/.erlang.cookie"
fi

echo ERLANG_NODE='ejabberd@$(hostname -f)' >> conf/ejabberdctl.cfg

## Clustering
join_cluster() {
    # No need to look for a cluster to join if joined before.
    if [ -e "$EJABBERD_CLUSTER_READY_FILE" ]; then
        echo "[entrypoint_script] Skip joining cluster, already joined."
        # Mark ejabberd as ready
        touch "$EJABBERD_READY_FILE"
        return 0
    fi

    if [ "$EJABBERD_CLUSTER_KUBERNETES_DISCOVERY" == "true" ]; then
        local kubernetes_cluster_name="${EJABBERD_KUBERNETES_CLUSTER_NAME:-cluster.local}"
        local kubernetes_namespace="${EJABBERD_KUBERNETES_NAMESPACE:-`cat /var/run/secrets/kubernetes.io/serviceaccount/namespace`}"
        local kubernetes_label_selector="${EJABBERD_KUBERNETES_LABEL_SELECTOR:-cluster.local}"
        local kubernetes_subdomain="${EJABBERD_KUBERNETES_SUBDOMAIN:-$(curl --silent -X GET $INSECURE --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt https://kubernetes.default.svc.$kubernetes_cluster_name/api/v1/namespaces/$kubernetes_namespace/pods?labelSelector=$kubernetes_label_selector -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" | jq '.items[0].spec.subdomain' | sed 's/"//g' | tr '\n' '\0')}"

        if [ "$kubernetes_subdomain" == "null" ]; then
            EJABBERD_KUBERNETES_HOSTNAME="$EJABBERD_KUBERNETES_POD_NAME.$kubernetes_namespace.svc.$kubernetes_cluster_name"
        else
            EJABBERD_KUBERNETES_HOSTNAME="$EJABBERD_KUBERNETES_POD_NAME.$kubernetes_subdomain.$kubernetes_namespace.svc.$kubernetes_cluster_name"
        fi

        local join_cluster_result=0
        local pod_names="$(curl --silent -X GET "$INSECURE" --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt "https://kubernetes.default.svc.$kubernetes_cluster_name/api/v1/namespaces/$kubernetes_namespace/pods?labelSelector=$kubernetes_label_selector" -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" | jq '.items[].spec.hostname' | sed 's/"//g' | tr '\n' ' ')"

        for pod_name in $pod_names;
        do
            if [ "$pod_name" == "null" ]; then
                echo "[entrypoint_script] No Kubernetes pods were found. This might happen because the current pod is the first pod."
                echo "[entrypoint_script] Skip joining cluster."
                touch "$EJABBERD_CLUSTER_READY_FILE"
                # Mark ejabberd as ready
                touch "$EJABBERD_READY_FILE"
                break
            fi
            if [ "$pod_name" != "$EJABBERD_KUBERNETES_POD_NAME" ]; then
                local node_to_join="ejabberd@$pod_name.$kubernetes_subdomain.$kubernetes_namespace.svc.$kubernetes_cluster_name"
                echo "[entrypoint_script] Will join cluster node: '$node_to_join'"

                local response="$($HOME/bin/ejabberdctl ping "$node_to_join")"
                while [ $response != "pong" ]; do
                    echo "[entrypoint_script] Waiting for node: $node_to_join..."
                    sleep 5
                    response="$($HOME/bin/ejabberdctl ping "$node_to_join")"
                done

                $HOME/bin/ejabberdctl join_cluster "$node_to_join"
                join_cluster_result="$?"

                break
            else
                echo "[entrypoint_script] Skip joining current node: $pod_name"
            fi
        done

        if [ "$join_cluster_result" -eq 0 ]; then
            echo "[entrypoint_script] ejabberd did join cluster successfully"
            touch "$EJABBERD_CLUSTER_READY_FILE"
            # Mark ejabberd as ready
            touch "$EJABBERD_READY_FILE"
        else
            echo "[entrypoint_script] ejabberd did fail to join cluster"
            exit 2
        fi
    else
        echo "[entrypoint_script] Kubernetes clustering is not enabled"
        # Mark ejabberd as ready
        touch "$EJABBERD_READY_FILE"
    fi
}

## Termination
EJABBERD_PID=0

terminate() {
    local net_interface="$(route | grep '^default' | grep -o '[^ ]*$')"
    local ip_address="$(ip -4 addr show "$net_interface" | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | sed -e "s/^[[:space:]]*//" | head -n 1)"

    if [ "$EJABBERD_PID" -ne 0 ]; then
        # Leave the cluster before terminating
        if [ -n "$EJABBERD_KUBERNETES_HOSTNAME" ]; then
            NODE_NAME_TO_TERMINATE="ejabberd@$EJABBERD_KUBERNETES_HOSTNAME"
        else
            NODE_NAME_TO_TERMINATE="ejabberd@$ip_address"
        fi

        echo "[entrypoint_script] Leaving cluster '$NODE_NAME_TO_TERMINATE'"
        NO_WARNINGS=true $HOME/bin/ejabberdctl leave_cluster "$NODE_NAME_TO_TERMINATE"
        $HOME/bin/ejabberdctl stop > /dev/null
        $HOME/bin/ejabberdctl stopped > /dev/null

        kill -s TERM "$EJABBERD_PID"
        exit 0
    fi
}

trap "terminate" SIGTERM

## Start ejabberd
$HOME/bin/ejabberdctl foreground &
EJABBERD_PID=$!
$HOME/bin/ejabberdctl started
join_cluster
wait "$EJABBERD_PID"
