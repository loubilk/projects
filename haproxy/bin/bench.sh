#!/bin/sh

ProgramName=${0##*/}

routes=$(printf "%04d" $(oc get routes --all-namespaces | grep hello- | wc -l))
gotime_sh=/root/projects/haproxy/bin/gotime.sh
use_pbench=Y
export RUN_TIME=60	# TODO, run time in seconds
export VEGETA_RPS	# client requests per second

#for VEGETA_RPS in 1000 2000 3000 4000; do
for VEGETA_RPS in 3000 ; do
  rps_f=$(printf "%04d" $VEGETA_RPS)

  if test "$use_pbench" = Y ; then
    pbench-user-benchmark -C haproxy-r${routes}-${rps_f}rps-${RUN_TIME}s-hello-openshift -- $gotime_sh
  else
    $gotime_sh
  fi
  echo "sleeping 600"
  sleep 600
done

