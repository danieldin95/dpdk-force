# Copyright 2021 EasyStack, Inc.
#!/bin/bash

set -ex

. $(dirname $0)/functions.sh

if ecp_602; then
  cp -rvf ./bin/nova /opt
fi

cat > /dev/stdout <<'EOF'
## 1. configure vhost_sock

kubectl -n openstack get cm neutron-etc -o yaml | grep "\[ovn\]" -A 3
    [ovn]
    ovn_l3_scheduler = leastloaded
    ovn_metadata_enabled = true
    vhost_sock_dir = /var/lib/nova

kubectl -n openstack get pod | grep proton-server | awk '{print $1}' | xargs kubectl -n openstack delete pod

## 2. apply nova patch for vhostuserclient for 602 and 611 not need this.

kubectl -n openstack get cm nova-bin -o yaml | grep nova-compute.sh -A 10
  nova-compute.sh: |
    #!/bin/bash

    set -ex

    if [ -e "/opt/nova/nova" ]; then
      sudo cp -rvf /opt/nova/nova /usr/lib/python2.7/site-packages
    fi

kubectl -n openstack get pod | grep nova-compute | awk '{print $1}' | xargs kubectl -n openstack delete pod

## 3. create dpdk flavor

kubectl -n openstack exec -it $(kubectl -n openstack get pod | grep busybox  | awk '{print $1}') bash

source /openrc

openstack flavor create --vcpus 1 --ram 1024  dpdk-tiny_1 --property hw:mem_page_size=large
openstack flavor create --vcpus 2 --ram 2048  dpdk-tiny_2 --property hw:mem_page_size=large
openstack flavor create --vcpus 4 --ram 4096  dpdk-middle_1 --property hw:mem_page_size=large
openstack flavor create --vcpus 8 --ram 8192  dpdk-middle_2 --property hw:mem_page_size=large
openstack flavor create --vcpus 16 --ram 16384  dpdk-large_1 --property hw:mem_page_size=large

### 3.1 create octavia flavor

openstack flavor create \
  --id 630 --vcpus 1 --ram 2048 \
  --property hw:mem_page_size=large \
  --property amphora_owned=True \
  --property en_US='Tiny I+' --property zh_CN='小型I+' \
  amp_dpdk_tiny_1

openstack flavor create \
  --id 632 --vcpus 4 --ram 8192 \
  --property hw:mem_page_size=large \
  --property amphora_owned=True \
  --property en_US='Middle I+' --property zh_CN='中型I+' \
  amp_dpdk_middle_1

openstack flavor create \
  --id 634 --vcpus 8 --ram 16384 \
  --property hw:mem_page_size=large \
  --property amphora_owned=True \
  --property en_US='Large I+' --property zh_CN='大型I+' \
  amp_dpdk_large_1

openstack flavor create \
  --id 634 --vcpus 16 --ram 32768 \
  --property hw:mem_page_size=large \
  --property amphora_owned=True \
  --property en_US='Large II+' --property zh_CN='大型II+' \
  amp_dpdk_large_2

openstack flavor create \
  --id 636 --vcpus 32 --ram 32768 \
  --property hw:mem_page_size=large \
  --property amphora_owned=True \
  --property en_US='Super I+' --property zh_CN='巨型I+' \
  amp_dpdk_super_2

## 3.2. create compute az

nova aggregate-create dpdk dpdk-az
nova aggregate-add-host dpdk node-4.domain.tld
nova aggregate-add-host dpdk node-5.domain.tld

EOF