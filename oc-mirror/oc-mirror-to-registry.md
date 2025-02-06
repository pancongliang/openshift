## Mirror image sets in partially disconnected environments using the oc-mirror plugin


### Installing the oc-mirror plug-in
* Installing the [oc-mirror plug-in](https://docs.openshift.com/container-platform/4.11/installing/disconnected_install/installing-mirroring-disconnected.html#installation-oc-mirror-installing-plugin_installing-mirroring-disconnected).
  ```
  curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz
  tar -xvf oc-mirror.tar.gz
  chmod +x ./oc-mirror
  sudo mv ./oc-mirror /usr/local/bin/
  ```

### Disabling the default OperatorHub sources
* Disabling the default OperatorHub sources
  ```
  oc patch OperatorHub cluster --type json \
     -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
  ```

### Get [operator information](https://cloud.redhat.com/blog/how-oc-mirror-will-help-you-reduce-container-management-complexity).

* Login OperatorHub catalog
  ```
  podman login registry.redhat.io
  ```
  
* Find OCP releases by major/minor version:
  ```
  oc-mirror list releases --version=4.11
  ```
  
* Find the available catalogs for the target version
  ```
  oc-mirror list operators --catalogs --version=4.11
  ```

* Find the available packages within the selected catalog
  ```
  oc-mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.11
  ```

* Find channels for the selected package
  ```
  oc-mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.11 --package=cluster-logging

  or

  for i in cluster-logging elasticsearch-operator ; do oc-mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.11 --package=$i; done
  ```

* Find package versions within the selected channel
  ```
  oc-mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.11 --package=elasticsearch-operator --channel=stable-5.5
  ```

### [Configuring credentials](https://docs.openshift.com/container-platform/4.11/installing/disconnected_install/installing-mirroring-disconnected.html#installation-adding-registry-pull-secret_installing-mirroring-disconnected) that allow images to be mirrored.

* Download pull-secret(https://console.redhat.com/openshift/install/pull-secret)

* Add local Image Registry credentials to the pull-secret
  ```
  export LOCAL_REGISTRY=mirror.registry.example.com:8443
  podman login ${LOCAL_REGISTRY}
  podman login --authfile /root/pull-secret ${LOCAL_REGISTRY}
  ```
* Save the file either as ~/.docker/config.json or $XDG_RUNTIME_DIR/containers/auth.json
  ```
  cat /root/pull-secret | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json
  ```

* Creating the [image set configuration](https://docs.openshift.com/container-platform/4.11/installing/disconnected_install/installing-mirroring-disconnected.html#oc-mirror-imageset-config-params_installing-mirroring-disconnected)

  > Note that when running the oc-mirror plugin again, images are [pruned](https://docs.openshift.com/container-platform/4.11/installing/disconnected_install/installing-mirroring-disconnected.html#oc-mirror-updating-registry-about_installing-mirroring-disconnected) automatically from the target mirror registry if they are no longer included in the latest `ImageSetConfiguration` that was generated and mirrored.
  
  > In addition, if update the currently installed operator version, need to include the current version and the target version in `ImageSetConfiguration`, otherwise the operator will fail to update. And it is necessary to additionally update the index image address in the current `catalogsource` to display the new version of the operator.

  ```
  cat > imageset-config.yaml << EOF
  apiVersion: mirror.openshift.io/v1alpha2
  kind: ImageSetConfiguration
  storageConfig:
   registry:
     imageURL: ${LOCAL_REGISTRY}/mirror/metadata
     skipTLS: false
  mirror:
    platform:
      channels:
        - name: stable-4.10
          minVersion: 4.10.67
          maxVersion: 4.10.67
    operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.10
      packages:
        - name: cluster-logging
          channels:
            - name: 'stable-5.6'
              minVersion: '5.6.11'
              maxVersion: '5.6.11'
        - name: elasticsearch-operator
          channels:
            - name: 'stable-5.6'
              minVersion: '5.6.11'
              maxVersion: '5.6.11'
        - name: sriov-network-operator
          channels:
            - name: 'stable'
              minVersion: '4.10.0-202308261301'
              maxVersion: '4.10.0-202308261301'
        - name: kubernetes-nmstate-operator
          channels:
            - name: 'stable'
              minVersion: '4.10.0-202308260023'
              maxVersion: '4.10.0-202308260023'
        - name: performance-addon-operator
          channels:
            - name: '4.10'
              minVersion: '4.10.13'
              maxVersion: '4.10.13'
        - name: servicemeshoperator
          channels:
            - name: 'stable'
              minVersion: '2.4.3-0'
              maxVersion: '2.4.3-0'
  EOF
  ```

* [Mirroring](https://docs.openshift.com/container-platform/4.11/installing/disconnected_install/installing-mirroring-disconnected.html#mirroring-image-set-partial) an image set to a mirror registry.
  ```
  oc mirror --config=./imageset-config.yaml \
            docker://${LOCAL_REGISTRY} --dest-skip-tls
  ···
  info: Mirroring completed in 1m57.76s (40.22MB/s)
  Rendering catalog image "mirror.registry.example.com:8443/redhat/redhat-operator-index:v4.11" with file-based catalog 
  Writing image mapping to oc-mirror-workspace/results-1670920047/mapping.txt
  Writing CatalogSource manifests to oc-mirror-workspace/results-1670920047
  Writing ICSP manifests to oc-mirror-workspace/results-1670920047     #<-- This path is used in subsequent steps to create icsp and catalogsource
  ```

* Create icsp and catalogsource
  > If adding or updating an operator, need to create the `icsp` and then modify the current environment.
  ```
  ls oc-mirror-workspace/results-1670920047
  catalogSource-redhat-operator-index.yaml  charts  imageContentSourcePolicy.yaml  mapping.txt  release-signatures

  oc create -f imageContentSourcePolicy.yaml
  imagecontentsourcepolicy.operator.openshift.io/operator-0 created

  oc create -f catalogSource-redhat-operator-index.yaml
  catalogsource.operators.coreos.com/redhat-operator-index create
  ```

* If mirror the ocp release image and prepare to upgrade the ocp version, create a `release-signature`
  ```
  oc create -f release-signatures/
  ```
* Verify that the operator download is complete
  ```
  oc get catalogsource -n openshift-marketplace
  NAME                      DISPLAY   TYPE   PUBLISHER   AGE
  redhat-operator-index               grpc               13s

  oc get packagemanifest -n openshift-marketplace
  NAME                          CATALOG   AGE
  servicemeshoperator                     27m
  sriov-network-operator                  27m
  elasticsearch-operator                  27m
  performance-addon-operator              27m
  kubernetes-nmstate-operator             27m
  cluster-logging                         27m
  ```
* Verify OCP releases image
  ```
  podman search ${LOCAL_REGISTRY}/openshift/release-images \
    --list-tags --limit=1000 --tls-verify=false --authfile /root/pull-secret
  NAME                                                       TAG
  mirror.registry.example.com:8443/openshift/release-images  4.10.67-x86_64
  ```

### Mirroring an image set in a fully disconnected environment
* If it is a completely disconnected environment, `storageConfig.local.path` needs to be set instead of `storageConfig.registry.imageURL` to [mirror the image set to disk with the metadata, then mirror the image set file on disk to a mirror](https://docs.openshift.com/container-platform/4.11/installing/disconnected_install/installing-mirroring-disconnected.html#mirroring-image-set-full).
  ```
  apiVersion: mirror.openshift.io/v1alpha2
  kind: ImageSetConfiguration
  storageConfig:
   registry:                 
     imageURL: ${LOCAL_REGISTRY}/mirror/metadata
  ```
* Change to
  ```
  apiVersion: mirror.openshift.io/v1alpha2
  kind: ImageSetConfiguration
  storageConfig:
    local:
      path: /home/user/metadata   #<-- Do not delete or modify metadata generated by the oc-mirror plugin, use the same storage backend every time run the oc-mirror plugin for the same mirror registry.
  ```


### Additional error message:
* When upgrading the operator, if `ImageSetConfiguration` or ocp cannot recognize the `current and target` versions of the operator image, the following error message will be prompted
  ```
  oc -n openshift-operator-lifecycle-manager logs $(oc get pods -n openshift-operator-lifecycle-manager -o name -l app=catalog-operator) | grep "ResolutionFailed"
  I1207 13:49:43.519060       1 event.go:285] Event(v1.ObjectReference{Kind:"Namespace", Namespace:"", Name:"openshift-logging", UID:"f83ad7d2-5712-483e-be1f-f7eb2fd529a5", APIVersion:"v1", ResourceVersion:"929603", FieldPath:""}): type: 'Warning' reason: 'ResolutionFailed' constraints not satisfiable: no operators found in channel stable-5.6 of package cluster-logging in the catalog referenced by subscription cluster-logging, subscription cluster-logging exists

  oc describe po -n openshift-operators-redhat elasticsearch-operator-c989b54f-fc4s2
  Warning  Failed          62m (x3 over 62m)      kubelet            Failed to pull image "registry.redhat.io/openshift-logging/elasticsearch-rhel8-operator@sha256:0372385bef8805cc2be2ccb119ed62e3d155382d4a9eb6d39090fe2b6fffce4f": rpc error: code = Unknown desc = unable to retrieve auth token: invalid username/password: unauthorized: Please login to the Red Hat Registry using your Customer Portal credentials. Further instructions can be found here: https://access.redhat.com/RegistryAuthentication
  Normal   BackOff         2m28s (x261 over 62m)  kubelet            Back-off pulling image "registry.redhat.io/openshift4/ose-kube-rbac-proxy@sha256:796753816645b35cd08da53d925df5e4fb12df8b2a14db98db361f0ff787a028
  ```
