## Replace registry

### Confirm current environment
```
$ oc get cm registry-config -n openshift-config -o yaml
apiVersion: v1
data:
  docker.registry.example.com..5000: |
    -----BEGIN CERTIFICATE-----
    MIIE7jCCAtagAwIBAgIUTEqQ/sV+Ll9TZzWS2TRopnUcsaswDQYJKoZIhvcNAQEL
    ···
    -----END CERTIFICATE-----

$ oc get cm user-ca-bundle -n openshift-config -o yaml > user-ca-bundle-cm.yaml
$ oc get cm user-ca-bundle -n openshift-config -o yaml
apiVersion: v1
data:
  ca-bundle.crt: |
    -----BEGIN CERTIFICATE-----
    MIIE7jCCAtagAwIBAgIUTEqQ/sV+Ll9TZzWS2TRopnUcsaswDQYJKoZIhvcNAQEL
    ···
    -----END CERTIFICATE-----


$ ssh core@master01.ocp4.example.com sudo cat /etc/pki/ca-trust/source/anchors/openshift-config-user-ca-bundle.crt
-----BEGIN CERTIFICATE-----
MIIE7jCCAtagAwIBAgIUTEqQ/sV+Ll9TZzWS2TRopnUcsaswDQYJKoZIhvcNAQEL
···
-----END CERTIFICATE-----

$ oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 -d 
{
        "auths": {
                "docker.registry.example.com:5000": {
                        "auth": "YWRtaW46cmVkaGF0"
                }
        }
}

$ oc get imagecontentsourcepolicies.operator.openshift.io -o yaml
apiVersion: v1
items:
- apiVersion: operator.openshift.io/v1alpha1
  kind: ImageContentSourcePolicy
  metadata:
    creationTimestamp: "2023-03-29T08:21:08Z"
    generation: 1
    name: image-policy-0
    resourceVersion: "1335"
    uid: dce0b0d1-900c-43b6-ab68-9a16a87334c9
  spec:
    repositoryDigestMirrors:
    - mirrors:
      - docker.registry.example.com:5000/ocp4/openshift4
      source: quay.io/openshift-release-dev/ocp-release
- apiVersion: operator.openshift.io/v1alpha1
  kind: ImageContentSourcePolicy
  metadata:
    creationTimestamp: "2023-03-29T08:21:08Z"
    generation: 1
    name: image-policy-1
    resourceVersion: "1337"
    uid: 1a0cc146-5643-4573-9253-c59c43944d84
  spec:
    repositoryDigestMirrors:
    - mirrors:
      - docker.registry.example.com:5000/ocp4/openshift4
      source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
- apiVersion: operator.openshift.io/v1alpha1
  kind: ImageContentSourcePolicy
  metadata:
    creationTimestamp: "2023-11-15T09:51:58Z"
    generation: 1
    name: ocp-4-11-41
    resourceVersion: "727426"
    uid: 924abc42-dabd-4549-b895-e0ff18422ade
  spec:
    repositoryDigestMirrors:
    - mirrors:
      - docker.registry.example.com:5000/ocp4/openshift4
      source: quay.io/openshift-release-dev/ocp-release
    - mirrors:
      - docker.registry.example.com:5000/ocp4/openshift4
      source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
- apiVersion: operator.openshift.io/v1alpha1
  kind: ImageContentSourcePolicy
  metadata:
    creationTimestamp: "2023-11-15T09:32:59Z"
    generation: 1
    labels:
      operators.openshift.org/catalog: "true"
    name: operator-0
    resourceVersion: "721067"
    uid: 5d3b79fa-b64e-46b1-8fc9-326f05f7e5fc
  spec:
    repositoryDigestMirrors:
    - mirrors:
      - docker.registry.example.com:5000/openshift-logging
      source: registry.redhat.io/openshift-logging
    - mirrors:
      - docker.registry.example.com:5000/openshift4
      source: registry.redhat.io/openshift4
    - mirrors:
      - docker.registry.example.com:5000/redhat
      source: registry.redhat.io/redhat
```

### Install new image registry, The following image registry uses port 8443 by default
```
export REGISTRY_DOMAIN_NAME="mirror.registry.example.com"
export REGISTRY_ID="root"
export REGISTRY_PW="password"                         # 8 characters or more
export REGISTRY_INSTALL_PATH="/opt/quay-install"
wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/registry/mirror-registry/deploy-mirror-registry.sh

source deploy-mirror-registry.sh
```

