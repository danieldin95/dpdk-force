#!/bin/bash

set -ex


HUGEPAGES=2048

iommu_enabled() {
  find /sys/class/iommu | grep -i dmar
}

is_hypervisor() {
  lscpu | grep Hypervisor
}

setup_hugepages() {
  echo "vm.nr_hugepages=$HUGEPAGES" > /etc/sysctl.d/hugepages.conf
  sysctl -p /etc/sysctl.d/hugepages.conf 
  cat /proc/meminfo | grep HugePages_
}

setup_modules() {
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

  if is_hypervisor; then
cat > /etc/modprobe.d/iommu_unsafe_interrupts.conf <<EOF
options vfio_iommu_type1 allow_unsafe_interrupts=1
EOF
  else
cat > /etc/modprobe.d/iommu_unsafe_interrupts.conf <<EOF
options vfio_iommu_type1 allow_unsafe_interrupts=0
EOF
  fi

  if lsmod | grep -w vfio; then
    rmmod vfio-pci || :
    rmmod vfio_iommu_type1 || :
    rmmod vfio || :
  fi
  modprobe vfio-pci
  cat /sys/module/vfio/parameters/enable_unsafe_noiommu_mode
  cat /sys/module/vfio/holders/vfio_iommu_type1/parameters/allow_unsafe_interrupts 
}

setup_hugepages
setup_modules
