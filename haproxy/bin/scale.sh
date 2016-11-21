#!/bin/sh

template=../apps/nginx/nginx.json
project_basename=nginx-
projects=10	# 10, 20, 30, 60, 180
templates=10	# templates per project
replicas=6

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
  local project

  for p in $(seq 1 $projects)
  do
    project=${project_basename}$p
    i=1
    while test $i -le $templates
    do
      oc scale rc ${project_basename}$i -n ${project_basename}$p --replicas=${replicas}
      i=$((i+1))
      
      max_not_running 10
    done
  done
}

main

