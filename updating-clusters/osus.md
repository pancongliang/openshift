## Use OSUS Upgrade The Cluster

### Environment
~~~
- Current version:
$ oc get clusterversion
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.9.15    True        False         2d9h    Cluster version is 4.9.15

- Desired version: 4.10.20
~~~

### 1.Configuring access to a secured registry for the OpenShift update service
~~~
$ oc edit cm registry-config -n openshift-config
apiVersion: v1
data:
  updateservice-registry: |      # The OpenShift Update Service Operator requires the config map key name updateservice-registry in the registry CA cert.
    -----BEGIN CERTIFICATE-----
    ···
    -----END CERTIFICATE-----
  docker.registry.example.com..5000: |  # 	If the registry has the port, such as registry-with-port.example.com:5000, : should be replaced with ...
    -----BEGIN CERTIFICATE-----
    ···
    -----END CERTIFICATE-----
~~~


### 2.Optional: Updating the global cluster pull secret
- The procedure is required when users use a separate registry to store images than the registry used during installation.
~~~
$ podman login --authfile /root/pull-secret.txt docker.registry.example.com:5000
Username: admin
Password: 
Login Succeeded!

$ oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=/root/pull-secret.txt

$ ssh core@<node-name> sudo cat /var/lib/kubelet/config.json | jq
{
        "auths": {
                "docker.registry.example.com:5000": {
                        "auth": "xxx"
                }
        }
}
~~~


### 3.Installing the OpenShift Update Service Operator by using the web console
~~~
Web console -> Administrator -> Operators -> OperatorHub -> cincinnati-operator

$ oc -n openshift-update-service get clusterserviceversions
NAME                             DISPLAY                    VERSION   REPLACES                         PHASE
update-service-operator.v5.0.0   OpenShift Update Service   5.0.0     update-service-operator.v4.9.1   Succeeded

$ oc get po -n openshift-update-service
NAME                                     READY   STATUS    RESTARTS   AGE
updateservice-operator-c77465bfd-kk2td   1/1     Running   0          4m33s
~~~


### 4.Use the oc-mirror tool to mirror ocp image
~~~
### IMPORTANT
- Upgrade from ocp4.9.15 version to ocp4.10.20 version:
  Standard upgrade path[2]:  4.9.15(current version) -> 4.9.40(intermediate version) -> 4.10.20(desired version).
  Therefore, the full ocp image of the current/intermediate/desired version needs to be mirrored.
  After ocp 4.9.15/4.9.40/4.10.20 version image mirroring is completed.
  1. When the current version is 4.9.15, only the upgrade path of version 4.9.40 can be seen.
  2. After upgrading to version 4.9.40 (intermediate version),  will see version 4.10.20 (Desired version).
     Testing Process: Step 7
~~~

~~~
- Install oc-mirror tool:
$ curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz
$ tar -xvf oc-mirror.tar.gz
$ chmod +x ./oc-mirror
$ sudo mv ./oc-mirror /usr/local/bin/.

- Configuring credentials that allow images to be mirrored:
# Download pull-secret
$ podman login --authfile /root/pull-secret.txt docker.registry.example.com:5000
$ cat /root/pull-secret.txt | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json

- Creating the image set configuration[2][3]
$ cat << EOF > ./shortest-upgrade-imageset-configuration.yaml
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
storageConfig:
  registry:
    imageURL: docker.registry.example.com:5000/mirror/metadata-3
    skipTLS: false
mirror:
  platform:
    channels:
    - name: stable-4.10
      minVersion: 4.9.15
      maxVersion: 4.10.20
      shortestPath: true   #<--[3].Mirror only the shortest upgrade path，For example: setting minVersion 4.9.15/maxVersion 4.10.20 will mirror intermediate version 4.9.40
    graph: true            #<--[4].OSUS graphics data is also mirrored in the local registry
EOF

$ oc mirror --config=shortest-upgrade-imageset-configuration.yaml docker://docker.registry.example.com:5000 --dest-skip-tls
···
info: Mirroring completed in 16m38.97s (33.58MB/s)
Writing image mapping to oc-mirror-workspace/results-1669080793/mapping.txt
Writing UpdateService manifests to oc-mirror-workspace/results-1669080793
Writing ICSP manifests to oc-mirror-workspace/results-16690807

