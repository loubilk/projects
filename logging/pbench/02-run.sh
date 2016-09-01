#!/bin/bash

ProgramName=${0##*/}

me=$$
pb_res=${1:-'/var/lib/pbench-agent'}
payload_script=/tmp/payload.${me}
payload_log=/tmp/payload.${me}.log
slstress_hosts=/root/nodes.dat
pbench_hosts=/root/pbench/nodes.dat

# ElasticSearch variables
es_admin_cert=/etc/elasticsearch/secret/admin-cert
es_admin_key=/etc/elasticsearch/secret/admin-key
es_url=https://logging-es:9200

define_global_vars()
{
  tmout=${1:-300}
  string_length=${2:-256}
  delay=${3:-1000000}	# delay in microseconds seconds
  limits=${4:-limits}	# syslogd/rsyslogd rate default limits
  pause_secs=300	# pause seconds between test runs
  tag=slstress-${string_length}ll-${delay}w
  testname=10n-${limits}-${string_length}ll-${delay}wait-${tmout}s
  pb_dir=${pb_res}/$testname
  pb_dir_log=${pb_res}/$testname/log
  pb_dir_log_postprocess=${pb_res}/$testname/tools-default/log
}

payload_send_to_host()
{
  local host="$1"

  ssh $host "cat >${payload_script} && \
             chmod 755 ${payload_script} && \
             ${payload_script} >${payload_log} 2>&1"
}

payload_show_logs()
{
  local hosts=${1:-${pbench_hosts}}

  # show the logs from all pbench hosts
  while read -r host 
  do
    test "${host:0:1}" = "#" && continue 
    echo "cat ${payload_log}" | ssh -T $host # &
  done < ${hosts}

  wait
}

get_es_pods()
{
  oc get pods | grep ^logging-es | awk '{print $1}'
}

es_delete_indices()
{
  local log_dir=${pb_dir_log}/${1-es/delete_indices}
  local es_pods=$(get_es_pods)

  echo "Deleting ElasticSearch indices." >&2
  mkdir -p ${log_dir}

  for es_pod in $es_pods
  do
    oc exec $es_pod -- curl -s -k --cert $es_admin_cert --key $es_admin_key --cacert $es_admin_cert \
      -XDELETE "$es_url/*" >> ${log_dir}/${es_pod}.log
  done
}

# https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-optimize.html
# The optimize process basically optimizes the index for faster search operations.
# Also, perform a "flush".
es_optimize()
{
  local log_dir=${pb_dir_log}/${1-es}
  local es_pods=$(get_es_pods)

  echo "Optimizing ElasticSearch index." >&2
  mkdir -p ${log_dir}

  for es_pod in $es_pods
  do
    oc exec $es_pod -- curl -s -k --cert $es_admin_cert --key $es_admin_key --cacert $es_admin_cert \
      -XPOST "$es_url/_refresh" >> ${log_dir}/${es_pod}-refresh.log
    oc exec $es_pod -- curl -s -k --cert $es_admin_cert --key $es_admin_key --cacert $es_admin_cert \
      -XPOST "$es_url/_optimize?only_expunge_deletes=true&flush=true" >> ${log_dir}/${es_pod}-optimize.log
  done
}

es_get_stats()
{
  local log_dir=${pb_dir_log}/${1-es}
  local es_pods=$(get_es_pods)

  echo "Saving ElasticSearch stats." >&2
  mkdir -p ${log_dir}

  for es_pod in $es_pods
  do
    oc exec $es_pod -- curl -s -k --cert $es_admin_cert --key $es_admin_key --cacert $es_admin_cert \
      $es_url/_stats >> ${log_dir}/${es_pod}.log
  done
}

es_logs()
{ 
  local log_dir=${pb_dir_log}/${1-es}
  local es_pods=$(get_es_pods)

  echo "Saving ElasticSearch logs." >&2
  mkdir -p ${log_dir}

  for es_pod in $es_pods
  do
    mkdir -p ${log_dir}/${es_pod}
    exec 8<<_EOF_
_cluster/health?pretty		_cluster_health
_cluster/state?pretty		_cluster_state
_cluster/pending_tasks?pretty	_cluster_pending_tasks
_nodes?pretty			_nodes
_nodes/stats?pretty		_nodes_stats
_cat/allocation			_cat_allocation
_cat/health			_cat_health
_cat/nodes/stats		_cat_nodes_stats
_cat/plugins			_cat_plugins
_cat/recovery			_cat_recovery
_EOF_
#_cat/indices?v	# doesn't work

    while read -u8 -r api save rest
    do
      echo "# $es_url/$api:" >> ${log_dir}/${es_pod}/${save}.log
      oc exec $es_pod -- curl -s -k --cert $es_admin_cert --key $es_admin_key --cacert $es_admin_cert \
        $es_url/$api >> ${log_dir}/${es_pod}/${save}.log
    done
  done
}

system_logs() {
  local log_dir=${pb_dir_log}/${1-system}

  echo "Saving System logs." >&2
  mkdir -p ${log_dir}

  grep "journal: Suppressed" /var/log/messages >> ${log_dir}/rate-limiting.log
  grep "messages lost due to rate-limiting" /var/log/messages >> ${log_dir}/rate-limiting.log
}

oc_logs()
{
  local log_dir=${pb_dir_log}/${1-oc}

  echo "Saving OpenShift logs." >&2
  mkdir -p ${log_dir}

  oc get nodes -o wide > ${log_dir}/oc_get_nodes.log
  oc get pods -o wide > ${log_dir}/oc_get_pods.log

  for p in $(oc get pods | tail -n+2 | awk '{print $1}')
  do
    local log_dir_pod=${log_dir}/pods
    mkdir -p ${log_dir_pod}
    oc logs $p > ${log_dir_pod}/oc_logs-${p}.log
    oc describe pod $p > ${log_dir_pod}/oc_describe-${p}.log
  done
}

pb_move_logs()
{ 
  local pb_dir_log="$1"
  local pb_dir_log_postprocess="$2"

  while read -r host 
  do
    test "${host:0:1}" = "#" && continue 
    echo $host
    (payload_send_to_host $host <<EOF
echo "@\$HOSTNAME"
mv "${pb_dir_log}" "${pb_dir_log_postprocess}"
EOF
    ) &
  done < ${pbench_hosts}

  wait
}

slstress_start()
{
  while read -r host 
  do
    test "${host:0:1}" = "#" && continue 
    echo $host
    (payload_send_to_host $host <<EOF
# Show where am I.
echo "@\$HOSTNAME"
# Variables
tmout=${1:-300}
string_length=${2:-1024}
delay=${3:-1000000}
tag=${4:-slstress}
pb_dir_log=${5:-/var/lib/pbench-agent/$tag/log}
slstress_bin=/root/slstress

# Payload
#scp -rp ip-172-31-57-206:/root/svt/logging_metrics_performance/enterprise_logging/test/slstress/slstress /root/slstress
test -x \$slstress_bin || {
  curl -s https://raw.githubusercontent.com/jmencak/perf-tools/master/bin/x86-64/slstress > \$slstress_bin || {
    echo "Unable to fetch slstress client." >&2
    exit 1
  }
  chmod 755 \${slstress_bin}
}
mkdir -p \${pb_dir_log}
(date "+%Y-%m-%d %H:%M:%S" ; df -h; echo) >> \${pb_dir_log}/df.log
timeout \${tmout} /root/slstress -t \${tag} -l \${string_length} -w \${delay} >> \${pb_dir_log}/slstress.log
(date "+%Y-%m-%d %H:%M:%S" ; df -h; echo) >> \${pb_dir_log}/df.log
EOF
  ) &
  done < ${slstress_hosts}

  wait
}

