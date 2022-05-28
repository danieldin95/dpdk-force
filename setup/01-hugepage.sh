# Copyright 2021 EasyStack, Inc.
#!/bin/bash

set -ex

. $(dirname $0)/functions.sh

function figure_out_memory() {
  local memory_total_kib=$(cat /proc/meminfo | grep MemTotal | awk '{print $2}')
  MEM_TOTAL=$(( memory_total_kib / 1024 ))
  local osd_count=$(get_osd_count)
  if [ $osd_count -gt 0 ]; then
    OSD_RESERVED_MEM=$(( 4 * $osd_count * 1024 ))
  fi
}

function configure_hugepage() {
  local numa_nodes=$(get_numa_node)
  local dpdk_reserved_mem=$(( $MEM_TOTAL-$POD_RESERVED_MEM-$SYSTEM_RESERVED_MEM-$OSD_RESERVED_MEM ))
  local dpdk_reserved_hugepages=$(( $dpdk_reserved_mem / HUGEPAGESZ ))
  if [ ! $dpdk_reserved_hugepages -gt 0 ]; then
    echo "ERROR: not enough memory for dpdk:"$dpdk_reserved_mem
    return 1
  fi
  if cat /etc/default/grub | grep default_hugepagesz; then
    sed -i -e 's/default_hugepagesz=\w* hugepagesz=\w* hugepages=\w* //g' /etc/default/grub
  fi
  if cat /etc/default/grub | grep default_hugepagesz; then
    echo "ERROR: hugepages setup failed."
    return 1
  fi
  sed -i -e 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="default_hugepagesz='${HUGEPAGESZ}'M hugepagesz='${HUGEPAGESZ}'M hugepages='$dpdk_reserved_hugepages' /' /etc/default/grub
  if [ -e '/boot/efi/EFI/escore/grub.cfg' ]; then
    grub2-mkconfig --output=/boot/efi/EFI/escore/grub.cfg
  elif [ -e '/boot/grub2/grub.cfg' ]; then
    grub2-mkconfig --output=/boot/grub2/grub.cfg
  else
    echo "ERROR: file grub.cfg not found."
  fi
  cat /etc/default/grub | grep default_hugepagesz
  echo "INFO: ^^^ Please restart this machine to effect hugepages ^^^"
}

figure_out_memory
configure_hugepage