#!/bin/sh

router_namespace=default
tool_output_dir=/tmp

haproxy_counters_clear() {
    for router in $(oc get pod --no-headers -n ${router_namespace} | awk '/^router-/ {print $1}') ; do
        cmd="echo 'clear counters all' | socat - UNIX-CONNECT:/var/lib/haproxy/run/haproxy.sock"
        oc exec "${router}" -n ${router_namespace} -- /bin/sh -c "$cmd" &
    done
    wait
}

haproxy_counters_clear
