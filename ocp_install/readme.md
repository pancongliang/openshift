**Required machines for cluster installation**
~~~
Hostname                    | Role
--- --- --- --- --- --- --- | --- --- --- --- --- --- --- 
bastion.ocp4.example.com    | bastion(nfs/registry/haproxy/dns/httpd server)
master01.ocp4.example.com   | master 
master02.ocp4.example.com   | master
master03.ocp4.example.com   | master
worker01.ocp4.example.com   | worker
worker02.ocp4.example.com   | worker
bootstrap.ocp4.example.com  | bootstrap
~~~

**1.Download script file**
~~~
mkdir ocp_install
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/00_security.sh
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/00_subscription.sh
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/01_ocp_env_parameter.sh
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/02_install_infrastructure.sh
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/03_install_mirror_registry.sh
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/04_mirror_ocp_image.sh
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/05_generate_ignition.sh
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/06_generate_setup_script_file.sh
wget https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/07_configure_after_installation.sh
~~~

**2.Security settings and subscriptions**
~~~
source 00_security.sh
source 00_subscription.sh
reboot
~~~
**3.Execute after modifying the necessary parameters**
~~~
vim 01_ocp_env_parameter.sh
source 01_ocp_env_parameter.sh
~~~

**4.Install rpm and configure httpd/nfs/dns/haproxy**
~~~
source 02_install_infrastructure.sh
~~~

**5.Install mirror-registry**
~~~
source 03_install_mirror_registry.sh
~~~

**6.download ocp image**
~~~
source 04_mirror_ocp_image.sh
~~~

**7.Generate ignition file**
~~~
source 05_generate_ignition.sh
~~~

**8.Generate setup script file**
~~~
source 06_generate_setup_script_file.sh
~~~

**9.Install bootstrap/master/worker node**
~~~
[root@bastion ~]# ls ${IGNITION_PATH}/set*
set-bootstrap.sh  set-master01.sh  set-master02.sh  set-master03.sh  set-worker01.sh  set-worker02.sh

# 1.Install bootstrap
# After mounting the ISO, start the bootstrap node and execute the following command.
# If the node cannot communicate, manually enter the content in set-*.sh.
[core@localhost ~]$ sudo -i
[root@localhost ~]$ curl http://$BASTION_IP:8080/pre/set-bootstrap.sh -o set-bootstrap.sh
[root@localhost ~]$ source set-bootstrap.sh
[root@localhost ~]$ reboot
···
# Wait for the reboot to complete and check for error messages
[root@bastion ~]# ssh core@${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
[core@localhost ~]$ sudo -i
[root@localhost ~]$ netstat -ntplu |grep 6443
[root@localhost ~]$ netstat -ntplu |grep 22623
[root@localhost ~]$ podman ps
[root@localhost ~]$ journalctl -b -f -u release-image.service -u bootkube.service

# 2.Install all master
[core@localhost ~]$ sudo -i
[root@localhost ~]$ curl http://$BASTION_IP:8080/pre/set-master01.sh -o set-master01.sh
[root@localhost ~]$ source set-master01.sh
[root@localhost ~]$ reboot
···Install all master nodes in sequence···


# 3.Install all worker
[core@localhost ~]$ sudo -i
[root@localhost ~]$ curl http://$BASTION_IP:8080/pre/set-worker01.sh -o set-worker01.sh
[root@localhost ~]$ source set-master01.sh
[root@localhost ~]$ reboot
···Install all worker nodes in sequence···

# 4.Approve csr and wait for 30 minutes to check whether the cluster is normal 
oc get csr
oc get node
oc get csr -o name | xargs oc adm certificate approve
oc get co | grep -v '.True.*False.*False'
~~~

8.Configure image-registry-operator data persistence and registry trustedCA
~~~
source 07_configure_after_installation.sh
~~~