### Download the ocp installation image and create icsp
```
$ oc get clusterversion
NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
version   4.11.41   True        False         12m     Cluster version is 4.11.41

export OCP_RELEASE=4.11.41
export LOCAL_REGISTRY='mirror.registry.example.com:8443'
export LOCAL_REPOSITORY='ocp4/openshift4'
export PRODUCT_REPO='openshift-release-dev'
export LOCAL_SECRET_JSON='/root/pull-secret'
export RELEASE_NAME="ocp-release"
export ARCHITECTURE=x86_64

$ oc adm release mirror -a ${LOCAL_SECRET_JSON} --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE}
...

$ vim icsp.yaml
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: openshift-4-11-41
spec:
  repositoryDigestMirrors:
  - mirrors:
    - mirror.registry.example.com:8443/ocp4/openshift4
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - mirror.registry.example.com:8443/ocp4/openshift4
    source: quay.io/openshift-release-dev/ocp-v4.0-art-dev

$ oc create -f icsp.yaml
$ oc get imagecontentsourcepolicies
```

### Dowload operator image and create icsp

[How to use the oc-mirror plug-in to mirroring operators](https://access.redhat.com/solutions/6994677)
```
$ MIRROR_REGISTRY=mirror.registry.example.com:8443
$ cat /root/pull-secret | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json

cat > imageset-config.yaml << EOF
apiVersion: mirror.openshift.io/v1alpha2
kind: ImageSetConfiguration
storageConfig:
 registry:                 
   imageURL: ${MIRROR_REGISTRY}/mirror/metadata
   skipTLS: false
mirror:
  operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.11
      packages:
        - name: cluster-logging
          channels:
            - name: stable
            - name: stable-5.6
              minVersion: '5.6.5'
              maxVersion: '5.6.12'
        - name: elasticsearch-operator
          channels:
            - name: stable
            - name: stable-5.6
              minVersion: '5.6.5'
              maxVersion: '5.6.12'
EOF

$ oc mirror --config=./imageset-config.yaml \
            docker://${MIRROR_REGISTRY} --dest-skip-tls

$ oc create -f oc-mirror-workspace/results-1700069182/imageContentSourcePolicy.yaml
```

### Update pull-secret
```
$ podman login --authfile /root/offline-pull-secret mirror.registry.example.com:8443
$ cat offline-pull-secret 
{
        "auths": {
                "docker.registry.example.com:5000": {
                        "auth": "YWRtaW46cmVkaGF0"
                },
                "mirror.registry.example.com:8443": {
                        "auth": "YWRtaW46cmVkaGF0MTIz"
                }
        }
}

$ oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=/root/offline-pull-secret

#!/bin/bash
for Hostname in $(oc get nodes  -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
do
   echo "---  [$Hostname] ---"
   ssh -o StrictHostKeyChecking=no core@$Hostname sudo cat /var/lib/kubelet/config.json
   echo
done
```

### Create a configmap to add additional new image registry certificates.
```
$ oc create configmap registry-cas \
     --from-file=docker.registry.example.com..5000=/etc/pki/ca-trust/source/anchors/docker.registry.example.com.ca.crt \
     --from-file=mirror.registry.example.com..8443=/etc/pki/ca-trust/source/anchors/mirror.registry.example.com.ca.pem \
     -n openshift-config

$ oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}' --type=merge

#!/bin/bash
for Hostname in $(oc get nodes  -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
do
   echo "---  [$Hostname] ---"
   ssh -o StrictHostKeyChecking=no core@$Hostname sudo ls /etc/docker/certs.d/
   echo
done
```

### Update user-ca-bundle configmap certificate(Automatically reboot all nodes)
```
$ oc edit configmap user-ca-bundle -n openshift-config   # ca key update
apiVersion: v1
data:
  ca-bundle.crt: |
    -----BEGIN CERTIFICATE-----
    MIID2DCCAsCgAwIBAgIUeNsuwhcSKG8A/3iMfRC3TKwszPAwDQYJKoZIhvcNAQEL
    ...
    -----END CERTIFICATE-----

$ oc get proxy/cluster -o yaml   # Check whether user-ca-bundle is set in cluster proxy spec.trustedCA. If not set, set as below.
apiVersion: config.openshift.io/v1
kind: Proxy
...
spec:
  trustedCA:
    name: user-ca-bundle

$ oc patch proxy/cluster --type=merge --patch='{"spec":{"trustedCA":{"name":"user-ca-bundle"}}}'

$ oc get node
NAME                        STATUS                        ROLES    AGE    VERSION
master01.ocp4.example.com   Ready                         master   231d   v1.24.12+ceaf338
master02.ocp4.example.com   NotReady,SchedulingDisabled   master   231d   v1.24.12+ceaf338
master03.ocp4.example.com   Ready                         master   231d   v1.24.12+ceaf338
worker01.ocp4.example.com   Ready                         worker   231d   v1.24.12+ceaf338
worker02.ocp4.example.com   NotReady,SchedulingDisabled   worker   231d   v1.24.12+ceaf338

#!/bin/bash
for Hostname in $(oc get nodes  -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
do
   echo "---  [$Hostname] ---"
   ssh -o StrictHostKeyChecking=no core@$Hostname sudo cat /etc/pki/ca-trust/source/anchors/openshift-config-user-ca-bundle.crt
   echo 
done
```

7.Change the index image of catalogsource to the latest index image
```
$ cat oc-mirror-workspace/results-1700069182/catalogSource-redhat-operator-index.yaml |grep image
  image: mirror.registry.example.com:8443/redhat/redhat-operator-index:v4.11

$ oc edit catalogsource redhat-operator-index -n openshift-marketplace
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
...
spec:
  image: mirror.registry.example.com:8443/redhat/redhat-operator-index:v4.11  # update index image

```

###  TEST
#### Update openshift-logging test

Since the Operator version being used may be inconsistent with the Operator version just downloaded, the Operator needs to be updated.
Different operator upgrade methods may have some differences, so it is recommended to refer to the official documentation. The following example updates the openshift-logging version using the image provided by the new image registry
```
# Stop mirror-registry
$ systemctl stop mirror-registry
$ podman login docker.registry.example.com:5000
Error: authenticating creds for "docker.registry.example.com:5000": pinging container registry docker.registry.example.com:5000: Get "https://docker.registry.example.com:5000/v2/": dial tcp 10.74.251.171:5000: connect: connection refused

$ oc get csv -n openshift-logging
NAME                            DISPLAY                            VERSION   REPLACES                        PHASE
cluster-logging.v5.6.5          Red Hat OpenShift Logging          5.6.5     cluster-logging.v5.6.4          Succeeded
elasticsearch-operator.v5.6.5   OpenShift Elasticsearch Operator   5.6.5     elasticsearch-operator.v5.6.4   Succeeded

1. OCP Console -> Operators -> Installed Operators -> Elasticsearch Operator -> update
2. OCP Console -> Operators -> Installed Operators -> Logging Operator -> update

$ oc get po -n openshift-logging
NAME                                            READY   STATUS      RESTARTS   AGE
cluster-logging-operator-555f8b85f6-whbn4       1/1     Running     0          82s
collector-68qq4                                 2/2     Running     0          61s
collector-7626j                                 2/2     Running     0          60s
collector-h8tvd                                 2/2     Running     0          53s
collector-n76j9                                 2/2     Running     0          52s
collector-v69l7                                 2/2     Running     0          51s
elasticsearch-cdm-37dl0rux-1-89d7dff6d-pnhc9    2/2     Running     0          4m38s
elasticsearch-cdm-37dl0rux-2-7d84c7b7bf-p44sb   2/2     Running     0          3m8s
elasticsearch-cdm-37dl0rux-3-7db54d5b8b-dsjmk   2/2     Running     0          2m2s
elasticsearch-im-app-28334520-wthtc             0/1     Completed   0          11m
elasticsearch-im-audit-28334520-4vskz           0/1     Completed   0          11m
elasticsearch-im-infra-28334520-xjkxj           0/1     Completed   0          11m
kibana-6f9844d4fd-trq5v                         2/2     Running     0          5m18s

$ oc get csv -n openshift-logging
NAME                             DISPLAY                            VERSION   REPLACES                        PHASE
cluster-logging.v5.6.12          Red Hat OpenShift Logging          5.6.12    cluster-logging.v5.6.5          Succeeded
elasticsearch-operator.v5.6.12   OpenShift Elasticsearch Operator   5.6.12    elasticsearch-operator.v5.6.5   Succeeded
```

#### Delete all images of the node and restart to test whether the ocp image can be pulled
```
$ ssh core@worker01.ocp4.example.com
[core@worker01 ~]$ sudo -i
[root@worker01 ~]# podman images
REPOSITORY                                                           TAG         IMAGE ID      CREATED        SIZE
REPOSITORY                                                            TAG         IMAGE ID      CREATED        SIZE
docker.registry.example.com:5000/redhat/redhat-operator-index         v4.11       8b8e0d11fee9  15 hours ago   2.1 GB
quay.io/minio/minio                                                   latest      603e753a418c  4 days ago     148 MB
registry.redhat.io/openshift-logging/cluster-logging-rhel8-operator   <none>      94129357d002  4 weeks ago    428 MB
registry.redhat.io/openshift-logging/log-file-metric-exporter-rhel8   <none>      b0bd51a61c13  4 weeks ago    228 MB
registry.redhat.io/openshift-logging/elasticsearch-proxy-rhel8        <none>      781f8b58d07f  4 weeks ago    267 MB
...
registry.redhat.io/openshift-logging/logging-curator5-rhel8           <none>      0c654bd523bd  7 months ago   907 MB
quay.io/openshift-release-dev/ocp-v4.0-art-dev                        <none>      d1e6e4eb5934  7 months ago   1.33 GB
quay.io/openshift-release-dev/ocp-v4.0-art-dev                        <none>      85a2587bfb79  7 months ago   449 MB

[root@worker01 ~]# podman rmi -f $(podman images --format "{{.ID}}")
[root@worker01 ~]# reboot

$ ssh core@worker01.ocp4.example.com sudo podman images
REPOSITORY                                                           TAG         IMAGE ID      CREATED       SIZE
quay.io/minio/minio                                                  latest      603e753a418c  4 days ago    148 MB
registry.redhat.io/openshift-logging/cluster-logging-rhel8-operator  <none>      94129357d002  4 weeks ago   428 MB
registry.redhat.io/openshift-logging/log-file-metric-exporter-rhel8  <none>      b0bd51a61c13  4 weeks ago   228 MB
registry.redhat.io/openshift-logging/elasticsearch-proxy-rhel8       <none>      781f8b58d07f  4 weeks ago   267 MB
registry.redhat.io/openshift-logging/elasticsearch6-rhel8            <none>      6f8baf91ff55  4 weeks ago   531 MB
registry.redhat.io/openshift-logging/logging-curator5-rhel8          <none>      1757b6c91a2e  4 weeks ago   915 MB
registry.redhat.io/openshift-logging/fluentd-rhel8                   <none>      002a3c2a5c19  5 weeks ago   241 MB
quay.io/openshift-release-dev/ocp-v4.0-art-dev                       <none>      356adaefbc87  6 months ago  526 MB
quay.io/openshift-release-dev/ocp-v4.0-art-dev                       <none>      6e6d8196efd5  6 months ago  670 MB

#!/bin/bash
for Hostname in $(oc get nodes  -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
do
   echo "reboot node $Hostname"
   ssh -o StrictHostKeyChecking=no core@$Hostname sudo shutdown -r -t 3 &> /dev/null
done
reboot node master01.ocp4.example.com
reboot node master02.ocp4.example.com
reboot node master03.ocp4.example.com
reboot node worker01.ocp4.example.com
reboot node worker02.ocp4.example.com

$ oc get po -A | grep -vE 'Running|Completed'
$ oc get co | grep -v '.True.*False.*False'
```

#### Delete/Add node text

```
$ oc delete node worker01
# Reinstall worker01 
$ oc get csr
NAME        AGE   SIGNERNAME                                    REQUESTOR                                                                   REQUESTEDDURATION   CONDITION
csr-bl2g2   3s    kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Pending

$ oc adm certificate approve csr-bl2g2
certificatesigningrequest.certificates.k8s.io/csr-bl2g2 approved

$ oc get csr
NAME        AGE   SIGNERNAME                                    REQUESTOR                                                                   REQUESTEDDURATION   CONDITION
csr-bl2g2   24s   kubernetes.io/kube-apiserver-client-kubelet   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   <none>              Approved,Issued
csr-cnl7b   4s    kubernetes.io/kubelet-serving                 system:node:worker02.ocp4.example.com                                       <none>              Pending

$ oc adm certificate approve csr-cnl7b
certificatesigningrequest.certificates.k8s.io/csr-cnl7b approved

$ oc get no
NAME                        STATUS   ROLES    AGE    VERSION
master01.ocp4.example.com   Ready    master   231d   v1.24.12+ceaf338
master02.ocp4.example.com   Ready    master   231d   v1.24.12+ceaf338
master03.ocp4.example.com   Ready    master   231d   v1.24.12+ceaf338
worker01.ocp4.example.com   Ready    worker   231d   v1.24.12+ceaf338
worker02.ocp4.example.com   Ready    worker   31m    v1.24.12+ceaf338
```
