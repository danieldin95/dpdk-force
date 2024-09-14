#!/bin/bash

set -ex


HUGEPAGES=$((1024*1))

setup_hugepages() {
  echo "vm.nr_hugepages=$HUGEPAGES" > /etc/sysctl.d/hugepages.conf
  sysctl -p /etc/sysctl.d/hugepages.conf 
  cat /proc/meminfo | grep HugePages_
}

setup_modules() {
  cat > /etc/modules-load.d/vfio-pci.conf <<EOF
vfio-pci
EOF

  cat > /etc/modprobe.d/vfio.conf <<EOF
options vfio enable_unsafe_noiommu_mode=1
EOF

  cat > /etc/modprobe.d/iommu_unsafe_interrupts.conf <<EOF
options vfio_iommu_type1 allow_unsafe_interrupts=1
EOF

  if lsmod | grep -w vfio; then
    rmmod vfio-pci || :
    rmmod vfio_iommu_type1 || :
    rmmod vfio || :
    if cat /sys/module/vfio/parameters/enable_unsafe_noiommu_mode | grep N; then
      echo "!!!!! Please rebooting for IOMMU."
      exit 1
    fi
  fi
  modprobe vfio-pci
  cat /sys/module/vfio/parameters/enable_unsafe_noiommu_mode
}

setup_hugepages
setup_modules