$ ls -ltr oc-mirror-workspace/results-1669080793
total 100
drwxr-xr-x 2 root root     6 Nov 22 01:12 charts
drwxr-xr-x 2 root root   144 Nov 22 01:13 release-signatures
-rw-r--r-- 1 root root 91865 Nov 22 01:33 mapping.txt
-rwxr-xr-x 1 root root   349 Nov 22 01:33 updateService.yaml             #<-- This file will be used in subsequent steps
-rwxr-xr-x 1 root root   639 Nov 22 01:33 imageContentSourcePolicy.yaml  #<-- This file will be used in subsequent steps

$ oc create -f oc-mirror-workspace/results-1669080793/imageContentSourcePolicy.yaml 

$ podman search docker.registry.example.com:5000/openshift/release-images --list-tags --limit=1000 --tls-verify=false --authfile /root/pull-secret
NAME                                                       TAG
docker.registry.example.com:5000/openshift/release-images  4.9.40-x86_64
docker.registry.example.com:5000/openshift/release-images  4.9.15-x86_64
docker.registry.example.com:5000/openshift/release-images  4.10.20-x86_64

$ oc get imagecontentsourcepolicy
NAME             AGE
generic-0        32s
release-0        32s
···
~~~

### 5. Creating an OpenShift Update Service application
~~~
- Use the updateService.yaml file automatically generated in step 4
$ cat oc-mirror-workspace/results-1669080793/updateService.yaml 
apiVersion: updateservice.operator.openshift.io/v1
kind: UpdateService
metadata:
  name: update-service-oc-mirror
spec:
  graphDataImage: docker.registry.example.com:5000/openshift/graph-image@sha256:046dc941d94df3ada844994c3c1f8c5e1f57e55232c5295979902daf570fbe53
  releases: docker.registry.example.com:5000/openshift/release-images
  replicas: 2

$ oc create -f oc-mirror-workspace/results-1669080793/updateService.yaml -n openshift-update-service

$ oc get po -n openshift-update-service 
NAME                                        READY   STATUS    RESTARTS   AGE
update-service-oc-mirror-699d5696d8-2l2xz   2/2     Running   0          22s
update-service-oc-mirror-699d5696d8-prm4s   2/2     Running   0          23s
updateservice-operator-c77465bfd-kk2td      1/1     Running   0          6m29s
~~~

### 6. Configuring the Cluster Version Operator (CVO)
~~~
$ NAMESPACE=openshift-update-service
$ NAME=update-service-oc-mirror

