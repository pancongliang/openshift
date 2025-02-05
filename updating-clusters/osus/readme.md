## Use OSUS Upgrade The Cluster

### Environment
~~~
- Current version:
$ oc get clusterversion
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.14.20   True        False         4d21h   Cluster version is 4.14.20

- Desired version: 4.15.20
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
  mirror.registry.example.com..8443: |  # 	If the registry has the port, such as registry-with-port.example.com:5000, : should be replaced with ...
    -----BEGIN CERTIFICATE-----
    ···
    -----END CERTIFICATE-----
~~~


### 2.Optional: Updating the global cluster pull secret
- The procedure is required when users use a separate registry to store images than the registry used during installation.
~~~
$ podman login --authfile /root/pull-secret.txt mirror.registry.example.com:8443
$ oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret
~~~


### 3.Installing the OpenShift Update Service Operator
~~~
export CHANNEL_NAME="v1"
export CATALOG_SOURCE_NAME="redhat-operators"
export NAMESPACE="rhacs-operator"
curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/updating-clusters/osus/01-operator.yaml | envsubst | oc create -f -
curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash

$ oc get po -n openshift-update-service
~~~


### 4.Use the oc-mirror tool to mirror ocp image
~~~
- Install oc-mirror tool:
$ sudo curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz
$ sudo tar -xvf oc-mirror.tar.gz
$ sudo chmod +x oc-mirror && sudo mv ./oc-mirror /usr/local/bin/.

- Configuring credentials that allow images to be mirrored:
# Download pull-secret
$ podman login --authfile pull-secret mirror.registry.example.com:8443
$ cat /root/pull-secret | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json

- Creating the image set configuration[2][3]
$ cat << EOF > ./shortest-upgrade-imageset-configuration.yaml
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
storageConfig:
  registry:
    imageURL: mirror.registry.example.com:8443/mirror/metadata
    skipTLS: false
mirror:
  platform:
    channels:
    - name: stable-4.15
      minVersion: 4.14.20
      maxVersion: 4.15.20
      shortestPath: true
    graph: true
EOF

$ oc mirror --config=shortest-upgrade-imageset-configuration.yaml docker://mirror.registry.example.com:8443 --dest-skip-tls
···
Writing image mapping to oc-mirror-workspace/results-1738760238/mapping.txt
Writing UpdateService manifests to oc-mirror-workspace/results-1738760238
Writing ICSP manifests to oc-mirror-workspace/results-1738760238

$ ll oc-mirror-workspace/results-*
drwxr-xr-x. 2 root root     6 Feb  5 12:43 charts
-rwxr-xr-x. 1 root root   639 Feb  5 12:57 imageContentSourcePolicy.yaml
-rw-r--r--. 1 root root 79936 Feb  5 12:57 mapping.txt
drwxr-xr-x. 2 root root    98 Feb  5 12:43 release-signatures
-rwxr-xr-x. 1 root root   349 Feb  5 12:57 updateService.yaml

$ oc create -f oc-mirror-workspace/results-*/imageContentSourcePolicy.yaml 
~~~

### 5. Creating an OpenShift Update Service application
~~~
- Use the updateService.yaml file automatically generated in step 4
$ cat oc-mirror-workspace/results-*/updateService.yaml 
apiVersion: updateservice.operator.openshift.io/v1
kind: UpdateService
metadata:
  name: update-service-oc-mirror
spec:
  graphDataImage: mirror.registry.example.com:8443/openshift/graph-image@sha256:850b59438f7cdd120b6c3a394bf60f494e0a832edc4ece343c3ac9f4a29d1913
  releases: mirror.registry.example.com:8443/openshift/release-images
  replicas: 2

$ oc create -f oc-mirror-workspace/results-*/updateService.yaml -n openshift-update-service

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
