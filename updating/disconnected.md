## Upgrading the cluster while disconnected from the network

### Use the oc-mirror plug-in to download the release mirror

* Installing the oc-mirror plug-in.
  ```
  curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz
  tar -xvf oc-mirror.tar.gz
  chmod +x ./oc-mirror
  sudo mv ./oc-mirror /usr/local/bin/
  ```
* Download [pull-secret](https://console.redhat.com/openshift/install/pull-secret)

* Add local registry credentials to the pull-secret
  ```
  export LOCAL_REGISTRY=mirror.registry.example.com:8443
  podman login ${LOCAL_REGISTRY}
  podman login --authfile /root/pull-secret ${LOCAL_REGISTRY}
  ```

* Save the file either as ~/.docker/config.json or $XDG_RUNTIME_DIR/containers/auth.json
  ```
  cat /root/pull-secret | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json
  ```
  
* Find OCP releases by major/minor version
  ```
  oc-mirror list releases --version=4.11
  ```

* Creating the image set configuration
  ```
  cat > imageset-config.yaml << EOF
  apiVersion: mirror.openshift.io/v1alpha2
  kind: ImageSetConfiguration
  storageConfig:
   registry:
     imageURL: ${LOCAL_REGISTRY}/mirror/metadata
  mirror:
    platform:
      channels:
        - name: stable-4.11
          minVersion: 4.10.20     # Current version
          maxVersion: 4.11.53     # Updated target version
          shortestPath: true      # Mirror only the shortest upgrade path，For example: setting minVersion 4.9.12/maxVersion 4.10.31 will mirror intermediate version 4.9.47
   #operators:                    # Can mirror both ocp release image and specific operator
   #- catalog: registry.redhat.io/redhat/redhat-operator-index:v4.10
   #  packages:
   #  ···
  EOF
  ```

* Mirroring an image set to a mirror registry.
  ```
  oc mirror --config=./imageset-config.yaml docker://${LOCAL_REGISTRY} --dest-skip-tls
  ```

* Create release-signatures and image-content-source-policy
  ```
  ls oc-mirror-workspace/results-1701860336
  catalogSource-redhat-operator-index.yaml  charts  imageContentSourcePolicy.yaml  mapping.txt  release-signatures

  oc create -f imageContentSourcePolicy.yaml
  oc create -f release-signatures/
  ```

* If the operator is mirrored, create the catalogsource
  ```
  oc create -f catalogSource-redhat-operator-index.yaml
  ```

* Verify OCP releases image
  ```
  podman search ${LOCAL_REGISTRY}/openshift/release-images \
    --list-tags --limit=1000 --tls-verify=false --authfile /root/pull-secret
  NAME                                                       TAG
  mirror.registry.example.com:8443/openshift/release-images  4.10.20-x86_64
  mirror.registry.example.com:8443/openshift/release-images  4.11.53-x86_64
  ```

### Upgrading a cluster in a disconnected environment without the OpenShift Update Service
  
* Pausing a MachineHealthCheck resource
  ```
  oc get machinehealthcheck -n openshift-machine-api
  NAME                              MAXUNHEALTHY   EXPECTEDMACHINES   CURRENTHEALTHY
  machine-api-termination-handler   100% 

  oc -n openshift-machine-api annotate mhc machine-api-termination-handler cluster.x-k8s.io/paused=""
  ```

* Change upgrade channel
  ```
  oc patch clusterversion version --type merge -p '{"spec": {"channel": "stable-4.11"}}'
  ```

* Retrieve release image digests
  ```
  export LOCAL_REGISTRY=${LOCAL_REGISTRY}
  export LOCAL_REPOSITORY='openshift/release-images'
  export OCP_RELEASE_VERSION='4.11.53'
  export ARCHITECTURE='x86_64'
  export RELEASE_DIGEST=$(oc adm release info -o 'jsonpath={.digest}{"\n"}' quay.io/openshift-release-dev/ocp-release:${OCP_RELEASE_VERSION}-${ARCHITECTURE})
  ```

* Upgrade disconnected clusters
  ```
  oc adm upgrade --allow-explicit-upgrade \
     --to-image quay.io/openshift-release-dev/ocp-release@${RELEASE_DIGEST}
  
  oc get pod,job -n openshift-cluster-version
  NAME                                            READY   STATUS     RESTARTS   AGE
  pod/cluster-version-operator-7444474bc4-jmkms   1/1     Running    11         252d
  pod/version--mt47x-lwmgs                        0/1     Init:3/4   0          34s

  NAME                       COMPLETIONS   DURATION   AGE
  job.batch/version--mt47x   0/1           34s        34s
  ```
  
* Wait for the OCP cluster upgrade to complete and check the status
  ```
  oc get clusterversion
  NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
  version   4.10.20   True        True          2m58s   Working towards 4.11.53: 104 of 806 done (12% complete)

  oc get clusterversion
  NAME      VERSION   AVAILABLE   PROGRESSING   SINCE   STATUS
  version   4.11.53   True        False         112m    Cluster version is 4.11.53

  oc get nodes |grep -v Ready

  oc get co | grep -v '.True.*False.*False' 

  oc get pods -A | egrep -v 'Running|Completed'
  ```

* OCP cluster upgrade completes restore machine health check
  ```
  oc -n openshift-machine-api annotate mhc <mhc-name> cluster.x-k8s.io/paused-
  ```
