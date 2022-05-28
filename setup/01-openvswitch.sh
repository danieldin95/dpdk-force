#!/bin/bash

set -ex

DPDK_MEM=1024

bind_device() {
  # dpdk-devbind -b vfio-pci 0000:02:03.0
  dpdk-devbind -s
}

setup_openvswitch() {
  sed -i 's/OVS_USER_ID=.*/OVS_USER_ID="root:hugetlbfs"/g' /etc/sysconfig/openvswitch
  rm -vf /var/run/openvswitch.useropts
  
  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=true
  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=try
  #ovs-vsctl --no-wait set Open_vSwitch . other_config:per-port-memory=true

  #ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-extra="--iova-mode=va"
  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-mem="$DPDK_MEM,0"
  ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-socket-limit="$DPDK_MEM,0"
  ovs-vsctl --no-wait set Open_vSwitch . other_config:pmd-cpu-mask=0x0C
  ovs-vsctl list Open_vSwitch
}

add_bridge() {
  ovs-vsctl --may-exist add-br br-phy -- set bridge br-phy datapath_type=netdev
  #ovs-vsctl --may-exist add-port br-phy dp-0203 -- set Interface dp-0203 type=dpdk options:dpdk-devargs=0000:02:03.0
  #ovs-vsctl --may-exist add-port br-phy dp-0204 -- set Interface dp-0203 type=dpdk options:dpdk-devargs=0000:02:04.0
}

bind_device
setup_openvswitch
add_bridge