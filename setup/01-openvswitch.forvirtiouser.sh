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
  ovs-vsctl --no-wait set Open_vSwitch . other_config:pmd-cpu-mask=0xF0

  /usr/share/openvswitch/scripts/ovs-ctl restart
  ovs-vsctl list Open_vSwitch
}

add_vxlan_pci() {
  local name=""
  local br=br-vxlan
  ovs-vsctl --may-exist add-br $br -- set bridge $br datapath_type=netdev
  ip link set up dev $br
  ip addr add  2.2.2.1/24 dev $br || true

  dpdk-devbind.py --bind=vfio-pci 0000:02:02.0
  dpdk-devbind.py --bind=vfio-pci 0000:02:03.0

  name=Bond1
  ovs-vsctl --if-exist del-port $name
  ovs-vsctl add-bond $br $name eth1 eth2 \
    -- set Port $name lacp=active bond_mode=balance-tcp other_config:lacp-time=fast other_config:lb-output-action=true \
    -- set interface eth1 type=dpdk options:dpdk-devargs=0000:02:02.0 options:n_rxq=2 \
    -- set interface eth2 type=dpdk options:dpdk-devargs=0000:02:03.0 options:n_rxq=2
}


add_vxlan_virtio() {
  local name=""
  local br=br-vxlan
  ovs-vsctl --may-exist add-br $br -- set bridge $br datapath_type=netdev
  ip link set up dev $br
  ip addr add  2.2.2.1/24 dev $br || true

  name=dpdk0
  ovs-vsctl --if-exist del-port $name
  ovs-vsctl add-port $br $name -- set Interface $name type=dpdk options:dpdk-devargs="virtio_user_$name,iface=$name,path=/dev/vhost-net"
}

add_vxlan() {
  local br=br-dpdk
  ovs-vsctl --may-exist add-br $br -- set bridge $br datapath_type=netdev

  local name=dpdk1
  ovs-vsctl --if-exist del-port $name
  ovs-vsctl add-port $br $name -- set Interface $name type=dpdk options:dpdk-devargs="virtio_user_$name,iface=$name,path=/dev/vhost-net"
  name=vx-1
  ovs-vsctl --if-exist del-port $name
  ovs-vsctl add-port $br $name -- set Interface $name type=vxlan options:remote_ip=2.2.2.10
}

setup_openvswitch
add_vxlan
# add_vxlan_virtio
add_vxlan_pci
