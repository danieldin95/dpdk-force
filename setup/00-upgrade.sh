# Copyright 2021 EasyStack, Inc.
#!/bin/bash

set -ex

. $(dirname $0)/functions.sh

function load_kernel_module() {
  cat > /etc/modules-load.d/vfio-pci.conf <<EOF
vfio-pci
EOF
  if iommu_enabled; then
    cat > /etc/modprobe.d/vfio.conf <<EOF
options vfio enable_unsafe_noiommu_mode=0
EOF
  else
    cat > /etc/modprobe.d/vfio.conf <<EOF
options vfio enable_unsafe_noiommu_mode=1
EOF
  fi
  if lsmod | grep -w vfio; then
    rmmod vfio-pci
    rmmod vfio_iommu_type1
    rmmod vfio
  fi
  if lspci | grep -i Mellanox; then
    modprobe -a ib_uverbs mlx5_core mlx5_ib
  fi
  modprobe vfio-pci
  cat /sys/module/vfio/parameters/enable_unsafe_noiommu_mode
}

function install_system_service() {
  cp ./bin/dpdk-binds /usr/bin
  chmod +x /usr/bin/dpdk-binds
  cp ./service/dpdk-binds.service /usr/lib/systemd/system
  systemctl enable dpdk-binds
  systemctl enable openvswitch
}

install_system_service
load_kernel_module