slstress_run()
{
  slstress_start "$@"
  payload_show_logs ${slstress_hosts}
}

main()
{
  system_logs ""
  oc_logs "oc/pre_test"
  es_logs "es/pre_test"
  es_delete_indices "es/delete_indices"
  es_get_stats "es/stats/pre_test"

  echo "Starting pbench tools." >&2
  pbench-start-tools -d ${pb_dir}

  echo "Starting slstress." >&2
  slstress_run "${tmout}" "${string_length}" "${delay}" "${tag}" "${pb_dir_log}"

  es_get_stats "es/stats/post_test"
  es_optimize "es/optimize"
  es_get_stats "es/stats/post_optimize"
  system_logs ""
  oc_logs "oc/post_test"
  es_logs "es/post_test"

  echo "Stopping pbench tools." >&2
  pbench-stop-tools -d ${pb_dir}

  pb_move_logs "${pb_dir_log}" "${pb_dir_log_postprocess}"
  payload_show_logs
  pbench-postprocess-tools -d ${pb_dir}
}

for line_length in 256 512 1024 2048
do
  echo "line length: $line_length"
  for delay in 1000000 100000 10000 1000 100 0
  do
    echo "delay: $delay"
    define_global_vars 300 $line_length $delay no_limits
    main
    echo "Sleeping ${pause_secs}s"
    sleep ${pause_secs}
  done
done
