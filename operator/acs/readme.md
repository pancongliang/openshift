### Install RHACS Operator

* Install the Operator using the default namespace
  ```
  export CHANNEL_NAME="stable"
  export CATALOG_SOURCE_NAME="redhat-operator-index"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/acs/01-operator.yaml | envsubst | oc create -f -

  oc patch installplan $(oc get ip -n rhacs-operator  -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n rhacs-operator --type merge --patch '{"spec":{"approved":true}}'

  oc get ip -n rhacs-operator
  ```

### Create Central instance
* Deploy [NFS Storage Class](https://github.com/pancongliang/openshift/blob/main/storage/nfs-storageclass/readme.md)

* Argo CD controls access to resources through RBAC policies set in the Argo CD instance. So first get the admin role for Argo CD
  ```
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/acs/02-central.yaml
  ```
* Get RHACS `admin` user login password and consle URL.
  ```
  oc get secret central-htpasswd -n stackrox -o go-template='{{index .data "password" | base64decode}}'
  OvMHL13iRq4XD15ILM1hAXb5X

  oc get route central -n stackrox
  NAME      HOST/PORT                                PATH   SERVICES   PORT    TERMINATION   WILDCARD
  central   central-stackrox.apps.ocp4.example.com          central    https   passthrough   None
  ```

### Add an OpenShift cluster to RHACS
* Get Authentication Token
  ```
  Platform Configuration → Integrations → Cluster Init Bundle → Generate bundle → <cluster_init_bundle.yaml> → Generate → Download Kubernetes Secret File
  ```
  
* Creating resources by using the init bundle
  ```
  oc apply -f cluster_init_bundle.yaml -n stackrox
  secret/collector-tls created
  secret/sensor-tls created
  secret/admission-control-tls created
  ```

### Installing secured cluster services
* Create Secured Cluster instance
  ```
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/acs/03-secured-cluster.yaml
  ```
* View deployed resources
  ```
  oc get po -n stackrox

  oc get deployment -n stackrox
  NAME                READY   UP-TO-DATE   AVAILABLE   AGE
  admission-control   3/3     3            3           13m
  central             1/1     1            1           70m
  central-db          1/1     1            1           70m
  scanner             2/2     2            2           70m
  scanner-db          1/1     1            1           70m
  sensor              1/1     1            1           13m

  oc get daemonsets.apps  -n stackrox
  NAME        DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
  collector   6         6         6       6            6           <none>          13m
  ```
