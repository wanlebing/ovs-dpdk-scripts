#!/bin/bash -x

# Directories #
#OVS_DIR=/home/sugeshch/repo/ovs_dpdk/ovs_dpdk
DPDK_DIR=/home/sugeshch/repo/dpdk_master
OVS_DIR=/home/sugeshch/repo/ovs_master
echo $OVS_DIR $DPDK_DIR
DPDK_PHY1=0000:05:00.0
DPDK_PHY2=0000:05:00.1
#KERNEL_DRV=i40e
KERNEL_DRV=ixgbe


# Variables #
HUGE_DIR=/dev/hugepages


function start_test {
	sudo umount $HUGE_DIR
	echo "Lets bind the ports to the kernel first"
	sudo $DPDK_DIR/tools/dpdk_nic_bind.py --bind=$KERNEL_DRV $DPDK_PHY1 $DPDK_PHY2
    mkdir -p $HUGE_DIR
	sudo mount -t hugetlbfs nodev $HUGE_DIR

	sudo modprobe uio
	sudo rmmod igb_uio.ko
	sudo insmod $DPDK_DIR/x86_64-native-linuxapp-gcc/kmod/igb_uio.ko
	sudo $DPDK_DIR/tools/dpdk_nic_bind.py --bind=igb_uio $DPDK_PHY1 $DPDK_PHY2

	sudo rm /usr/local/etc/openvswitch/conf.db
	sudo $OVS_DIR/ovsdb/ovsdb-tool create /usr/local/etc/openvswitch/conf.db $OVS_DIR/vswitchd/vswitch.ovsschema

	sudo $OVS_DIR/ovsdb/ovsdb-server --remote=punix:/usr/local/var/run/openvswitch/db.sock --remote=db:Open_vSwitch,Open_vSwitch,manager_options --pidfile &
	sudo -E $OVS_DIR/vswitchd/ovs-vswitchd --dpdk -c 0x2 -n 4 --socket-mem=1024,1 -- --pidfile unix:/usr/local/var/run/openvswitch/db.sock --log-file &
	sleep 22
	sudo $OVS_DIR/utilities/ovs-vsctl --timeout 10 del-br br0
	sudo $OVS_DIR/utilities/ovs-vsctl --timeout 10 add-br br0 -- set bridge br0 datapath_type=netdev
	sudo $OVS_DIR/utilities/ovs-vsctl --timeout 10 add-port br0 dpdk0 -- set Interface dpdk0 type=dpdk
	sudo $OVS_DIR/utilities/ovs-vsctl --timeout 10 add-port br0 dpdk1 -- set Interface dpdk1 type=dpdk

	sudo $OVS_DIR/utilities/ovs-ofctl del-flows br0
	sudo $OVS_DIR/utilities/ovs-ofctl add-flow br0 idle_timeout=0,in_port=1,action=output:2
	sudo $OVS_DIR/utilities/ovs-ofctl add-flow br0 idle_timeout=0,in_port=2,action=output:1
	#sudo $OVS_DIR/utilities/ovs-ofctl add-flow br0 idle_timeout=0,in_port=2,dl_dst=03:00:00:00:00:03,nw_dst=192.168.2.101,action=output:1
	sudo $OVS_DIR/utilities/ovs-vsctl set Open_vSwitch . other_config:pmd-cpu-mask=10
	sudo $OVS_DIR/utilities/ovs-ofctl dump-flows br0
	sudo $OVS_DIR/utilities/ovs-ofctl dump-ports br0
	sudo $OVS_DIR/utilities/ovs-vsctl show
	echo "Finished setting up the bridge, ports and flows..."
}

function kill_switch {
	echo "Killing the switch.."
	sudo $OVS_DIR/utilities/ovs-appctl -t ovs-vswitchd exit
	sudo $OVS_DIR/utilities/ovs-appctl -t ovsdb-server exit 
	sleep 1
	sudo umount $HUGE_DIR
}

function menu {
	echo "Press [q] to exit the test, or any other key to relaunch the switch"
	read next

	if [ "$next" == "q" ]; then
		echo "Exiting Test. Bye!"
		kill_switch
		exit 0
	else
		echo "Relaunching Switch.."
		kill_switch
		start_test
	fi
}

# main
while true;
do
	menu
done
