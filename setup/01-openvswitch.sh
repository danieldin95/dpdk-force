#!/bin/bash

set -ex

DPDK_MEM=$((1024*1))

bind_device() {
  dpdk-devbind.py -b vfio-pci 0000:02:03.0
  dpdk-devbind.py -b vfio-pci 0000:02:04.0
  dpdk-devbind.py -b vfio-pci 0000:02:05.0
  dpdk-devbind.py -b vfio-pci 0000:00:09.0
  dpdk-devbind.py -s
}

setup_openvswitch() {
  sed -i 's/OVS_USER_ID=.*/OVS_USER_ID="root:hugetlbfs"/g' /etc/sysconfig/openvswitch
  rm -vf /var/run/openvswitch.useropts
  
  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=true
  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=try
  #ovs-vsctl --no-wait set Open_vSwitch . other_config:per-port-memory=true

  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-extra="--iova-mode=pa"
  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-mem="$DPDK_MEM,0"
  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-limit="$DPDK_MEM,0"
  ovs-vsctl --no-wait set Open_vSwitch . other_config:pmd-cpu-mask=0xFFFFC
  ovs-vsctl list Open_vSwitch
}

rxq_affinity() {
  port=$1
  rxq_n=$2
  cpu_s=$3

  affinity_args=""
  for i in $(seq 0 $rxq_n); do
    if [ "$i"x == "0"x ]; then
        affinity_args="$i:$(( $i+$cpu_s ))"
    else
       affinity_args="$affinity_args,$i:$(( $i+$cpu_s ))"
    fi
  done
  affinity_args="pmd-rxq-affinity=$affinity_args"
  ovs-vsctl set Interface $port options:n_rxq=$rxq_n other_config:$affinity_args
}

add_bridge() {
  ovs-vsctl --may-exist add-br br-eth6 -- set bridge br-eth6 datapath_type=netdev
  ovs-vsctl --if-exists del-port eth6
  ovs-vsctl --may-exist add-port br-eth6 eth6 -- set Interface eth6 type=dpdk options:dpdk-devargs=0000:00:09.0 options:flow-ctrl-autoneg="true"
  rxq_affinity eth6 20 2
}

bind_device
setup_openvswitch
add_bridge
