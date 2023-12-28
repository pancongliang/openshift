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
  ACS Console Platform → Configuration → Integrations → Cluster Init Bundle → Generate bundle → <cluster_init_bundle.yaml> → Generate → Download Kubernetes Secret File
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

### Authenticating by using the roxctl CLI
* Installing the roxctl CLI
  ```
  arch="$(uname -m | sed "s/x86_64//")"; arch="${arch:+-$arch}"
  curl -f -o roxctl "https://mirror.openshift.com/pub/rhacs/assets/4.3.1/bin/Linux/roxctl${arch}"
  chmod +x roxctl
  mv ./roxctl /usr/local/bin/
  ```
  
* Creating an API token

  (ACS Console → Platform Configuration → Integrations → Authentication Tokens → API Token → <Admin> → Generate Token)
  ```
  export ROX_API_TOKEN=eyJhbGciOiJSUzI1NiIsImtpZCI6Imp3dGswIiwidHlwIjoiSldUIn0.eyJhdWQiOlsiaHR0cHM6Ly9zdGFja3JveC5pby9qd3Qtc291cmNlcyNhcGktdG9rZW5zIl0sImV4cCI6MTczNTMyMDU1NywiaWF0IjoxNzAzNzg0NTU3LCJpc3MiOiJodHRwczovL3N0YWNrcm94LmlvL2p3dCIsImp0aSI6Ijk0NTZmMTExLWM0NDAtNDRhMi04YTNiLTQ1OTFiYTM4MGZkOSIsIm5hbWUiOiJhZG1pbiIsInJvbGVzIjpbIkFkbWluIl19.KPxFW6VEnkqA9KEjjQJ1_9BuXZVGlfZfVtBdJCJWQuxgIO4WUQdcsT3Qz1R4AdO1wZANrcTObhZ-OFKXnYDjCh_O6PoY3_40rfsfTum-2p771tr0SpTLv9hXcCJcs1xiY7okQFwVyk6LXHZYHCqAJs-BhlcwLHPJiYQn1PTm2bBIoLDMDdRe0d2lpMyVKXtU8bfnNreaHQPesU1sH5wPcEQo9ESQ1azLVtUl7GdeR-E2CrVl3pK6NlmhSZfI7dirQRJjdQZd6x9bh0Y6LbRxEoUgaX-SzHFh-UHWrl2oQ4FD7CrjjrHl1OWXlh2SWMVVR5pq5pTIY61VTX2NmAJcMD0jtU4N5hv2qcjtvAoJgRw8l5D7ZcU-SOWhqw846OMWcLUs33x3EHyu1f6wcub2TPEpHQpq1YWoZbJyYbqv5YzmqiKBScz2u5TC7qhrUlKAUc7s77QDlWkCip8oKrmK60JFWbo3yCOMtEkKuQ5R2A7RZBxAirYGTmgnXlOXgilbGZfYSH6F_FJ7xdtJJD7JdWXDSZpaON2xehM0JSqnIDv1hc-uG8iVd1nCi405Ui106oFSXyIHkEE0av160lE33jIEqAPO80VTuHzCF2gyFKHjokRSUsX698nFLUpn4y33ZljYClP9rYB5CE38whaJIduXnEzLi1ARv_2Ee4VxvNA
  ```

* Get CENTRAL_ADDRESS/ENDPOINT
  ```
  export ROX_ENDPOINT=$(oc get route central -n stackrox -o jsonpath='{.spec.host}'):443
  export ROX_CENTRAL_ADDRESS=$(oc get route central -n stackrox -o jsonpath='{.spec.host}'):443
  ```

roxctl central login


### Updating Scanner definitions in offline mode

* Downloading [Scanner]( https://install.stackrox.io/scanner/scanner-vuln-updates.zip t) definitions

* Uploading definitions to Central by using an API token
  ```
  roxctl scanner upload-db \
     -e "$ROX_CENTRAL_ADDRESS" \
     --scanner-db-file=<compressed_scanner_definitions.zip>
  ```
### Updating kernel support packages in offline mode

* Downloading [kernel support packages](https://install.stackrox.io/collector/support-packages/index.html)

* Uploading kernel support packages to Central
  ```
   roxctl collector support-packages upload <package_file> \
  -e "$ROX_CENTRAL_ADDRESS"
  ```
