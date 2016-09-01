#!/bin/bash

exec 9</root/pbench/nodes.dat
hostname=$(hostname)
tools="iostat mpstat pidstat proc-interrupts proc-vmstat sar turbostat"
pbench_agent_dir=/var/lib/pbench-agent

# deal with local host
rm -rf ${pbench_agent_dir}
pbench-register-tool-set --interval=3
for tool in $tools
do
  pbench-register-tool --name=$tool -- --interval=3
done

# deal with remote hosts
while read -u9 -r host
do
  test "${host:0:1}" = "#" && continue
  test "${host}" = "${hostname}" && continue	# current host already registered locally
  echo "rm -rf ${pbench_agent_dir}" | ssh -T ${host}

  pbench-register-tool-set --remote=$host --interval=3
  for tool in $tools
  do
    pbench-register-tool --name=$tool --remote=$host -- --interval=3
  done
done

#pbench-cleanup		# does cleanup (/var/lib/pbench-agent), but only on local node!
#pbench-clear-tools	# removes registered tools, even on remote hosts if "remote@<box>" is in /var/lib/pbench-agent/tools-default/
