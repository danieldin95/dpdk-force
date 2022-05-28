# Copyright 2021 EasyStack, Inc.
#!/bin/bash

# declare -x BRIDGES="br-int br-vxlan br-prv"
# declare -x DRYRUN="true"

set -ex

. $(dirname $0)/functions.sh

echo "Enable DPDK on $BRIDGES"

function check_openvswitch() {
  local result=$(ovs-vsctl get Open_vSwitch . dpdk_initialized)
  if [ "$result"x != "true"x ]; then
    echo "ERROR: No-enable DPDK for OpenvSwitch."
    return 1
  fi
}

function find_port_pci() {
  local port=$1; shift
  local pci=$(get_port_pci $port)
  if [ "$pci"x != x ]; then
    echo $pci
    return
  fi
  local file=$(find $DPDK_DIR -name kernel-$port-[0-9]*)
  local pci=$(echo $file | awk -F "$port-" '{print $2}')
  if [ "$pci"x == x ]; then
    echo "ERROR: $port not-found pci-address"
    return 1
  fi
  echo $pci
}

function device_bind() {
  local bond=$1; shift
  local bond_ports=$(get_bond_ports $bond)
  local port_args=""
  local bond_args=$(get_bond_args $bond)

  for port in $bond_ports; do
    if pci=$(find_port_pci $port); then
      if ! mellanox_4_5 $pci; then
        dpdk-devbind.py -b vfio-pci $pci
      fi
      port_args="""$port_args
-- set Interface $port type=dpdk mtu_request=1600
-- set Interface $port options:dpdk-devargs=$pci options:n_rxq=$CPU_PER_NUMA"""
    fi
    # set Interface $port options:dpdk-lsc-interrupt=true
    if [ -e "$NETROWK_SCRIPTS_DIR/ifcfg-$port" ]; then
      mv $NETROWK_SCRIPTS_DIR/ifcfg-$port $NETROWK_SCRIPTS_DIR/remove.ifcfg-$port
    fi
  done
  ovs-vsctl --if-exists del-port $bond
  ovs-vsctl add-bond br-$bond $bond $bond_ports $bond_args $port_args || {
    ovs-vsctl add-bond br-$bond $bond $bond_ports
    return 1
  }
  DEVICE_BINDS="$DEVICE_BINDS $bond_ports"
}

function write_port_pcis_file() {
  local ports=$@
  if [ "$ports"x == x ]; then
    return
  fi
  for port in $ports; do
    local pci=$(get_port_pci $port)
    if [ "$pci"x != x ]; then
      touch $DPDK_DIR/kernel-$port-$pci
    fi
  done
}

function backup_port_pci() {
  local bonds=$(ovs-vsctl show | grep  'Port Bond' | awk '{print $2}')
  local bond_ports=""
  for bond in $bonds; do
    bond_ports="$bond_ports $(get_bond_ports $bond)"
  done
  [ -e "$DPDK_DIR" ] || mkdir -p $DPDK_DIR
  write_port_pcis_file "$bond_ports"
}

function update_port_bind() {
  [ -e "$DPDK_DIR" ] || mkdir -p $DPDK_DIR
  echo "$@" > $DPDK_DIR/devices
}

function set_bridge_netdev() {
  local br=$1
  ovs-vsctl set Bridge $br datapath_type=netdev
  if [ -e "$NETROWK_SCRIPTS_DIR/ifcfg-$br" ]; then
    ifup $br
  fi
}

function find_bridges_by_bridge() {
  local br=$1; shift
  local ports=$(ovs-vsctl list-ports $br)
  local news=""
  for port in $ports; do
    if echo $port | grep ^$br-- > /dev/null; then
      local peer=$(echo $port | sed "s/$br--//g")
      if ! echo $BRIDGES | grep -w $peer > /dev/null; then
        news="$news $peer"
        BRIDGES="$BRIDGES $peer"
      fi
    fi
  done
  for peer in $news; do
    find_bridges_by_bridge $peer
  done
}

function set_bonds() {
  local bridges=$@
  for br in $bridges; do
    if echo $br | grep br-Bond; then
      local bond=$(echo $br | sed 's/br-//g')
      set_bridge_netdev $br
      device_bind $bond
    fi
  done
}

function set_netdev() {
  local bridges=$@
  for br in $bridges; do
    set_bridge_netdev $br
  done
}

function set_bridges() {
  local ports=$@
  for port in $ports; do
    find_bridges_by_bridge $port
  done

  echo "Try to set DPDK with $BRIDGES"
  if [ "$DRYRUN"x != "true"x ]; then
    set_bonds $BRIDGES
    set_netdev $BRIDGES
  fi
}

if [ "$DRYRUN"x != "true"x ]; then
  check_openvswitch
fi
backup_port_pci
set_bridges $BRIDGES
if [ "$DRYRUN"x != "true"x ]; then
  update_port_bind $DEVICE_BINDS
fi
