#!/bin/sh

ProgramName=${0##*/}

# Global variables #############################################################
wlg_selector=test
wlg_pods=1		# total number of wlg pods to be running and synchronised
wlg_project="centos-stress"
wlg_template=/root/projects/haproxy/stress/stress-pod.json
gotime_bin=/root/projects/haproxy/bin/gotime
gotime_doc_root=/root/projects/haproxy/gotime

# WLG variables
GUN=`hostname`
RUN_TIME=${RUN_TIME:-60}
PBENCH_DIR=${PBENCH_DIR:-${benchmark_run_dir:-/tmp}}
VEGETA_RPS=${VEGETA_RPS:-10}

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
  cat <<EOF 1>&2
Usage: $ProgramName
EOF
}

prepare_gotime_files() {
  local file_targets=${gotime_doc_root}/targets
  local pbench_dir=${benchmark_run_dir:-/tmp}

  mkdir -p ${gotime_doc_root} || die 1 'cannot create gotime document root \`${gotime_doc_root}'
  oc get routes --no-headers --all-namespaces | awk '{print $3}' > ${file_targets} \
    || die 1 'cannot prepare a file with OpenShift routes \`${file_targets}'

#  test "${RUN_TIME}" && echo $RUN_TIME > ${gotime_doc_root}/RUN_TIME	# TODO (to get rid of populate_cluster_with_pods() -> use cluster loader?)
  test "${VEGETA_RPS}" && echo $VEGETA_RPS > ${gotime_doc_root}/vegeta/VEGETA_RPS
  echo ${PBENCH_DIR} > ${gotime_doc_root}/PBENCH_DIR
}

populate_cluster_with_pods() {
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
       -vRUN="vegeta" \
       -vRUN_TIME="${RUN_TIME:-600}" \
       -vIDENTIFIER=$i \
       -f $wlg_template | oc create -f-
    i=$(($i+1))
  done
}

wait_for_pods_running() {
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

  # all required ${wlg_pods} running, "oc rsync /root/.ssh" into them
  for pod_namespace in $(oc get pods --no-headers --all-namespaces --selector=${wlg_selector} | awk '/1\/1/ && /Running/ {printf "%s|%s\n", $2, $1}')
  do
    pod=${pod_namespace%%|*}
    namespace=${pod_namespace##*|}
    oc rsync /root/.ssh ${pod}:/root/ -n ${namespace} 
  done
}

sync_pods() {
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
  sync_pods			# synchronise the pods to start tests at the same time
#  wait_for_pods_shutdown	# wait for all the pods leave the Running state
}

main
