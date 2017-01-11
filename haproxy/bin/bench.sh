#!/bin/sh

ProgramName=${0##*/}

app=nginx	# nginx|hello|cakephp|...
routes=$(printf "%04d" $(oc get routes --all-namespaces | grep ${app} | wc -l))
gotime_sh=/root/projects/haproxy/bin/gotime.sh
ppr=20			# pods per route (replicas)
use_pbench=Y
wlg_pods=2
wlg_pods_start=N
export RUN_TIME=600	# benchmark run-time in seconds
export VEGETA_RPS	# client requests per second

router_restarts() {
  oc get pods -n default | awk '/^router-/ {print $4}'
}

#for VEGETA_RPS in 10 60 100 600 1000 2000; do
for VEGETA_RPS in 10000; do
#  for target in routes services endpoints ; do
  for target in endpoints ; do
    rps_f=$(printf "%04d" $VEGETA_RPS)
    router_restarts_start=$(router_restarts)

    if test "$use_pbench" = Y ; then
      pbench-user-benchmark -C haproxy-${routes}r-${ppr}ppr-${rps_f}rps-${RUN_TIME}s-${app}-${target} -- \
        $gotime_sh -c $wlg_pods -p "${wlg_pods_start}" -t $target
    else
      $gotime_sh -c $wlg_pods -p "$wlg_pods_start" -t $target
    fi
    router_restarts_stop=$(router_restarts)
    test $router_restarts_stop -gt $router_restarts_start && {
      echo "Router restarted.  Stopping..." >&2
      exit 0
    }
    echo "sleeping 60"
    sleep 60
  done
done

