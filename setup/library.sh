# Copyright 2021 EasyStack, Inc.

function arm_s2500() {
  if ! lscpu | grep -i ^architecture | grep -i aarch64; then
    return 1
  fi
  local sockets=$(lscpu | grep -i '^socket(s):' | awk '{print $2}')
  local nodes=$(lscpu | grep -i '^numa node(s):' | awk '{print $3}')
  if [ "$nodes"x == "$sockets"x ]; then
    return 1
  fi
  return 0
}

function is_network_node() {
  local node=$(hostname -s)
  if kubectl get node ${node} --show-labels | grep openstack-network > /dev/null; then
    return 0
  fi
  return 1
}

function is_compute_node() {
  local node=$(hostname -s)
  if kubectl get node ${node} --show-labels | grep openstack-compute > /dev/null; then
    return 0
  fi
  return 1
}

function ecp_602() {
  local image=$(crictl ps -a | grep ' ovn-controller ' | awk '{print $2}')
  if crictl images | grep image | grep '6.0.2'; then
    return 0
  fi
  return 1
}

function ecp_611() {
  local image=$(crictl ps -a | grep ' ovn-controller ' | awk '{print $2}')
  if crictl images | grep image | grep '6.1.1'; then
    return 0
  fi
  return 1
}

function iommu_enabled() {
  find /sys/class/iommu | grep -i dmar
}

function mellanox_4_5() {
  local pci=$1
  if lspci -s $pci | grep -i -e ConnectX-4 -i -e ConnectX-5; then
    return 0
  fi
  return 1
}
