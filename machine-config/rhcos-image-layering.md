### 0.There is no wget command available in default coreos
~~~
[root@worker02 ~]# wget --help
-bash: wget: command not found

$ ssh core@worker-2.ocp4.example.com
[core@worker-2 ~]$ sudo -i
[root@worker-2 ~]# rpm-ostree status
State: idle
Deployments:
● ostree-unverified-registry:quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:95d04bea30c295df64bbe8bd708552010b78bd21a22dc0f42df1e24d35e9d587
                   Digest: sha256:95d04bea30c295df64bbe8bd708552010b78bd21a22dc0f42df1e24d35e9d587
                  Version: 412.86.202306132230-0 (2023-07-27T07:37:39Z)

[root@worker-2 ~]# wget --help
-bash: wget: command not found
~~~

### 1.Save the file either as $XDG_RUNTIME_DIR/containers/auth.json.
~~~
$ cat /root/pull-secret | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json
~~~

### 2.Find the 'rhel-coreos-8' image address that matches the current ocp version
~~~
$ oc adm release info --image-for=rhel-coreos-8 quay.io/openshift-release-dev/ocp-release:4.12.22-x86_64
quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:95d04bea30c295df64bbe8bd708552010b78bd21a22dc0f42df1e24d35e9d587

or

$ oc get cm -n openshift-machine-config-operator machine-config-osimageurl -o jsonpath='{.data.baseOSContainerImage}'

- Obtaining package list for RHEL CoreOS or specific image: https://access.redhat.com/solutions/5787001
~~~

### 3.Create Containerfile
~~~
$ cat > Containerfile << EOF
FROM quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:95d04bea30c295df64bbe8bd708552010b78bd21a22dc0f42df1e24d35e9d587
RUN rpm-ostree install wget
EOF

$ podman build -t bastion.ocp4.example.com:5000/coreos-layering/coreos-add-wget:v1 .
$ podman push bastion.ocp4.example.com:5000/coreos-layering/coreos-add-wget:v1
$ podman rmi bastion.ocp4.example.com:5000/coreos-layering/coreos-add-wget:v1
$ podman pull bastion.ocp4.example.com:5000/coreos-layering/coreos-add-wget:v1
$ podman inspect  bastion.ocp4.example.com:5000/coreos-layering/coreos-add-wget:v1 |grep RepoDigests -A1
          "RepoDigests": [
               "bastion.ocp4.example.com:5000/coreos-layering/coreos-add-wget@sha256:89871f3a4fc1c8f1375708eea3c6c5e3731efbf83baf0b77160169189fc11474"
~~~

### 4.Create a machine config file
~~~
$ cat > mc-os-layer-add-wget.yaml << EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: single
  name: os-layer-add-wget
spec:
  osImageURL: bastion.ocp4.example.com:5000/coreos-layering/coreos-add-wget@sha256:89871f3a4fc1c8f1375708eea3c6c5e3731efbf83baf0b77160169189fc11474 
EOF

$ cat single.mcp.yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfigPool
metadata:
  name: single
spec:
  machineConfigSelector:
    matchExpressions:
      - {key: machineconfiguration.openshift.io/role, operator: In, values: [worker,single]}
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/single: ""

$ oc label node worker-2.ocp4.example.com node-role.kubernetes.io/single="" 
$ oc create -f single.mcp.yaml
$ oc create -f mc-os-layer-add-wget.yaml
~~~

### 5.Check that the worker machine config pool has rolled out with the new machine config
~~~
$ oc get mc |grep os-layer-add-wget
os-layer-add-wget                                                                                                    109s
$ oc get mc | grep rendered-single |grep os-layer-add-wget
rendered-single-ec19c64c098b084aae2221bf3c1b2b9b        4accd895aa8fe5ccbd166b9562fdcf5a2112c5ec   3.2.0             59s
$ oc get node |grep worker-2.ocp4.example.com
worker-2.ocp4.example.com   Ready,SchedulingDisabled   single,worker                 151d   v1.25.10+8c21020


### 6.When the node is back in the Ready state, check that the node is using the custom layered image
~~~
$ ssh core@worker-2.ocp4.example.com
[core@worker-2 ~]$ sudo -i
[root@worker-2 ~]# rpm-ostree status
State: idle
Deployments:
● ostree-unverified-registry:bastion.ocp4.example.com:5000/coreos-layering/coreos-add-wget@sha256:89871f3a4fc1c8f1375708eea3c6c5e3731efbf83baf0b77160169189fc11474
                   Digest: sha256:89871f3a4fc1c8f1375708eea3c6c5e3731efbf83baf0b77160169189fc11474
                  Version: 412.86.202306132230-0 (2023-08-01T10:33:14Z)

[root@worker-2 ~]# wget --help
···
Startup:
  -V,  --version                   display the version of Wget and exit
  -h,  --help                      print this help
  -b,  --background                go to background after startup
  -e,  --execute=COMMAND           execute a `.wgetrc'-style command
···
~~~
