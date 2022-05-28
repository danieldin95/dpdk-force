# DPDK Support
This scripts for enforcing dpdk in network node.

## step0 
to upgrade openvswitch and install dpdk.
```
$ ./setup/00-upgrade.sh
```

## step1 
to figure out and configure 1G hugepage.
```
$ ./setup/01-hugepage.sh
```

***IMPORTANT*** rebooting this machine

## step2 
to configure openvswitch for dpdk parameters.

```
$ ./setup/02-ovs-dpdk.sh
```

## step3 
to binds device to dpdk and remove from kernel.

```
$ ./setup/03-device-bind.sh
```

## step4 
to configure nova to adapt vhost serve mode and configure neutron to set vhost-socket-dir.
```
$ ./setup/04-openstack.sh
```
