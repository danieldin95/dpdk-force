# Copyright 2021 EasyStack, Inc.
#!/bin/bash

set -ex

. $(dirname $0)/functions.sh

function figure_out_memory() {
  local numa_nodes=$(get_numa_node)
  local memory_file="/etc/kubernetes/memory.yml"
  local pod_limit_mem=$(cat "$memory_file" | grep kubepods_memory_lim | awk -F: '{print $2}')
  if [ "$pod_limit_mem"x = x ]; then
    pod_limit_mem=$(cat "$memory_file" | grep compute_reserved_mem | awk -F: '{print $2}')
    if [ "${pod_limit_mem}"x = x ]; then
      echo "WARN: not found pod max memory on file:"$memory_file
      pod_limit_mem=0
    fi
  fi
  if [ $pod_limit_mem -gt $POD_RESERVED_MEM ]; then
    local dpdk_memory=$(( $pod_limit_mem - $POD_RESERVED_MEM ))
    local numa_nodes_count=$(get_numa_count)
    MEM_PER_NUMA=$(( $dpdk_memory / $numa_nodes_count ))
  fi
  for node in $numa_nodes; do
    local memory=0
    if [ -e "$node/hugepages" ]; then
      memory=$MEM_PER_NUMA
    fi
    if [ "$SOCKET_MEM"x == x ]; then
      SOCKET_MEM="$memory"
      SOCKET_LIMIT="0"
    else
      SOCKET_MEM="$SOCKET_MEM,$memory"
      SOCKET_LIMIT="$SOCKET_LIMIT,0"
    fi
  done
}

# Nova reserve first 4/6 cores for system, and DPDK uses latest cpus.
# In x86_64 machine reserve 4 cores per numa, and s2500 reserve 2 cores.

function get_cpu_list() {
  local node_path=$1
  local tail=$2
  find $node_path -name 'cpu[0-9]*' | xargs -i basename {} | sed 's/cpu//g' | sort -n | tail -n $tail
}

function get_cpu_core() {
  local cpu=$1
  cat /sys/devices/system/cpu/cpu$cpu/topology/thread_siblings_list | awk -F , '{print $1}'
}

function figure_out_cpuset() {
  local numa_nodes=$(get_numa_node)
  local tail_cpu=$CPU_PER_NUMA
  for node in $numa_nodes; do
    local cpu_list=$(get_cpu_list $node $tail_cpu);
      for cpu in $cpu_list; do
        local core=$(get_cpu_core $cpu)
        local offset=$(( $core / 64))
        local core_id=$(( $core % 64 ))
        local core_mask=$(( 1 << $core_id ))
        local cpu_mask=${PMD_CPU_MASK[offset]}
        if [ "$cpu_mask"x == ""x ]; then
          cpu_mask=0
        fi
        PMD_CPU_MASK[offset]=$(( $cpu_mask | $core_mask ))
    done
  done
}

function backup_openvswitch() {
  if [ "$DRYRUN"x != "true"x ]; then
    local file=$(date +%y%m%d%H%M)
	mkdir -p $DPDK_DIR
    ovs-vsctl list Open_vSwitch > $DPDK_DIR/backup.$file
    ovs-appctl bond/list >> $DPDK_DIR/backup.$file
    ovs-vsctl show >> $DPDK_DIR/backup.$file
  fi
}

function config_openvswitch() {
  sed -i 's/OVS_USER_ID=.*/OVS_USER_ID="root:hugetlbfs"/g' /etc/sysconfig/openvswitch
  rm -vf /var/run/openvswitch.useropts

  local cpu_mask=""
  for mask in ${PMD_CPU_MASK[@]}; do
    cpu_mask=$( printf "%016X" $mask )$cpu_mask
  done

  #ovs-vsctl --no-wait set Open_vSwitch . other_config:per-port-memory=true
  ovs-vsctl --no-wait set Open_vSwitch . other_config:tx-flush-interval=50
  ovs-vsctl --no-wait set Open_vSwitch . other_config:smc-enable=true
  ovs-vsctl --no-wait set Open_vSwitch . other_config:emc-insert-inv-prob=10
  #ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-extra="--iova-mode=pa"
  ovs-vsctl --no-wait set Open_vSwitch . other_config:pmd-cpu-mask="0x"$cpu_mask
  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-mem="$SOCKET_MEM"
  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-limit="$SOCKET_LIMIT"

  #ovs-vsctl --no-wait set open_vSwitch . other_config:hw-offload=true
  #ovs-vsctl --no-wait set open_vSwitch . other_config:vhost-iommu-support=true
  #ovs-vsctl --no-wait set open_vSwitch . other_config:userspace-tso-enable=true
  ovs-vsctl --no-wait set open_vSwitch . other_config:pmd-auto-lb-load-threshold="80"
  ovs-vsctl --no-wait set open_vSwitch . other_config:pmd-auto-lb-improvement-threshold="50"
  ovs-vsctl --no-wait set open_vSwitch . other_config:pmd-auto-lb-rebal-interval="1"
  ovs-vsctl --no-wait set open_vSwitch . other_config:pmd-auto-lb="true"

  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=try
}

function check_openvswitch() {
  local result=$(ovs-vsctl get Open_vSwitch . dpdk_initialized)
  if [ "$result"x != "true"x ]; then
    systemctl restart openvswitch
    result=$(ovs-vsctl get Open_vSwitch . dpdk_initialized)
  fi
  if [ "$result"x != "true"x ]; then
    echo "ERROR: Enable DPDK for OpenvSwitch failed"
	cat /var/log/openvswitch/ovs-vswitchd.log | grep -i dpdk | tail -n 100
    return 1
  fi
  echo "INFO: Enable DPDK for OpenvSwitch successful"
}

figure_out_memory
figure_out_cpuset

backup_openvswitch
config_openvswitch
check_openvswitch