#!/bin/bash

exec 9</root/pbench/nodes.dat

while read -u9 host
do
  test ${host:0:1} = "#" && continue

  echo $host
  ssh root@$host 'pbench-clear-results'
done
