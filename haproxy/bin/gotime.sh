#!/bin/sh

ProgramName=${0##*/}

# Global variables #############################################################
wlg_selector=test
wlg_pods=1		# total number of wlg pods/clients to be running and synchronised
wlg_pods_start=Y	# Y: start WLG pods
wlg_project="centos-stress"
wlg_template=/root/projects/haproxy/stress/stress-pod.json
gotime_bin=/root/projects/haproxy/bin/gotime
gotime_doc_root=/root/projects/haproxy/gotime
targets=routes	# routes|services|endpoints

# WLG variables
GUN=`hostname`
RUN_TIME=${RUN_TIME:-60}
PBENCH_DIR=${PBENCH_DIR:-${benchmark_run_dir:-/tmp}}
RPS=${RPS:-10}		# legacy, for vegeta, wrk2
DELAY=${DELAY:-1000}	# for wrk

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

usage() {
  local err="$1"

  cat <<EOF 1>&2
Usage: $ProgramName

Options:
  --help|-h      this help
  -c #           number of clients [$wlg_pods]
  -p bool        start WLG pods (Y|N) [$wlg_pods_start]
  -t target      target=routes|services|endpoints [$targets}
EOF

  test "$err" && exit $err
}

prepare_gotime_files() {
  local file_targets=${gotime_doc_root}/targets
  local pbench_dir=${benchmark_run_dir:-/tmp}

  mkdir -p ${gotime_doc_root} || die 1 'cannot create gotime document root \`${gotime_doc_root}'
  if test $targets = routes ; then
    oc get routes --no-headers --all-namespaces | awk '{print $3}' > ${file_targets} \
      || die 1 'cannot prepare a file with OpenShift $targets \`${file_targets}'
  fi

  # TODO: ugly hack
  if test $targets = services ; then
    oc get svc --all-namespaces --no-headers | \
    awk '/nginx-/ {printf "%s\n", $3}' > ${file_targets} \
      || die 1 'cannot prepare a file with OpenShift $targets \`${file_targets}'
  fi

  # TODO: ugly hack
  if test $targets = endpoints ; then 
    rm -f ${file_targets}
    for i in {1..30}
    do
      oc get ep -n nginx-$i -o yaml | \
        grep -- '- ip' | sed 's|    - ip: ||' >> ${file_targets} \
          || die 1 'cannot prepare a file with OpenShift $targets \`${file_targets}'
    done
  fi

#  test "${RUN_TIME}" && echo $RUN_TIME > ${gotime_doc_root}/RUN_TIME	# TODO (to get rid of populate_cluster_with_pods() -> use cluster loader?)
  test "${RPS}" && echo $RPS > ${gotime_doc_root}/vegeta/VEGETA_RPS	# legacy tools
  test "${RPS}" && echo $RPS > ${gotime_doc_root}/wrk2/WRK_RPS		# legacy tools
  test "${DELAY}" && echo $DELAY > ${gotime_doc_root}/wrk/WRK_DELAY
  test "${WRK_THREADS}" && echo $WRK_THREADS > ${gotime_doc_root}/wrk/WRK_THREADS
  echo ${PBENCH_DIR} > ${gotime_doc_root}/PBENCH_DIR
  export TARGET_HOST=$(tr '\n' ':' < $file_targets)	# JMeter
  export ROUTER_IP=172.31.56.140			# JMeter
}

populate_cluster_with_pods() {
  test "$wlg_pods_start" = Y || return

  if oc project $wlg_project 2>&1 ; then
    # $wlg_project exists, recycle it
    for res in pod rc dc bc ; do
      oc delete $res --all -n $wlg_project 2>&1
    done
  else
    # $wlg_project doesn't exist
    oc new-project $wlg_project
  fi
  local i=0
  while test $i -lt $wlg_pods
  do
    oc process \
       -vGUN="${GUN}" \
       -vRUN="${RUN}" \
       -vRUN_TIME="${RUN_TIME:-600}" \
       -vIDENTIFIER=$i \
       -vTARGET_HOST="${TARGET_HOST}" \
       -vROUTER_IP="${ROUTER_IP}" \
       -f $wlg_template | oc create -f-
    i=$(($i+1))
  done
}

wait_for_pods_running() {
  test "$wlg_pods_start" = Y || return

  # all required ${wlg_pods} running and have /root/.ssh from current machine
  # wait for them to terminate
  while true
  do
    pods_running=$(oc get pods --no-headers --all-namespaces --selector=${wlg_selector} | grep 1/1 | grep Running | wc -l)
    test $pods_running -eq $wlg_pods && {
      break
    }
    fail "$pods_running WLG pods running, expecting $wlg_pods"
    sleep 5
  done
}

rsync_root_ssh_to_pods() {
  local pod pod_namespace pods_running namespace

  test "$wlg_pods_start" = Y || return

  # all required ${wlg_pods} running, "oc rsync /root/.ssh" into them
  for pod_namespace in $(oc get pods --no-headers --all-namespaces --selector=${wlg_selector} | awk '/1\/1/ && /Running/ {printf "%s|%s\n", $2, $1}')
  do
    pod=${pod_namespace%%|*}
    namespace=${pod_namespace##*|}
    oc rsync /root/.ssh ${pod}:/root/ -n ${namespace} 
  done
}

sync_clients() {
#  $gotime_bin -v -n $wlg_pods -r ${gotime_doc_root}  -- /bin/sh -c 'n=$(oc get pods --no-headers --all-namespaces --selector=${wlg_selector} | grep Running | grep 1/1 | wc -l) ; test "$n" -eq '$wlg_pods
  $gotime_bin -v -n $wlg_pods -r ${gotime_doc_root}  -- true
}

# all required ${pods} running and have /root/.ssh from current machine
wait_for_pods_shutdown() {
  local pods_running

  # wait for them to terminate
  while true
  do
    pods_running=$(oc get pods --no-headers --all-namespaces --selector=${wlg_selector} | grep Running | wc -l)
    test $pods_running -eq 0 && break
    fail "$pods_running WLG pods running, expecting 0"
    sleep 5
  done
}

main() {
  prepare_gotime_files		# prepare a file with OpenShift routes and other variables
  populate_cluster_with_pods	# let cluster-loader.py do its job and populate cluster with WLG pods
  wait_for_pods_running		# wait for all the WLG pods enter the Running state
  rsync_root_ssh_to_pods	# copy over /root/.ssh to the WLG pods
  sync_clients			# synchronise the pods to start tests at the same time
#  wait_for_pods_shutdown	# wait for all the pods leave the Running state
}

# option parsing
while true
do
  case "$1" in
    --[Hh][Ee][Ll][Pp]|-h) usage 0
    ;;

    -c) if test "$2" ; then
          wlg_pods="$2"
        else
          die 1 "missing # of clients"
        fi
        shift
    ;;

    -p) wlg_pods_start="$2"
        case $wlg_pods_start in
          Y|N) wlg_pods_start=$2
          ;;

          *) test "$2" && die 1 "expected boolean Y|N, received \`$2'"
          ;;
        esac
        shift
    ;;

    -t) targets="$2"
        case $targets in
          routes|services|endpoints) targets=$2
          ;;

          *) die 1 "invalid target \`$2'"
          ;;
        esac
        shift
    ;;

    -*) die 1 "$ProgramName: invalid option \`$1'"
    ;;

    *)  break
    ;;
  esac
  shift
done

main $@
