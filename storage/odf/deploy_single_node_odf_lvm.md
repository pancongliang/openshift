### What is ODF LVM?
OpenShift Data Foundation Logical Volume Manager (ODF LVM) is a way to deploy ODF using the local storage of a single OpenShift node. ODF LVM can be regarded as a streamlined deployment method for deploying ODF on a single node.

Since ODF is actually a containerized Ceph deployment method, a single OpenShift node deploying ODF LVM requires at least three additional storage devices. This article uses OpenShift Local to demonstrate how to install and configure ODF on a single node OpenShift.

It should be noted that standard ODF is deployed on multiple nodes and therefore has RWX capabilities. ODF LVM only runs on one node, so its PV does not have the RWX capability of simultaneous access by multiple nodes.


#### Add storage devices to worker nodes
* Select a worker node and add 3 storage devices to the worker node
~~~
ssh core@<worker-node-name> sudo lsblk
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sda      8:0    0   80G  0 disk 
├─sda1   8:1    0    1M  0 part 
├─sda2   8:2    0  127M  0 part 
├─sda3   8:3    0  384M  0 part /boot
└─sda4   8:4    0 79.5G  0 part /sysroot
sr0     11:0    1 1024M  0 rom 
sdb    252:16   0    10G  0 disk    # Additional storage devices
sdc    252:32   0    10G  0 disk    #
sdd    252:48   0    10G  0 disk    #
~~~

#### Install and configure the ODF LVM Operator
1. Install the ODF LVM Operator using default configuration in the OpenShift console

2. Create an instance of LVMCluster using default configuration in ODF LVM Operator
~~~
kind: LVMCluster
apiVersion: lvm.topolvm.io/v1alpha1
metadata:
  name: odf-lvmcluster
  namespace: openshift-storage
spec:
  storage:
    deviceClasses:
      - name: vg1
        thinPoolConfig:
          name: thin-pool-1
          overprovisionRatio: 10
          sizePercent: 90
~~~

* After deployment is completed, you can see the following pod in the openshift-storage project  
~~~
$ oc get po -n openshift-storage 
~~~

* View the cluster StorageClass and there are already the following two, the first of which comes with OpenShift Local, and the second is newly created by the ODF LVM Operator.
~~~
$ oc get storageclass
NAME                                     PROVISIONER                        RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
crc-csi-hostpath-provisioner (default)   kubevirt.io.hostpath-provisioner   Delete          WaitForFirstConsumer   false                  40d
odf-lvm-vg1                              topolvm.cybozu.com                 Delete          WaitForFirstConsumer   true                   12h
~~~

~~~
ssh core@<worker-node-name> sudo lsblk
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sda      8:0    0   80G  0 disk 
├─sda1   8:1    0    1M  0 part 
├─sda2   8:2    0  127M  0 part 
├─sda3   8:3    0  384M  0 part /boot
└─sda4   8:4    0 79.5G  0 part /sysroot
sr0     11:0    1 1024M  0 rom 
sdb                                                252:16   0    10G  0 disk 
|-vg1-thin--pool--1_tmeta                          253:0    0     4M  0 lvm  
| `-vg1-thin--pool--1-tpool                        253:2    0    27G  0 lvm  
|   |-vg1-thin--pool--1                            253:3    0    27G  1 lvm  
|   `-vg1-2bdb8b85--622f--426a--a096--abe626f32550 253:4    0     1G  0 lvm  /var/lib/kubelet/pods/1c972e66-d879-44d2-92f6-1ba4284237f5/volumes/kubernetes.io~csi/pvc-4f3f49a6-238c-4f77-93ce-96bb8fc77dde/mount
`-vg1-thin--pool--1_tdata                          253:1    0    27G  0 lvm  
  `-vg1-thin--pool--1-tpool                        253:2    0    27G  0 lvm  
    |-vg1-thin--pool--1                            253:3    0    27G  1 lvm  
    `-vg1-2bdb8b85--622f--426a--a096--abe626f32550 253:4    0     1G  0 lvm  /var/lib/kubelet/pods/1c972e66-d879-44d2-92f6-1ba4284237f5/volumes/kubernetes.io~csi/pvc-4f3f49a6-238c-4f77-93ce-96bb8fc77dde/mount
sdc                                                252:32   0    10G  0 disk 
`-vg1-thin--pool--1_tdata                          253:1    0    27G  0 lvm  
  `-vg1-thin--pool--1-tpool                        253:2    0    27G  0 lvm  
    |-vg1-thin--pool--1                            253:3    0    27G  1 lvm  
    `-vg1-2bdb8b85--622f--426a--a096--abe626f32550 253:4    0     1G  0 lvm  /var/lib/kubelet/pods/1c972e66-d879-44d2-92f6-1ba4284237f5/volumes/kubernetes.io~csi/pvc-4f3f49a6-238c-4f77-93ce-96bb8fc77dde/mount
sdd                                                252:48   0    10G  0 disk 
`-vg1-thin--pool--1_tdata                          253:1    0    27G  0 lvm  
  `-vg1-thin--pool--1-tpool                        253:2    0    27G  0 lvm  
    |-vg1-thin--pool--1                            253:3    0    27G  1 lvm  
    `-vg1-2bdb8b85--622f--426a--a096--abe626f32550 253:4    0     1G  0 lvm  /var/lib/kubelet/pods/1c972e66-d879-44d2-92f6-1ba4284237f5/volumes/kubernetes.io~csi/pvc-4f3f49a6-238c-4f77-93ce-96bb8fc77dde/moun
~~~

#### Create PVC/PV verification using ODF
~~~
$ oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0

$ oc set volumes deployment/nginx \
   --add --name nginx-volume --type pvc --claim-class odf-lvm-vg1 \
   --claim-mode RWO --claim-size 10Gi --mount-path /data \
   --claim-name nginx-volume

$ oc rsh nginx df -h data
~~~
