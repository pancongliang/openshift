## Offlile Installation of OpenShift 4

### Prerequisites
* The script needs to be run as `root` user  
* Prepare the following machines  

  | Hostname                    | Role                         | vCPU | RAM  | Storage |
  |-----------------------------|-----------------------------|------|------|---------|
  | bastion.ocp4.example.com    | bastion (NFS/HAProxy/DNS/HTTPD) | 4  |  6 GB  |  100 GB   |
  | bootstrap.ocp4.example.com  | bootstrap                   |  4   | 16 GB | 100 GB  |
  | master01.ocp4.example.com   | master                      |  4   | 16 GB | 100 GB  |
  | master02.ocp4.example.com   | master                      |  4   | 16 GB | 100 GB  |
  | master03.ocp4.example.com   | master                      |  4   | 16 GB | 100 GB  |
  | worker01.ocp4.example.com   | worker                      |  4   |  8 GB | 100 GB  |
  | worker02.ocp4.example.com   | worker                      |  4   |  8 GB | 100 GB  |
  | worker03.ocp4.example.com   | worker                      |  4   |  8 GB | 100 GB  |


### Download the Installation Script

* In the bastion machine, run the following command to download the installation script:

  ```
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/installing/any-platform/online/00-dl-script.sh | sh
  ```


### Register Subscription

* In the bastion machine, run the following command to register the subscription:

  ```
  bash 00-reg-sub.sh
  ```


### Set the necessary installation parameters

* In the bastion machine, edit and apply the environment variable script:

  ```
  vim 01-set-params.sh
  source 01-set-params.sh
  ```


### Install Infrastructure and Generate Scripts

* In the bastion machine, run the pre-installation script to install and configure NFS, HTTPD, Named, HAProxy, Registry, OpenShift tools, and other required components. This script also generates the Ignition file and installation scripts for each node:

  ```
  bash 02-pre-inst.sh
  ```
  
* In the bastion machine, check whether the node installation script has been generated:
  ```
  (cd "${INSTALL_DIR}" && ls -d bs m[0-9] w[0-9])

  bs  m1  m2  m3  w1  w2  w3
  ```

  
### Mirror the OpenShift Release Image

* In the bastion machine, run the following command to mirror the OCP release image:
  
  ```
  bash 03-mirror-img.sh
  ```


### Install the Bootstrap Nodes

* Mount the ISO on the bootstrap node, then boot the node and run the following command:

  ```
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ curl -s http://BASTION_IP:8080/pre/bs | sh
  [root@localhost ~]$ reboot
  ```

* After the reboot, check for error messages:
 
  ```
  [root@bastion ~]# ssh core@${BOOTSTRAP_HOSTNAME}
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ netstat -ntplu | grep -E '6443|22623'
  [root@localhost ~]$ podman ps
  [root@localhost ~]$ journalctl -b -f -u release-image.service -u bootkube.service
  ```


### Install the Control Plane Nodes

* Mount the ISO on the control-plane node, then boot the node and run the following command:

  ```
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ curl -s http://BASTION_IP:8080/pre/m1 | sh
  [root@localhost ~]$ reboot
  ```
* Repeat the process for all Control-Plane nodes.
  
* Monitor the bootstrap process:

  ```
  openshift-install --dir ${INSTALL_DIR}/ wait-for bootstrap-complete --log-level=info
  ```


### Install the Worker Nodes

* Mount the ISO on the worker node, then boot the node and run the following command:

  ```
  [core@localhost ~]$ sudo -i
  [root@localhost ~]$ curl -s http://BASTION_IP:8080/pre/w1 | sh
  [root@localhost ~]$ reboot
  ```

* Repeat the process for all worker nodes.


### Approve Pending CSRs

* In the bastion machine, run the following command to approve the Certificate Signing Request (CSR):
  
  ```
  bash ${INSTALL_DIR}/ocp4cert-approver.sh &
  ```

* In the bastion machine, Check the node status and operators:

  ```
  export KUBECONFIG=${INSTALL_DIR}/auth/kubeconfig
  oc get node
  oc get co | grep -v '.True.*False.*False'
  ```

### Configure Image Registry Storage and Create htpasswd User

* In the bastion machine, run the following command to configure image registry data persistence and create the htpasswd user:

  ```
  bash 04-post-inst-cfg.sh
  oc completion bash >> /etc/bash_completion.d/oc_completion
  source /etc/bash_completion.d/oc_completion
  source $HOME/.bash_profile
  ```


### Log in to OpenShift

* In the bastion machine, run the following command to log in to OpenShift:

  ```
  unset KUBECONFIG
  oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443 --insecure-skip-tls-verify=false
  ```
