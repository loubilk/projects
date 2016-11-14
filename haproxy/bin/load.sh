#!/bin/sh

cluster_loader_dir=/root/svt/openshift_scalability
routes=$(printf "%04d" $(oc get routes --all-namespaces | grep hello-openshift | wc -l))
template=apps/hello-openshift/hello-openshift.json
project_basename=hello-openshift-
projects=8
templates=100

max_not_running() {
  local max_not_running="${1:-10}"
  local not_running

  while true
  do
    not_running=$(oc get pods --all-namespaces --no-headers | grep -v Running | wc -l)
    test "$not_running" -le "$max_not_running" && break
    echo "$not_running pods not running"
    sleep 1
  done
}

main() {
  for p in $(seq 1 $projects)
  do
    oc new-project ${project_basename}$p
    i=1
    while test $i -le $templates
    do
      oc process -vIDENTIFIER=$i -vREPLICAS=1 -f $template | \
        oc create -f-
      i=$((i+1))
      
      max_not_running 10
    done
  done
}

main
