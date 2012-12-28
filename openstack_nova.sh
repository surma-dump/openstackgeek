#!/bin/bash

# Make sure only root can run our script
if [ "$(id -u)" != "0" ]; then
   echo "You need to be 'root' dude." 1>&2
   exit 1
fi

host_ip=$(/sbin/ifconfig eth0| sed -n 's/.*inet *addr:\([0-9\.]*\).*/\1/p')
echo "#############################################################################################################"
echo "The IP address for eth0 is probably $host_ip".  Keep in mind you need an eth1 for this to work.
echo "#############################################################################################################"
read -p "Enter the primary ethernet interface IP: " host_ip_entry
read -p "Enter the fixed network (eg. 10.0.2.32/27): " fixed_range
read -p "Enter the fixed starting IP (eg. 10.0.2.33): " fixed_start
echo "#######################################################################################"
echo "The floating range can be a subset of your current network.  Configure your DHCP server"
echo "to block out the range before you choose it here.  An example would be 10.0.1.224-255"
echo "#######################################################################################"
read -p "Enter the floating network (eg. 10.0.1.224/27): " floating_range
read -p "Enter the floating netowrk size (eg. 32): " floating_size

# get nova
apt-get install nova-api nova-cert nova-common nova-compute nova-compute-kvm nova-doc nova-network nova-objectstore nova-scheduler nova-novncproxy nova-volume python-nova python-novaclient nova-consoleauth novnc

. ./stackrc
password=$SERVICE_PASSWORD

# hack up the nova paste file
sed -e "
s,%SERVICE_TENANT_NAME%,admin,g;
s,%SERVICE_USER%,admin,g;
s,%SERVICE_PASSWORD%,$password,g;
" -i /etc/nova/api-paste.ini

# write out a new nova file
echo "
[DEFAULT]

# MySQL Connection #
sql_connection=mysql://nova:$password@127.0.0.1/nova

# nova-scheduler #
rabbit_password=password
scheduler_driver=nova.scheduler.simple.SimpleScheduler

# nova-api #
cc_host=$host_ip_entry
auth_strategy=keystone
s3_host=$host_ip_entry
ec2_host=$host_ip_entry
nova_url=http://$host_ip_entry:8774/v1.1/
ec2_url=http://$host_ip_entry:8773/services/Cloud
keystone_ec2_url=http://$host_ip_entry:5000/v2.0/ec2tokens
api_paste_config=/etc/nova/api-paste.ini
allow_admin_api=true
use_deprecated_auth=false
ec2_private_dns_show_ip=True
dmz_cidr=169.254.169.254/32
ec2_dmz_host=$host_ip_entry
metadata_host=$host_ip_entry
metadata_listen=0.0.0.0
enabled_apis=ec2,osapi_compute,metadata

# Networking #
network_api_class=nova.network.quantumv2.api.API
quantum_url=http://$host_ip_entry:9696
quantum_auth_strategy=keystone
quantum_admin_tenant_name=service
quantum_admin_username=quantum
quantum_admin_password=$password
quantum_admin_auth_url=http://$host_ip_entry:35357/v2.0
libvirt_vif_driver=nova.virt.libvirt.vif.LibvirtHybridOVSBridgeDriver
linuxnet_interface_driver=nova.network.linux_net.LinuxOVSInterfaceDriver
firewall_driver=nova.virt.libvirt.firewall.IptablesFirewallDriver

# Cinder #
volume_api_class=nova.volume.cinder.API

# Glance #
glance_api_servers=$host_ip_entry:9292
image_service=nova.image.glance.GlanceImageService

# novnc #
novnc_enable=true
novncproxy_base_url=http://$host_ip_entry:6080/vnc_auto.html
vncserver_proxyclient_address=127.0.0.1
vncserver_listen=0.0.0.0

# Misc #
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/var/lock/nova
root_helper=sudo nova-rootwrap /etc/nova/rootwrap.conf
verbose=true
" > /etc/nova/nova.conf

# sync db
nova-manage db sync

# restart nova
./openstack_restart_nova.sh

# no clue why we have to do this when it's in the config?
nova-manage network create private --fixed_range_v4=$fixed_range --num_networks=1 --bridge=br100 --bridge_interface=eth1 --network_size=$fixed_size
nova-manage floating create --ip_range=$floating_range

# do we need this?
chown -R nova:nova /etc/nova/

echo "#######################################################################################"
echo "'nova list' and a 'nova image-list' to test.  Do './openstack_horizon.sh' next."
echo "#######################################################################################"

