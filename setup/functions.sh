# Copyright 2021 EasyStack, Inc.

TOP_DIR=$(dirname $0)

. $TOP_DIR/library.sh

### BEGIN: THE FOLLOWING IS GLOBAL VARIABLES ###
DRYRUN=$DRYRUN
ARCH="x86_64"

# Memory
MEM_TOTAL=""
MEM_PER_NUMA=$(( 1024 * 8 ))         # x86 8G, s2500 4G.
if arm_s2500; then
  MEM_PER_NUMA=$(( 1024 * 4 ))
fi
SYSTEM_RESERVED_MEM=$(( 1024 * 12 )) # 4 * 3G
POD_RESERVED_MEM=$(( 1024 * 10 ))    # this defult is 10G
OSD_RESERVED_MEM=0                   # 4G * nodes.
DPDK_RESERVED_MEM=0

# OVS DPDK
POD_RESERVED_MEM=$(( 1024 * 10 ))    # this defult is 10G.
SOCKET_MEM=""
SOCKET_LIMIT=""
CPU_PER_NUMA=$CPU_PER_NUMA           # x86 -4:, s2500 -2:.
if [ "$CPU_PER_NUMA"x == ""x ]; then
  if is_compute_node; then
    CPU_PER_NUMA=4
    if arm_s2500; then
      CPU_PER_NUMA=2
    fi
  else
    CPU_PER_NUMA=8
  fi
fi
PMD_CPU_MASK=0

# Device binds
DPDK_DIR="/etc/dpdk"
NETROWK_SCRIPTS_DIR="/etc/sysconfig/network-scripts"
DEVICE_BINDS=""
# Network node:
#   br-ex -> bond1
#   br-vxlan -> bond2
#   br-storage -> bond3
# Baremetal node:
#   br-vxlan -> bond1
#   br-prv -> bond2
if [ "$BRIDGES"x == ""x ] ; then
  BRIDGES="br-int br-vxlan br-prv br-ex"
fi

### END: THE FOLLOWING IS GLOBAL VARIABLES ###

### BEGIN: THE FOLLOWING IS FUNCTIONS ###
function get_bond_ports() {
  local bond=$1
  local ports=$(ovs-vsctl get port $bond interfaces | sed -e 's/\[\|\]\|,//g')
  for port in $ports; do
    ovs-vsctl get interface $port name
  done
}

function get_bond_args() {
  local args=""
  local bond=$1
  local lacp=$(ovs-vsctl get port $bond lacp)
  local mode=$(ovs-vsctl get port $bond bond_mode)
  if [ "$lacp"x == "active"x ]; then
    args="""$args
-- set port $bond bond_mode=$mode
-- set port $bond lacp=active
-- set port $bond other_config:lacp-fallback-ab=true"""
  fi
  echo $args
}

function get_port_pci() {
  local port=$1
  ethtool -i $port | grep bus-info | sed 's/bus-info: //g'
}

function get_numa_node() {
  local path="/sys/devices/system/node"
  find $path -name 'node[0-9]*' | xargs -i basename {} | sed 's/node//g' | sort -n | xargs -i echo "$path/node"{}
}

function get_numa_count() {
  find /sys/devices/system/node/ -name 'node[0-9]*' | wc -l
}

function get_socket_count() {
  lscpu | grep -i ^socket | awk '{print $2}'
}

function get_osd_count() {
  crictl pods | grep -v -i notready | grep ceph-osd-[0-9] | wc -l
}

HUGEPAGESZ=2 # MiB

function max_hugepages() {
  local page=$(find /sys/kernel/mm/hugepages -name 'hugepages-*' | tail -n 1)
  local size=$(basename $page| sed 's/hugepages-*//g' | sed 's/kB//g')
  if [ "$size"x != ""x ]; then
    HUGEPAGESZ=$(( $size / 1024 ))
  fi
}

max_hugepages
### END: THE FOLLOWING IS FUNCTIONS ###