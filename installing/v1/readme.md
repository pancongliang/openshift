## Restricted network installation OpenShift4

* Use scripts to install and configure the infrastructure and download the ocp image to the offline registry.
* The script generates the ignition file, and downloads and executes the script from node to install openshift.

* Required machines for cluster installation
  ```
  Hostname                    | Role
  --- --- --- --- --- --- --- | --- --- --- --- --- --- --- 
  bastion.ocp4.example.com    | bastion(nfs/registry/haproxy/dns/httpd)
  master01.ocp4.example.com   | master 
  master02.ocp4.example.com   | master
  master03.ocp4.example.com   | master
  worker01.ocp4.example.com   | worker
  worker02.ocp4.example.com   | worker
  bootstrap.ocp4.example.com  | bootstrap
  ```

### Download the script and install and configure infrastructure services through the script

* Download script file
  ```
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/installing/v1/00-download-script.sh | sh
  ```

* Security settings and subscriptions
  ```
  source 00-security.sh
  source 00-subscription.sh

  reboot
  ```

* Execute after modifying the necessary parameters
  ```
  vim 01-set-ocp-env-parameter.sh
  
  source 01-set-ocp-env-parameter.sh
  ```

* Install rpm and configure httpd/nfs/dns/haproxy
  ```
  source 02-install-infrastructure.sh
  ```

* Install mirror-registry
  ```
  source 03-install-mirror-registry.sh
  ```

* Download ocp image
  ```
  source 04-mirror-ocp-release-image.sh
  ```

### Generate ignition file and install bootstrap/master/worker node through script

* Generate ignition file
  ```
  source 05-generate-ignition-file.sh
  ```
  
* Generate setup script file
  ```
  source 06-generate-setup-script-file.sh

  ls ${IGNITION_PATH}/set*
  set-bootstrap.sh  set-master01.sh  set-master02.sh  set-master03.sh  set-worker01.sh  set-worker02.sh
  ```

* Install bootstrap

  After mounting the ISO, start the bootstrap node and execute the following command.
  If the node cannot communicate, manually enter the content in set-*.sh.
  
  ```
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ curl -s http://$BASTION_IP:8080/pre/set-bootstrap.sh | sh
  [root@localhost ~]$ reboot
  ···
  # Wait for the reboot to complete and check for error messages
  [root@bastion ~]# ssh core@${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}
  
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ netstat -ntplu |grep 6443
  [root@localhost ~]$ netstat -ntplu |grep 22623
  [root@localhost ~]$ podman ps
  [root@localhost ~]$ journalctl -b -f -u release-image.service -u bootkube.service
  ```

* Install all master
  ```
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ curl -s http://$BASTION_IP:8080/pre/set-master01.sh | sh
  [root@localhost ~]$ reboot
  ···Install all master nodes in sequence···
  ```

* Install all worker
  ```
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ curl -s http://$BASTION_IP:8080/pre/set-worker01.sh | sh
  [root@localhost ~]$ reboot
  ···Install all worker nodes in sequence···
  ```

* Approve csr and wait for 30 minutes to check whether the cluster is normal
  ```
  [root@bastion ~]# export KUBECONFIG=${IGNITION_PATH}/auth/kubeconfig
  [root@bastion ~]# oc get csr
  [root@bastion ~]# oc get node
  [root@bastion ~]# oc get csr -o name | xargs oc adm certificate approve
  [root@bastion ~]# oc get co | grep -v '.True.*False.*False'
  ```

### Configure image-registry-operator data persistence and registry trustedCA

* Configure image-registry-operator data persistence and registry trustedCA through the following script.

  ```
  source 07-configure-after-installation.sh
  ```
