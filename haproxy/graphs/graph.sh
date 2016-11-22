#!/bin/sh

### binaries ####################################################################
pctl_bin=pctl

### functions ###################################################################
graph_total_latency_pctl() {
  local results="$1"
  local dir_out="$2"
  local graph_conf=$(realpath total_latency_pctl.conf)
  local graph_data_in_latency=$dir_out/total_latency_pctl.txt
  local graph_image_out=$dir_out/total_latency_pctl.png
 
  mkdir -p $dir_out
  rm -f $graph_data_in_latency
  for err in $(awk -F, '{print $2}' $results | sort -u)
  do
    printf "%s\t" $err >> $graph_data_in_latency
    awk -F, "{if(\$2 == $err) {print (\$3/1000000)}}" < $results  | \
      $pctl_bin >> $graph_data_in_latency
  done
  
  gnuplot \
    -e "data_in='$graph_data_in_latency'" \
    -e "graph_out='$graph_image_out'" \
    $graph_conf
}

graph_time_bytes_hits_latency() {
  local results="$1"
  local dir_out="$2"
  local graph_data_in=$dir_out/time_bhl.txt

  local graph_bytes_conf=$(realpath time_bytes.conf)
  local graph_image_out_bytes=$dir_out/time_bytes.png

  local graph_hits_conf=$(realpath time_hits.conf)
  local graph_image_out_hits=$dir_out/time_hits.png

  local graph_latency_conf=$(realpath time_latency.conf)
  local graph_image_out_latency=$dir_out/time_latency.png

  mkdir -p $dir_out
  cat $results | LC_ALL=C sort -t, -n -k1 | \
  awk '
{
  time=int($1/1000000000)
  latency += ($3/1000000)
  bytes_out += $4
  bytes_in += $5
  hits += 1
  if(time_prev == 0) {
    time_prev=time	# we are just beginning
  }
  if(time_prev != time) {
    printf "%ld\t%ld\t%ld\t%ld\t%lf\n", time_prev, bytes_out, bytes_in, hits, (latency/hits)
    time_prev=0
    bytes_out=0
    bytes_in=0
    hits=0
    latency=0
  }
} 
BEGIN {
  FS=","
  time_prev=0
  bytes_out=0
  bytes_in=0
  hits=0
  latency=0
}
' > $graph_data_in

  gnuplot \
    -e "data_in='$graph_data_in'" \
    -e "graph_out='$graph_image_out_bytes'" \
    $graph_bytes_conf

  gnuplot \
    -e "data_in='$graph_data_in'" \
    -e "graph_out='$graph_image_out_hits'" \
    $graph_hits_conf

  gnuplot \
    -e "data_in='$graph_data_in'" \
    -e "graph_out='$graph_image_out_latency'" \
    $graph_latency_conf
}

main() {
  local results="$1"
  local dir_out="$2"

  graph_total_latency_pctl "$results" "$dir_out"
  graph_time_bytes_hits_latency "$results" "$dir_out"
}

for r in $(find /var/lib/pbench-agent/ -name results-0.csv)
do
  results=$r
  dir_out=$(dirname $results)/client/${IDENTIFIER:-0}
  main "$results" "$dir_out"
done
