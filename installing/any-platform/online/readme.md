## Online Installation OpenShift4

### Machine List

| Hostname                    | Role                                           |
|-----------------------------|------------------------------------------------|
| bastion.ocp4.example.com     | bastion (nfs/haproxy/dns/httpd)                |
| master01.ocp4.example.com    | master                                         |
| master02.ocp4.example.com    | master                                         |
| master03.ocp4.example.com    | master                                         |
| worker01.ocp4.example.com    | worker                                         |
| worker02.ocp4.example.com    | worker                                         |
| worker03.ocp4.example.com    | worker                                         |
| bootstrap.ocp4.example.com   | bootstrap                                      |


### Download the Installation Script

* To download the installation script, run the following command:

  ```
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/installing/any-platform/online/00-dl-script.sh | sh
  ```

### Register Subscription

* Run the following command to register the subscription:

  ```
  source 00-reg-sub.sh
  ```


### Set Environment Variables

* Edit and source the environment variables script:

  ```
  vim 01-set-params.sh
  source 01-set-params.sh
  ```


### Install Infrastructure and Generate Scripts

* Run the pre-installation script:

  ```
  source 02-pre-inst.sh

  $ ls ${INSTALL_DIR}/set*
  inst-bootstrap.sh  inst-master01.sh  inst-master02.sh  inst-master03.sh  inst-worker01.sh  inst-worker02.sh  inst-worker03.sh
  ```


### Install Bootstrap

* After mounting the ISO, start the `bootstrap` node and execute the following command:

  ```
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ curl -s http://BASTION_IP:8080/pre/inst-bootstrap.sh | sh
  [root@localhost ~]$ reboot
  ```

* After the reboot, check for error messages:
 
  ```
  [root@bastion ~]# ssh core@${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ netstat -ntplu | grep -E '6443|22623'
  [root@localhost ~]$ podman ps
  [root@localhost ~]$ journalctl -b -f -u release-image.service -u bootkube.service
  ```


### Install Control-Plane

* After mounting the ISO, start the `Control-Plane` node and execute the following command:

  ```
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ curl -s http://BASTION_IP:8080/pre/inst-master01.sh | sh
  [root@localhost ~]$ reboot
  ```
* Repeat the process for all Control-Plane nodes.
  
* Monitor the bootstrap process:

  ```
  openshift-install --dir ${INSTALL_DIR}/ wait-for bootstrap-complete --log-level=info
  ```


### Install Workers

* After mounting the ISO, start the `worker` node and execute the following command:

  ```
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ curl -s http://BASTION_IP:8080/pre/inst-worker01.sh | sh
  [root@localhost ~]$ reboot
  ```

* Repeat the process for all worker nodes.


### Approval of CSR

* Repeat the process for all worker nodes.To approve the Certificate Signing Request (CSR), run the following command:

  ```
  source ${INSTALL_DIR}/ocp4cert_approver.sh &
  ```

* Repeat the process for all worker nodes.Check the node status and operators:

  ```
  export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig
  oc get node
  oc get co | grep -v '.True.*False.*False'
  ```

### Configure Image-Registry-Operator Data Persistence

* Repeat the process for all worker nodes.Configure the image registry operator's data persistence by running the script:

  ```
  source 03-post-inst-cfg.sh
  source /etc/bash_completion.d/oc_completion
  ```


### Login to OpenShift

* Repeat the process for all worker nodes. Can login to OpenShift using the following command:

  ```
  oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443
  ```

* Or, use the KUBECONFIG environment variable:

  ```
  echo 'export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig' >> $HOME/.bash_profile
  source $HOME/.bash_profile
  ```
