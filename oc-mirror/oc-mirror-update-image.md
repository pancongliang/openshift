## Update operators in partially disconnected environments using the oc-mirror plugin

### View the currently used operator and version before updating the image

* View catalogsource name
  ```
  $ oc get catalogsources -n openshift-marketplace
  NAME                    DISPLAY   TYPE   PUBLISHER   AGE
  redhat-operator-index             grpc               7m10s
  ```
* View the operator in the index image
  ```
  $ oc get catalogsources redhat-operator-index -n openshift-marketplace -o yaml |grep image
  image: docker.registry.example.com:5000/redhat/redhat-operator-index:v4.10
  ```
* View the operator in the index image
  ```
  $ oc-mirror list operators --catalog=docker.registry.example.com:5000/redhat/redhat-operator-index:v4.10
  NAME                        DISPLAY NAME                      DEFAULT CHANNEL
  cluster-logging             Red Hat OpenShift Logging         stable-5.6
  elasticsearch-operator      OpenShift Elasticsearch Operator  stable-5.6
  performance-addon-operator  Performance Addon Operator        4.10
  ```
* View the version of the operator in the index image
  ```
  $ oc-mirror list operators --catalog=docker.registry.example.com:5000/redhat/redhat-operator-index:v4.10 \
    --package=elasticsearch-operator --channel=stable-5.6
  VERSIONS
  5.6.2
  ```
* View packagemanifests
  ```
  $ oc get packagemanifests -n openshift-marketplace
  NAME                         CATALOG   AGE
  performance-addon-operator             8m26s
  elasticsearch-operator                 8m26s
  cluster-logging                        8m26s
  ```
* View subscription
  ```
  $ oc get subscription -A
  NAMESPACE                    NAME                     PACKAGE                  SOURCE                  CHANNEL
  openshift-logging            cluster-logging          cluster-logging          redhat-operator-index   stable-5.6
  openshift-operators-redhat   elasticsearch-operator   elasticsearch-operator   redhat-operator-index   stable-5.6
  ```
* View ClusterServiceVersion
  ```
  $ oc get csv -n openshift-logging
  NAME                            DISPLAY                            VERSION   REPLACES                        PHASE
  cluster-logging.v5.6.2          Red Hat OpenShift Logging          5.6.2     cluster-logging.v5.6.1          Succeeded
  elasticsearch-operator.v5.6.2   OpenShift Elasticsearch Operator   5.6.2     elasticsearch-operator.v5.6.1   Succeeded
  ```
* Change operator to manual upgrade
  ```
  $ oc describe subscriptions elasticsearch-operator -n openshift-operators-redhat | grep "Install Plan Approval"
  Install Plan Approval:  Manual

  $ oc describe subscriptions cluster-logging -n openshift-logging | grep "Install Plan Approval"
  Install Plan Approval:  Manual
  ```
* View ocp release images
  ```
  $ podman search docker.registry.example.com:5000/openshift/release-images \
    --list-tags --limit=1000 --tls-verify=false --authfile /root/pull-secret
  NAME                                                       TAG
  docker.registry.example.com:5000/openshift/release-images  4.10.20-x86_64
  ```
* Because the oc-mirror plugin updates (add/delete/update) based on metadata information, it is recommended that each update be based on the previous ImageSetConfiguration modification.
    The following is the previous ImageSetConfiguration, updating and deleting/adding images based on this file
  ```
  $ cat imageset-config.yaml
  apiVersion: mirror.openshift.io/v1alpha2
  kind: ImageSetConfiguration
  storageConfig:
   registry:
     imageURL: docker.registry.example.com:5000/mirror/metadata
     skipTLS: false
  mirror:
    platform:
      channels:
        - name: stable-4.10
          minVersion: 4.10.20
          maxVersion: 4.10.20
          shortestPath: true 
    operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.10
      packages:
        - name: cluster-logging
          channels:
            - name: 'stable-5.6'
              minVersion: '5.6.2'
              maxVersion: '5.6.2'
        - name: elasticsearch-operator
          channels:
            - name: 'stable-5.6'
              minVersion: '5.6.2'
              maxVersion: '5.6.2'
        - name: performance-addon-operator
          channels:
            - name: '4.10'
              minVersion: '4.10.13'
              maxVersion: '4.10.13'
  ```

