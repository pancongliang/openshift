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
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/installing/v2/00-download-script.sh | sh
  ```

* Security settings and register subscriptions
  ```
  source 00-security-setup.sh
  source 00-register-subscription.sh

  reboot
  ```

* Execute after modifying the necessary parameters
  ```
  vim 01-set-ocp-install-parameters.sh
  
  source 01-set-ocp-install-parameters.sh
  ```

* Install rpm/oc and configure httpd/nfs/dns/haproxy
  ```
  source 02-install-configure-infrastructure.sh
  ```

* Install mirror-registry
  ```
  source 03-install-mirror-registry.sh
  ```

* Download ocp image
  ```
  source 04-mirror-ocp-release-image.sh
  ```

### Create ignition file and install bootstrap/master/worker node through script

* Create ignition file
  ```
  source 05-create-ignition-config-file.sh
  ```
  
* Create node installation script file
  ```
  source 06-create-installation-script.sh

  ls ${IGNITION_PATH}/set*
  set-bootstrap.sh  set-master01.sh  set-master02.sh  set-master03.sh  set-worker01.sh  set-worker02.sh
  ```

* Install bootstrap

  After mounting the ISO, start the `bootstrap` node and execute the following command.
  If the node cannot communicate, manually enter the content in `set-*.sh`.
  ```
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ curl -s http://BASTION_IP:8080/pre/set-bootstrap.sh | sh
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
  After mounting the ISO, start the `master` node and execute the following command.
  If the node cannot communicate, manually enter the content in `set-*.sh`.
  ```
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ curl -s http://BASTION_IP:8080/pre/set-master01.sh | sh
  [root@localhost ~]$ reboot
  ···Install all master nodes in sequence···
  ```

* Install all worker
  After mounting the ISO, start the `worker` node and execute the following command.
  If the node cannot communicate, manually enter the content in `set-*.sh`.
  ```
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ curl -s http://BASTION_IP:8080/pre/set-worker01.sh | sh
  [root@localhost ~]$ reboot
  ···Install all worker nodes in sequence···
  ```

* Approve csr and wait for 30 minutes to check whether the cluster is normal
  ```
  # Bastion Terminal-1:
  source 01-set-ocp-install-parameters.sh
  export KUBECONFIG=${IGNITION_PATH}/auth/kubeconfig
  while true; do
    oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
    sleep 10
  done
  ```
  ```
  # Bastion Terminal-2(Close Terminal-1 after the status of all nodes is Ready):
  source 01-set-ocp-install-parameters.sh
  export KUBECONFIG=${IGNITION_PATH}/auth/kubeconfig
  oc get node
  oc get co | grep -v '.True.*False.*False'
  ```

### Configure image-registry-operator data persistence and registry trustedCA

* Configure image-registry-operator data persistence and registry trustedCA through the following script.

  ```
  source 07-post-installation-configuration.sh
  ```
