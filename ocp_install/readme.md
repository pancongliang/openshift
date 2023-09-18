### Restricted network installation OpenShift4
* Use scripts to install and configure the infrastructure and download the ocp image to the offline warehouse.
* The script generates the ignition file, and downloads and executes the script from node to install openshift.

* Required machines for cluster installation
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

### Download the script and install and configure infrastructure services through the script

* Download script file
  ~~~
  wget -O - https://raw.githubusercontent.com/pancongliang/openshift/main/ocp_install/00_download_scripts.sh | sh
  ~~~

* Security settings and subscriptions
  ~~~
  source 00_security.sh
  source 00_subscription.sh
  reboot
  ~~~

* Execute after modifying the necessary parameters
  ~~~
  vim 01_ocp_env_parameter.sh
  source 01_ocp_env_parameter.sh
  ~~~

* Install rpm and configure httpd/nfs/dns/haproxy
  ~~~
  source 02_install_infrastructure.sh
  ~~~

* Install mirror-registry
  ~~~
  source 03_install_mirror_registry.sh
  ~~~

* Download ocp image
  ~~~
  source 04_mirror_ocp_image.sh
  ~~~

* Generate ignition file
  ~~~
  source 05_generate_ignition.sh
  ~~~

* Generate setup script file
  ~~~
  source 06_generate_setup_script_file.sh
  ~~~

### Generate igniyion file and install bootstrap/master/worker node through script

* Generate ignition file
  ~~~
  source 05_generate_ignition.sh
  ~~~
* Generate setup script file
  ~~~
  source 06_generate_setup_script_file.sh
  ~~~
* After mounting the ISO, start the bootstrap node and execute the following command.
  If the node cannot communicate, manually enter the content in set-*.sh.
  ~~~
  [root@bastion ~]# ls ${IGNITION_PATH}/set*
  set-bootstrap.sh  set-master01.sh  set-master02.sh  set-master03.sh  set-worker01.sh  set-worker02.sh
  ~~~
* Install bootstrap
  ~~~
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ curl -s http://$BASTION_IP:8080/pre/set-bootstrap.sh | sh
  [root@localhost ~]$ source set-bootstrap.sh
  [root@localhost ~]$ reboot
  ···
  # Wait for the reboot to complete and check for error messages
  [root@bastion ~]# ssh core@${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ netstat -ntplu |grep 6443
  [root@localhost ~]$ netstat -ntplu |grep 22623
  [root@localhost ~]$ podman ps
  [root@localhost ~]$ journalctl -b -f -u release-image.service -u bootkube.service
  ~~~
* Install all master
  ~~~
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ curl -s http://$BASTION_IP:8080/pre/set-master01.sh | sh
  [root@localhost ~]$ reboot
  ···Install all master nodes in sequence···
  ~~~
* Install all worker
  ~~~
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ curl -s http://$BASTION_IP:8080/pre/set-worker01.sh | sh
  [root@localhost ~]$ reboot
  ···Install all worker nodes in sequence···
  ~~~

* Approve csr and wait for 30 minutes to check whether the cluster is normal
  ~~~
  [root@bastion ~]# export KUBECONFIG=${IGNITION_PATH}/auth/kubeconfig
  [root@bastion ~]# oc get csr
  [root@bastion ~]# oc get node
  [root@bastion ~]# oc get csr -o name | xargs oc adm certificate approve
  [root@bastion ~]# oc get co | grep -v '.True.*False.*False'
  ~~~

### Configure image-registry-operator data persistence and registry trustedCA

  ~~~
  source 07_configure_after_installation.sh
  ~~~