- In order to avoid cluster restart, customize the http route (when using the default https route, you need to configure the Route CA to trust the update server[4].
$ oc expose service "$NAME"-policy-engine -n "$NAMESPACE"

$ oc get route update-service-oc-mirror-policy-engine -n openshift-update-service
NAME                                     HOST/PORT                                                                               PATH   SERVICES                                 PORT            TERMINATION   WILDCARD
update-service-oc-mirror-policy-engine   update-service-oc-mirror-policy-engine-openshift-update-service.apps.ocp4.example.com          update-service-oc-mirror-policy-engine   policy-engine                 None

$ POLICY_ENGINE_GRAPH_URI="http://$(oc -n "$NAMESPACE" get route "$NAME"-policy-engine -o jsonpath='{.spec.host}/api/upgrades_info/v1/graph{"\n"}')"
$ PATCH="{\"spec\":{\"upstream\":\"${POLICY_ENGINE_GRAPH_URI}\"}}"

$ oc patch clusterversion version -p $PATCH --type merge

$ oc get clusterversion -o json|jq ".items[0].spec"
{
  "channel": "stable-4.9",
  "clusterID": "25b57f9f-ca4c-444f-9f77-1fc742cd3eed",
  "upstream": "http://update-service-oc-mirror-policy-engine-openshift-update-service.apps.ocp4.example.com/api/upgrades_info/v1/graph"
}
~~~

### 7. Upgrade ocp
~~~
- Current version:
$ oc get clusterversion
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.9.15    True        False         2d9h    Cluster version is 4.9.15

$ oc adm upgrade
Cluster version is 4.9.15
Upstream: http://update-service-oc-mirror-policy-engine-openshift-update-service.apps.ocp4.example.com/api/upgrades_info/v1/graph
Channel: stable-4.9 (available channels: candidate-4.10, candidate-4.9, fast-4.10, fast-4.9, stable-4.10, stable-4.9)
Recommended updates:
  VERSION     IMAGE
  4.9.40      docker.registry.example.com:5000/openshift/release-images@sha256:ed3b2eac54ea3406e516b08cbb4f0c488bf47f9200664239bdc266bc29ac7cca

$ oc patch clusterversion version --type merge -p '{"spec": {"channel": "stable-4.10"}}'

$ oc adm upgrade
Cluster version is 4.9.15
Upstream: http://update-service-oc-mirror-policy-engine-openshift-update-service.apps.ocp4.example.com/api/upgrades_info/v1/graph
Channel: stable-4.10 (available channels: candidate-4.10, candidate-4.9, fast-4.10, fast-4.9, stable-4.10, stable-4.9)
Recommended updates:
  VERSION     IMAGE
  4.9.40      docker.registry.example.com:5000/openshift/release-images@sha256:ed3b2eac54ea3406e516b08cbb4f0c488bf47f9200664239bdc266bc29ac7cca

# oc get co | grep -v '.True.*False.*False'

# Web console -> Administrator -> Administration -> Cluster Settings -> Details -> Update -> Select new version -> 4.9.40 -> Update

- Successfully upgraded to version 4.9.40(intermediate version).
$ oc get clusterversion
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.9.40    True        False         5m55s   Cluster version is 4.9.40

- After upgrading to version 4.9.40(intermediate version), the upgrade path for version 4.10.20(Desired version) is displayed as expected.
$ oc adm upgrade
Cluster version is 4.9.40
Upstream: http://update-service-oc-mirror-policy-engine-openshift-update-service.apps.ocp4.example.com/api/upgrades_info/v1/graph
Channel: stable-4.10 (available channels: candidate-4.10, candidate-4.9, eus-4.10, fast-4.10, fast-4.9, stable-4.10, stable-4.9)
Recommended updates:
  VERSION     IMAGE
  4.10.20     docker.registry.example.com:5000/openshift/release-images@sha256:b89ada9261a1b257012469e90d7d4839d0d2f99654f5ce76394fa3f06522b600

# Web console -> Administrator -> Administration -> Cluster Settings -> Details -> Update -> Select new version -> 4.10.20 -> Update

- Successfully upgraded to version 4.10.20(Desired version)version.
$ oc get clusterversion
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.10.20   True        False         18m     Cluster version is 4.10.20

$ oc get co | grep -v '.True.*False.*False'
~~~


### ImageSetConfiguration template
~~~
$ skopeo copy -a docker://quay.io/openshift-release-dev/ocp-release:4.10.20-x86_64 \
         docker://docker.registry.example.com:5000/ocp4/openshift4-release-images:4.10.20-x86_64

$ cat << EOF > ./imageset-config.yaml
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
storageConfig:
  registry:
    imageURL: docker.registry.example.com:5000/ocp/metadata-1
    skipTLS: false
mirror:
  platform:
    architectures:
      - amd64
    channels:
      - name: stable-4.10
        minVersion: 4.10.25
        maxVersion: 4.10.25
EOF

$ oc mirror --config=./imageset-config.yaml \
            docker://docker.registry.example.com:5000/ocp4/openshift41025

$ skopeo copy -a docker://quay.io/openshift-release-dev/ocp-release:4.10.20-x86_64 \
         docker://docker.registry.example.com:5000/ocp4/openshift4-release-images:4.10.20-x86_64

$ cat << EOF > ./imageset-config.yaml
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
storageConfig:
  registry:
    imageURL: docker.registry.example.com:5000/ocp/metadata-2
    skipTLS: false
mirror:
  platform:
    channels:
      - name: stable-4.10
        minVersion: 4.10.30
        maxVersion: 4.10.30
EOF

$ oc mirror --config=./imageset-config.yaml \
            docker://docker.registry.example.com:5000/ocp4/openshift41030
~~~            
