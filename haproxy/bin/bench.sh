#!/bin/sh -x

ProgramName=${0##*/}

openshift_scalability_dir=/root/svt/openshift_scalability
cluster_loader_cfg_template=/root/projects/haproxy/config/stress.yaml
cluster_loader_cfg=/tmp/stress.yaml.$$.${RANDOM}

nbproc=1			# number of HAProxy processes
use_pbench=y
WRK_TARGETS="nginx"  		# nginx|nginx-tls-edge|nginx-tls-passthrough|nginx-tls-reencrypt
WRK_DELAY="100"			# maximum delay between client requests in ms
WRK_CONNS_PER_THREAD=1		# how many connections per worker thread
WRK_KEEPALIVE="y"		# http-keepalive [yn]
WRK_TLS_SESSION_REUSE="y"	# TLS session reuse [yn]
URL_PATH="/1024.html"		# URL path
RUN_TIME=120			# benchmark run-time in seconds

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

# TODO: this is an ugly hack and a reason we need a way to pass environment variables to cluster-loader
replace_cl_env() {
  local var="$1"
  local val="$2"

  sed -i "s|^\(\s*-\s*${var}\s*\):.*|\1: \"$val\"|" ${cluster_loader_cfg}
}

# Main #########################################################################
pushd $openshift_scalability_dir
for WRK_TARGETS in nginx nginx-tls-edge nginx-tls-passthrough nginx-tls-reencrypt
do
  routes=$(oc get routes --all-namespaces | awk '{print $3}' | grep "${WRK_TARGETS}" | wc -l)
  routes_f=$(printf "%04d" $routes)

  test "${routes:-0}" -eq 0 && {
    warn "no routes to test against"
    continue
  }
  for WRK_DELAY in 0 ; do
#  for WRK_DELAY in 10 20 50 100 200 500 1000 ; do
    delay_f=$(printf "%04d" $WRK_DELAY)

    router_restarts_start=$(router_restarts)

    for WRK_CONNS_PER_THREAD in 1 10 20 30 40 ; do
      conns_per_thread_f=$(printf "%03d" $WRK_CONNS_PER_THREAD)
      for WRK_KEEPALIVE in y n ; do
        for WRK_TLS_SESSION_REUSE in y n ; do
          for bytes in 1024 4096 16384 65536 ; do
            for nginx_echo in y n ; do
              URL_PATH="/$bytes"
              if test "$nginx_echo" = n ; then
                URL_PATH="${URL_PATH}.html"
              fi
              cp $cluster_loader_cfg_template $cluster_loader_cfg
              replace_cl_env RUN_TIME "$RUN_TIME"
              replace_cl_env WRK_DELAY "$WRK_DELAY"
              replace_cl_env WRK_TARGETS "$WRK_TARGETS"
              replace_cl_env WRK_CONNS_PER_THREAD "$WRK_CONNS_PER_THREAD"
              replace_cl_env WRK_KEEPALIVE "$WRK_KEEPALIVE"
              replace_cl_env WRK_TLS_SESSION_REUSE "$WRK_TLS_SESSION_REUSE"
              replace_cl_env URL_PATH "$URL_PATH"
              cat $cluster_loader_cfg

              if test "$use_pbench" = y ; then
                pbench-user-benchmark -C haproxy-${nbproc}p-${WRK_TARGETS}-${routes_f}r-${conns_per_thread_f}cpt-${bytes}B-${nginx_echo}E-${delay_f}d_ms-${WRK_KEEPALIVE}ka-${WRK_TLS_SESSION_REUSE}tlsru-${RUN_TIME}s -- \
                  ./cluster-loader.py -vaf ${cluster_loader_cfg}
              else
                  ./cluster-loader.py -vaf ${cluster_loader_cfg}
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
        done
      done
    done
  done
done
popd
