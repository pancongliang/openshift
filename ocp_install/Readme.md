1.Apply after modifying hostname and IP
~~~
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/1_specify_hostname_and_ip_variables.sh
vim 1_specify_hostname_and_ip_variables.sh
source 1_specify_hostname_and_ip_variables.sh
~~~

2.install_rpm/ocp_tool/disable_selinux_firewalld/reboot
~~~
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/2_install_rpm_ocp_tool_and_disable_selinux_firewalld_reboot.sh
bash 2_install_rpm_ocp_tool_and_disable_selinux_firewalld_reboot.sh
~~~

3.set httpd/nfs/named/haproxy/registry
~~~
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/3_set_httpd_nfs_named_haproxy_registry.sh
bash 3_set_httpd_nfs_named_haproxy_registry.sh
~~~

4.download ocp image
~~~
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/4_download_ocp_image.sh
bash 4_download_ocp_image.sh
~~~

5.create install-config.yaml and ignition
~~~
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/5_create_install_config_and_ignition.sh
source 5_create_install_config_and_ignition.sh
~~~

6.create bootstrap/master/worker ip and coreos install file
~~~
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/6_create_bootstrap_master_worker_ip_and_coreos_install_file.sh
bash 6_create_bootstrap_master_worker_ip_and_coreos_install_file.sh
~~~

7.If the nodes can communicate with the bastion machine, run the corresponding command on each node starting from bootstrap
Unable to connect to the bastion machine, please refer to the command in the "xx_set-ip-1.sh" file to set the IP of each node, and then run "curl xx-installer-2.sh"
~~~
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/7_manually_install_on_each_nod.sh
bash 7_manually_install_on_each_nod.sh
ls $INSTALL_DIR

#1. Reboot the node and use the above command to set ip
curl http://$BASTION_IP:8080/pre/bootstrap-set-ip-1.sh
bash bootstrap-set-ip-1.sh
···
#2. Install boostrtap
ssh core@$BASTION_HOSTNAME
sudo -i
curl http://$BASTION_IP:8080/pre/bootstrap-installer-2.sh
bash bootstrap-installer-2.sh

- Wait for the reboot to complete and check for error messages
$ netstat -ntplu |grep 6443
$ netstat -ntplu |grep 22623
$ podman ps
$ journalctl -b -f -u release-image.service -u bootkube.service

#3.Install master
curl http://$BASTION_IP:8080/pre/master01-installer-2.sh
bash master01-installer-2.sh
···
#4.Install worker
···
#5.Approve csr and wait for 30 minutes to check whether the cluster is normal 
oc get csr
oc get node
oc get csr -o name | xargs oc adm certificate approve
oc get co | grep -v '.True.*False.*False'

or

1.Mount ISO/Boot bootstrap node and press the "Tab" key to enter the kernel editing page
2.Enter the following
$ coreos.inst.install_dev=<DISK_PARTITION> coreos.inst.ignition_url=http://<BASTION_IP>:8080/pre/botstrap.ign
ip=<NODE_IP>::<GW>:<NETMASK>:<BOOTSTRAP_HOSTNAME>:<NERWORK_DEVICE_NAME>:none
nameserver=<DNS_IP>

- Wait for the reboot to complete and check for error messages
$ netstat -ntplu |grep 6443
$ netstat -ntplu |grep 22623
$ podman ps
$ journalctl -b -f -u release-image.service -u bootkube.service

#3.Install master
$ coreos.inst.install_dev=<DISK_PARTITION> coreos.inst.ignition_url=http://<BASTION_IP>:8080/pre/master.ign
ip=<NODE_IP>::<GW>:<NETMASK>:<MASTER_HOSTNAME>:<NERWORK_DEVICE_NAME>:none
nameserver=<DNS_IP>
···
#4.Install worker
$ coreos.inst.install_dev=<DISK_PARTITION> coreos.inst.ignition_url=http://<BASTION_IP>:8080/pre/worker.ign
ip=<NODE_IP>::<GW>:<NETMASK>:<WORKER_HOSTNAME>:<NERWORK_DEVICE_NAME>:none
nameserver=<DNS_IP>
···

#5.Approve csr and wait for 30 minutes to check whether the cluster is normal 
oc get csr
oc get node
oc get csr -o name | xargs oc adm certificate approve
oc get co | grep -v '.True.*False.*False'
~~~

8.set imageregistry operator and registry trustedCA
~~~
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/8_set_imageregistry_pv_and_trustedCA.sh
source 8_set_imageregistry_pv_and_trustedCA.sh
~~~
