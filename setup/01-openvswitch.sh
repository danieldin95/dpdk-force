#!/bin/bash

set -ex

DPDK_MEM=$((1024*1))

setup_openvswitch() {
  if [ -e /etc/sysconfig/openvswitch ]; then
    sed -i 's/OVS_USER_ID=.*/OVS_USER_ID="root:hugetlbfs"/g' /etc/sysconfig/openvswitch
  fi
  rm -vf /var/run/openvswitch.useropts
  
  pidof grep ovs-vswitchd || /usr/share/openvswitch/scripts/ovs-ctl start
  
  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=true
  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=try
  # ovs-vsctl --no-wait set Open_vSwitch . other_config:per-port-memory=true

  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-extra="--iova-mode=pa"
  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-mem="$DPDK_MEM,0"
  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-limit="$DPDK_MEM,0"
  ovs-vsctl --no-wait set Open_vSwitch . other_config:pmd-cpu-mask=0xFFFFC

  /usr/share/openvswitch/scripts/ovs-ctl restart
  ovs-vsctl list Open_vSwitch
}

set_affinity() {
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
  dpdk-devbind.py -b vfio-pci 0000:02:00.0
  dpdk-devbind.py -s
  ovs-vsctl --may-exist add-br br-eth2 -- set bridge br-eth2 datapath_type=netdev
  ovs-vsctl --if-exists del-port eth2
  ovs-vsctl --may-exist add-port br-eth2 eth2 -- set Interface eth2 type=dpdk options:dpdk-devargs=0000:00:02.0 options:flow-ctrl-autoneg="true"
  # set_affinity eth2 20 2
}

setup_openvswitch
add_bridge
