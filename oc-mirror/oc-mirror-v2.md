## Mirror an image set in a full disconnected environment using the oc-mirror plugin


### Installing the oc-mirror plug-in
* Installing the oc-mirror plug-in
  ```
  curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz
  tar -xzf oc-mirror.tar.gz -C /usr/local/bin/
  chmod +x /usr/local/bin/oc-mirror
  ```

### Disabling the default OperatorHub sources
* Disabling the default OperatorHub sources
  ```
  oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
  ```

### Configuring credentials that allow images to be mirrored

* Download [pull-secret](https://console.redhat.com/openshift/install/pull-secret)
  
* Save the file either as ~/.docker/config.json or $XDG_RUNTIME_DIR/containers/auth.json
  ```
  cat ./pull-secret | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json
  ```

### Get operator information

* Find the available catalogs for the target version
  ```
  oc-mirror list operators --catalogs --version=4.18
  ```

* Find the available packages within the selected catalog
  ```
  oc-mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.18
  ```

* Find channels for the selected package
  ```
  oc-mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.18 --package=cluster-logging
  ```

* Find package versions within the selected channel
  ```
  oc-mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.18 --package=cluster-logging --channel=stable-6.1
  ```


### Creating the image set configuration

* Creating the image set configuration

  ```
  cat > isc.yaml << EOF
  kind: ImageSetConfiguration
  apiVersion: mirror.openshift.io/v2alpha1
  mirror:
    platform:
      channels:
      - name: stable-4.18
        minVersion: 4.18.2
        maxVersion: 4.18.2
      graph: true
    operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.18
      packages:
      - name: openshift-pipelines-operator-rh
        minVersion: '1.18.0'
        maxVersion: '1.18.0'
      - name: openshift-gitops-operator
        minVersion: 1.16.0
        maxVersion: 1.16.0
  EOF
  ```
### Optional A: Mirroring an image set in a fully disconnected environment
* Mirroring from mirror to disk(Environment with Internet access) 
  ```
  MIRROR_RESOURCES_DIR=./olm
  mkdir ${MIRROR_RESOURCES_DIR}
  oc-mirror -c isc.yaml file://${MIRROR_RESOURCES_DIR} --v2
  ```

* Migrate the mirror file and isc.yaml file to a fully disconnected environment

* Mirroring from disk to regitry(fully disconnected environment)
  ```
  MIRROR_RESOURCES_DIR=./olm
  MIRROR_REGISTRY=mirror.registry.example.com:8443
  podman login -u admin -p password ${MIRROR_REGISTRY}

  ls ${MIRROR_RESOURCES_DIR}
  mirror_000001.tar  working-dir

  oc-mirror -c isc.yaml --from file://${MIRROR_RESOURCES_DIR} docker://${MIRROR_REGISTRY} --v2 --dest-tls-verify=false
  ```

### Optional B: Mirroring an image set in a partially disconnected environment

* Add local Image Registry credentials to the pull-secret
  ```
  MIRROR_REGISTRY=mirror.registry.example.com:8443
  podman login -u admin -p password ${MIRROR_REGISTRY}
  podman login -u admin -p password --authfile ./pull-secret ${MIRROR_REGISTRY}
  cat ./pull-secret | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json
  ```

* Mirror image sets to a registry
  ```
  MIRROR_RESOURCES_DIR=./olm
  mkdir ${MIRROR_RESOURCES_DIR}
  oc-mirror -c isc.yaml --workspace file://olm docker://${MIRROR_REGISTRY} --v2 --dest-tls-verify=false
  ```
  
### Create IDMS, ITMS, CatalogSource, and Signature ConfigMap

* Create IDMS, ITMS and catalogsource
  ```
  ls ${MIRROR_RESOURCES_DIR}/working-dir/cluster-resources/
  cc-redhat-operator-index-v4-18.yaml  cs-redhat-operator-index-v4-18.yaml  idms-oc-mirror.yaml

  oc create -f ${MIRROR_RESOURCES_DIR}/working-dir/cluster-resources/idms-oc-mirror.yaml
  oc create -f ${MIRROR_RESOURCES_DIR}/working-dir/cluster-resources/cs-redhat-operator-index-v4-18.yaml

  # Generated if at least one image from the image set is mirrored by tag, Please note that MCO drains the nodes for ImageTagMirrorSet objects
  oc create -f ${MIRROR_RESOURCES_DIR}/working-dir/cluster-resources/itms-oc-mirror.yaml  

  oc get catalogsource -n openshift-marketplace
  NAME                             DISPLAY   TYPE   PUBLISHER   AGE
  cs-redhat-operator-index-v4-18             grpc               3m19s

  oc get packagemanifest -n openshift-marketplace
  NAME                              CATALOG   AGE
  openshift-pipelines-operator-rh             3m45s
  ···
  ```
* If release images are mirrored, create a signature-configmap and itms ITMS
  ```
  oc create -f ${MIRROR_RESOURCES_DIR}/working-dir/cluster-resources/signature-configmap.yaml

  # Please note that MCO drains the nodes for ImageTagMirrorSet objects
  oc create -f ${MIRROR_RESOURCES_DIR}/working-dir/cluster-resources/itms-oc-mirror.yaml  
  ```

### Deleting images from a disconnected environment 

* Create a disc.yaml file and include the following content
  ```
  cat > disc.yaml << EOF
  apiVersion: mirror.openshift.io/v2alpha1
  kind: DeleteImageSetConfiguration
  delete:
    operators:
      - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.18
        packages:
        - name: openshift-pipelines-operator-rh
          minVersion: '1.18.0'
          maxVersion: '1.18.0'
  EOF
  ```
* Create a delete-images.yaml file by running the following command
  ```
  MIRROR_RESOURCES_DIR=./olm
  MIRROR_REGISTRY=mirror.registry.example.com:8443
  
  oc-mirror delete --config disc.yaml --workspace file://${MIRROR_RESOURCES_DIR} --v2 --generate docker://${MIRROR_REGISTRY} --dest-tls-verify=false
  ```
* Verify that the delete-images.yaml file has been generated
  ```
  ls ${MIRROR_RESOURCES_DIR}/working-dir/delete
  delete-imageset-config.yaml  delete-images.yaml
  ```
* After generate the delete-images YAML file, delete the images from the remote registry by running the following command
  ```
  oc-mirror delete --v2 --delete-yaml-file ${MIRROR_RESOURCES_DIR}/working-dir/delete/delete-images.yaml docker://${MIRROR_REGISTRY} --dest-tls-verify=false
  ```
