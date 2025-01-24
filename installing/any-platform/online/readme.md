## Online Installation OpenShift4

```
Hostname                    | Role
--- --- --- --- --- --- --- | --- --- --- --- --- --- --- 
bastion.ocp4.example.com    | bastion(nfs/haproxy/dns/httpd)
master01.ocp4.example.com   | master 
master02.ocp4.example.com   | master
master03.ocp4.example.com   | master
worker01.ocp4.example.com   | worker
worker02.ocp4.example.com   | worker
worker03.ocp4.example.com   | worker
bootstrap.ocp4.example.com  | bootstrap
```


### Download the installation script
```
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/installing/any-platform/online/00-dl-script.sh | sh
```

### Register Subscription
```
source 00-reg-sub.sh
```

### Setting Environment Variables
```
vim 01-set-params.sh
source 01-set-params.sh
```

### Install infrastructure and generate scripts
```
source 02-inst-pre.sh

ls ${IGNITION_PATH}/set*
set-bootstrap.sh  set-master01.sh  set-master02.sh  set-master03.sh  set-worker01.sh  set-worker02.sh set-worker03.sh
```

### Install bootstrap

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

### Install all master

After mounting the ISO, start the `master` node and execute the following command.
If the node cannot communicate, manually enter the content in `set-*.sh`.
```
[core@localhost ~]$ sudo -i
[root@localhost ~]$ curl -s http://BASTION_IP:8080/pre/set-master01.sh | sh
[root@localhost ~]$ reboot
···Install all master nodes in sequence···
```

### Install all worker

After mounting the ISO, start the `worker` node and execute the following command.
If the node cannot communicate, manually enter the content in `set-*.sh`.
```
[core@localhost ~]$ sudo -i
[root@localhost ~]$ curl -s http://BASTION_IP:8080/pre/set-worker01.sh | sh
[root@localhost ~]$ reboot
···Install all worker nodes in sequence···
```

### Approval of CSR

```
source approve-csr.sh &

export KUBECONFIG=${IGNITION_PATH}/auth/kubeconfig
oc get node
oc get co | grep -v '.True.*False.*False'
```

### Configure image-registry-operator data persistence

```
source 03-post-inst-cfg.sh
```

### Login openshift

```
oc login -u admin -p redhat https://api.$CLUSTER_NAME.$BASE_DOMAIN:6443]

or

export KUBECONFIG=${IGNITION_PATH}/auth/kubeconfig

oc completion bash >> /etc/bash_completion.d/oc_completion
```