### View available operator versions and ocp release images
* Login OperatorHub catalog
  ```
  $ podman login registry.redhat.io
  ```
  
* Find OCP releases by major/minor version:
  ```
  $ oc-mirror list releases --version=4.11
  ```
  
* Find the available catalogs for the target version
  ```
  $ oc-mirror list operators --catalogs --version=4.11
  ```

* Find the available packages within the selected catalog
  ```
  $ oc-mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.10
  ```

* Find channels for the selected package
  ```
  $ oc-mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.10 --package=cluster-logging
  ```

* Find package versions within the selected channel
  ```
  $ oc-mirror list operators --catalog=registry.redhat.io/redhat/redhat-operator-index:v4.10 --package=elasticsearch-operator --channel=stable-5.6
  ```

### [Configuring credentials](https://docs.openshift.com/container-platform/4.11/installing/disconnected_install/installing-mirroring-disconnected.html#installation-adding-registry-pull-secret_installing-mirroring-disconnected) that allow images to be mirrored.

* Download pull-secret(https://console.redhat.com/openshift/install/pull-secret)

* Add local Image Registry credentials to the pull-secret
  ```
  $ MIRROR_REGISTRY=docker.registry.example.com:5000
  $ podman login ${MIRROR_REGISTRY}
  $ podman login --authfile /root/pull-secret ${MIRROR_REGISTRY}
  ```
* Save the file either as ~/.docker/config.json or $XDG_RUNTIME_DIR/containers/auth.json
  ```
  $ cat /root/pull-secret | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json
  ```

### Update the [image set configuration](https://docs.openshift.com/container-platform/4.11/installing/disconnected_install/installing-mirroring-disconnected.html#oc-mirror-imageset-config-params_installing-mirroring-disconnected)

  Note that when running the oc-mirror plugin again, images are [pruned](https://docs.openshift.com/container-platform/4.11/installing/disconnected_install/installing-mirroring-disconnected.html#oc-mirror-updating-registry-about_installing-mirroring-disconnected) automatically from the target mirror registry if they are no longer included in the latest `image set` that was generated and mirrored. 

* The test is as follows:
  - Added kubernetes-nmstate-operator
  - Delete performance-addon-operator
  - Update cluster-logging, elasticsearch-operator, ocp release images version

  ```
  $ cat > imageset-config.yaml << EOF
  apiVersion: mirror.openshift.io/v1alpha2
  kind: ImageSetConfiguration
  storageConfig:
   registry:
     imageURL: ${MIRROR_REGISTRY}/mirror/metadata
     skipTLS: false
  mirror:
    platform:
      channels:
        - name: stable-4.10
          minVersion: 4.10.20
          maxVersion: 4.10.67
          shortestPath: true 
    operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.10
      packages:
        - name: cluster-logging
          channels:
            - name: 'stable-5.6'
              minVersion: '5.6.2'
              maxVersion: '5.6.9'
        - name: elasticsearch-operator
          channels:
            - name: 'stable-5.6'
              minVersion: '5.6.2'
              maxVersion: '5.6.9'
        - name: kubernetes-nmstate-operator
          channels:
            - name: 'stable'
              minVersion: '4.10.0-202308260023'
              maxVersion: '4.10.0-202308260023'
  EOF
  ```

* [Mirroring](https://docs.openshift.com/container-platform/4.11/installing/disconnected_install/installing-mirroring-disconnected.html#mirroring-image-set-partial) an image set to a mirror registry.
  ```
  $ oc mirror --config=./imageset-config.yaml \
            docker://${MIRROR_REGISTRY} --dest-skip-tls
  ···
  # Related images that have been deleted in ImageSetConfiguration will be deleted during the download process.
  Pruning 2 manifest(s) from repository openshift4/performance-addon-rhel8-operator
  Deleting manifest sha256:ca987da286d1029cf36a4105dd9ffc24f8aacae52ddd8dfad6435220cae613ea from repo openshift4/performance-addon-rhel8-operator
  ···
  Writing CatalogSource manifests to oc-mirror-workspace/results-1701230281
  Writing ICSP manifests to oc-mirror-workspace/results-1701230281     #<-- This path is used in subsequent steps to create icsp and catalogsource
  ```



* Create icsp and modify catalogsource index image
  ```
  $ ls oc-mirror-workspace/results-1701230281
  catalogSource-redhat-operator-index.yaml  charts  imageContentSourcePolicy.yaml  mapping.txt  release-signatures

  $ oc create -f oc-mirror-workspace/results-1701230281/imageContentSourcePolicy.yaml
  imagecontentsourcepolicy.operator.openshift.io/operator-0 created

  $ cat oc-mirror-workspace/results-1701230281/catalogSource-redhat-operator-index.yaml |grep image
    image: docker.registry.example.com:5000/redhat/redhat-operator-index:v4.10
  
  # The update operator cannot modify the catalog source name, otherwise you will not be able to see the updateable version.
  $ oc edit catalogsource redhat-operator-index -n openshift-marketplace
  spec:
    image: docker.registry.example.com:5000/redhat/redhat-operator-index:v4.10  # Modify to the latest index image address
    sourceType: grpc
  ```

* Verify that the operator download is complete
  ```
  $ oc get catalogsource -n openshift-marketplace
  NAME                      DISPLAY   TYPE   PUBLISHER   AGE
  redhat-operator-index               grpc               13s

  # If it does not appear as expected, restart the pod in the openshift-marketplace project
  $ oc get packagemanifest -n openshift-marketplace  
  NAME                          CATALOG   AGE
  kubernetes-nmstate-operator             111m
  elasticsearch-operator                  111m
  cluster-logging                         111m
  ```
* Verify OCP releases image
  ```
  $ podman search docker.registry.example.com:5000/openshift/release-images \
    --list-tags --limit=1000 --tls-verify=false --authfile /root/pull-secret
  docker.registry.example.com:5000/openshift/release-images  4.10.20-x86_64
  docker.registry.example.com:5000/openshift/release-images  4.10.67-x86_64
  ```

### Test upgrade openshift-logging

* View upgrade channel information
  ```
  $ oc-mirror list operators --catalog=docker.registry.example.com:5000/redhat/redhat-operator-index:v4.10 \
    --package=elasticsearch-operator --channel=stable-5.6
  VERSIONS
  5.6.2
  ··· 
  5.6.9
  ```

* Upgrade logging to 5.6.9
  ```
  $ oc get csv -n openshift-logging
  NAME                            DISPLAY                            VERSION   REPLACES                        PHASE
  cluster-logging.v5.6.9          Red Hat OpenShift Logging          5.6.9     cluster-logging.v5.6.2          Succeeded
  elasticsearch-operator.v5.6.9   OpenShift Elasticsearch Operator   5.6.9     elasticsearch-operator.v5.6.2   Succeeded
  
  $ oc get po -n openshift-logging
  NAME                                            READY   STATUS      RESTARTS   AGE
  cluster-logging-operator-d854cf5d7-777cs        1/1     Running     0          2m40s
  collector-889x9                                 2/2     Running     0          73s
  collector-96cbm                                 2/2     Running     0          70s
  collector-k42gj                                 2/2     Running     0          71s
  collector-p8cxd                                 2/2     Running     0          71s
  collector-pt9g2                                 2/2     Running     0          72s
  elasticsearch-cdm-jtylwj1f-1-76f666455d-cv48m   1/2     Running     0          108s
  elasticsearch-cdm-jtylwj1f-2-794dccf54c-bqzc7   1/2     Running     0          19s
  elasticsearch-cdm-jtylwj1f-3-54648899c5-rdp8h   1/2     Running     0          105m
  elasticsearch-im-app-28353885-2rlth             0/1     Completed   0          6m58s
  elasticsearch-im-audit-28353885-9qgws           0/1     Completed   0          6m58s
  elasticsearch-im-infra-28353885-v5rlh           0/1     Completed   0          6m58s
  kibana-5c5bd44bdf-29gbm                         2/2     Running     0          3m18s
  ```
