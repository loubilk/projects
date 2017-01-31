#!/bin/sh

ProgramName=${0##*/}

app=nginx	# nginx|hello|cakephp|...
routes=$(oc get routes --all-namespaces | grep ${app} | wc -l)
gotime_sh=/root/projects/haproxy/bin/gotime.sh
ppr=1			# pods per route (replicas)
use_pbench=Y
wlg_pods=1
wlg_pods_start=Y
export RUN_TIME=120	# benchmark run-time in seconds
export RUN=wrk		# vegeta|wrk|wrk2
export DELAY		# maximum delay between client requests in ms
export WRK_THREADS=${routes}

# Functions ####################################################################
fail() {
  echo $@ >&2
}

warn() {
  fail "$ProgramName: $@"
}

die() {
  local err=$1
  shift
  fail "$ProgramName: $@"
  exit $err
}

router_restarts() {
  oc get pods -n default | awk '/^router-/ {print $4}'
}

# Main #########################################################################
for DELAY in 0 ; do
#  for target in routes services endpoints ; do
  for target in routes ; do
#  for target in services ; do
#  for target in endpoints ; do
    delay_f=$(printf "%04d" $DELAY)
    routes_f=$(printf "%04d" $routes)
    router_restarts_start=$(router_restarts)

    if test "$target" != routes && test "$wlg_pods_start" = Y  ; then
      die 1 "Testing anything else but routes from WLG pods is not supported."
    fi

    if test "$use_pbench" = Y ; then
      pbench-user-benchmark -C haproxy-${routes_f}r-${ppr}ppr-${delay_f}d_ms-${RUN_TIME}s-${app}-${target}-${RUN} -- \
        $gotime_sh -c ${wlg_pods:-1} -p "${wlg_pods_start:-N}" -t $target
    else
      $gotime_sh -c ${wlg_pods:-1} -p "${wlg_pods_start:-N}" -t $target
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
