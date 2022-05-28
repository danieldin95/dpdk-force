# DPDK Support
This scripts for enforcing dpdk for openvswitch.

## step0 
to configure hugepage and load vfio modules.
```
$ ./setup/00-setup.sh
```

## step1 
to configure dpdk parameters and setup bridges.
```
$ ./setup/01-openvswitch.sh
```
