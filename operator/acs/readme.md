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

* Create `stackrox` project
  ```
  oc new-project stackrox
  ```
  
* Create Central instance
  ```
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/acs/02-central.yaml

  oc get pod -n stackrox
  NAME                          READY   STATUS    RESTARTS   AGE
  central-86bbb8b6f4-6hxrs      1/1     Running   0          8m26s
  central-db-c565695b5-d2z6t    1/1     Running   0          8m26s
  scanner-75cb7469c7-2jnpf      1/1     Running   0          8m26s
  scanner-75cb7469c7-fgdr5      1/1     Running   0          8m26s
  scanner-db-5f4cb65547-4lnwc   1/1     Running   0          8m26s

  oc get pvc -n stackrox
  NAME         STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
  central-db   Bound    pvc-fa047085-c172-4db0-be54-79b7efc53c87   100Gi      RWO            nfs-client     10m
  ```

### Get RHACS consle URL and `admin` user login password

* Get RHACS consle URL
  ```
  oc get route central -n stackrox -o jsonpath='{"https://"}{.spec.host}{"\n"}'
  ```
  
* Get `admin` user login password
  ```
  oc get secret central-htpasswd -n stackrox -o jsonpath='{.data.password}' | base64 -d; echo
  ```

### Single Sign-On with OpenShift

* Set Single Sign-On with OpenShift
  ```
  ACS Console Platform → Platform Configuration -> Access Control -> Create auth Provider -> OpenShift Auth

  Name: OpenShift
  Minium access role: Analyst/admin
  Rules: mapped spcific user to Admin role
  e.g.  <User=name  Value=admin  Role=Admin>
  ```  
* Logout and refresh your browser. OpenShift provider will be available for you to login with OpenShift's user account

### Add an OpenShift cluster to RHACS

* Get Authentication Token
  ```
  ACS Console Platform → Configuration → Integrations → Cluster Init Bundle
  → Generate bundle → <cluster_init_bundle.yaml> → Generate → Download Kubernetes Secret File
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

### Installing the roxctl CLI

* Installing the roxctl CLI
  ```
  arch="$(uname -m | sed "s/x86_64//")"; arch="${arch:+-$arch}"
  curl -f -o roxctl "https://mirror.openshift.com/pub/rhacs/assets/4.3.1/bin/Linux/roxctl${arch}"
  chmod +x roxctl
  mv ./roxctl /usr/local/bin/
  ```

### Enabling offline mode and updating Scanner and kernel support packages

* Creating an API token and setting environment variables
  ```
  ACS Console → Platform Configuration → Integrations → Authentication Tokens → API Token → <Admin> → Generate Token
  ```
  
* Set the ROX_API_TOKEN variable
  ```
  export ROX_API_TOKEN=eyJhbGciOiJSUzI1NiIsImtpZCI6Imp3dGswIiwidHlwIjoiSldUIn0.eyJhdWQiOlsiaHR0cHM6Ly9zdGFja3JveC5pby9qd3Qtc291cmNlcyNhcGktdG9rZW5zIl0sImV4cCI6MTczNTM2MjM4OCwiaWF0IjoxNzAzODI2Mzg4LCJpc3MiOiJodHRwczovL3N0YWNrcm94LmlvL2p3dCIsImp0aSI6IjQxYmVjM2I1LTNiNDQtNDY5Ny1hMDY1LTZhZTM5MTkyOTBkZSIsIm5hbWUiOiJhZG1pbiIsInJvbGVzIjpbIkFkbWluIl19.FnJmRYN5-fCaSPq5ZyWE75TaPK-DFA1MizeGV6uLirGzCvxuPGnEv0IZI0J-M1tDPGvLQfG4EEh5J6A4jC0VqfWMfZe-rg0h1ZTELKf4SE0SU-fjyJmzlrnsLAqlWbq0Z0VIO0s1mROOjikQUyBRx9cCn_MGFcLomunhJAUhu5GETTbFRUFy5HvWRf1AI9R8nuHli023ouRLhbDkiCaQKI8n1EQ0WHevAj7FIrqTTtZUGxvhiQKnYF2zkzliLTdZz5MS6sAGtyIMVmBvqRFaPN35D7AN_xTJCzk-8TwqAW9qeMVLraa6OaC8VIY5U-FHKytA178Gxv9T2DoOFoa4KCYYP9msT6B6DmI7ens2ztfkLzeThYMtA_B7xzh-CR7EuHrSJkEywPG9Kyq6xT1DToxAbUWOSVzKfvcLWsECKKElrenRayleU0mHRaImW-XzEv3cTgwgNHMuLJMSJXUXEVzcYNV563Cl0QAlkHTMffYxRvFDG2w-lyrdGEmOs_rvJWGWvacJPa4xJa-7rDII6Ur4Uh8HHmmx4lKDqMQsHhrZBwpPYdJ7txyQpavgN0c2DYka9gtcmXRWTratiT9XO3jeTMClPDmdVjY2GmiEqn9Zi0ohWvIA5z-EpW5rc34RU7GeWe8wCUvPEJ4tKqwkeuoUxFCAlDBq_RHNA9CzVlo
  ```

* Set the ROX_CENTRAL_ADDRESS variable
  ```
  export ROX_CENTRAL_ADDRESS=$(oc get route central -n stackrox -o jsonpath='{.spec.host}'):443
  ```

* Downloading [kernel support packages](https://install.stackrox.io/collector/support-packages/index.html)
  
* Downloading [Scanner](https://install.stackrox.io/scanner/scanner-vuln-updates.zip) definitions
  ```
  wget -q https://install.stackrox.io/scanner/scanner-vuln-updates.zip
  ```
  
* Uploading definitions to Central
  ```
  roxctl --insecure-skip-tls-verify -e "$ROX_CENTRAL_ADDRESS" \
    scanner upload-db --scanner-db-file=scanner-vuln-updates.zip
  ```

* Uploading kernel support packages to Central
  ```
  ls
  support-pkg-2.7.0-latest.zip  support-pkg-2.7.0-latest.zip.sha256

  sha256sum -c support-pkg-2.7.0-latest.zip.sha256

  roxctl --insecure-skip-tls-verify -e "$ROX_CENTRAL_ADDRESS" \
    collector support-packages upload support-pkg-2.7.0-latest.zip
  ```

### Configuring delegated image scanning in an offline environment

* Configuring delegated image scanning in an offline environment 
  ```
  ACS Console →Platform Configuration → Clusters → Select <my-cluster> → Manage delegated scanning
  → Specified registries → Select default cluster to delegate to <my-cluter>
  → Add registry  Source → registry <LOCAL_REGISTEY> → Destination cluster <my-cluter> → Save
  ```

### Periodic scanning of images

* Central fetches the image scan results for all active images from Scanner or other integrated image scanners that you use and updates the results every 4 hours.

### Checking image scan results

* Manually check a single image
  ```
  export ROX_API_TOKEN="${ROX_API_TOKEN}"
  export ROX_CENTRAL_ADDRESS=$(oc get route central -n stackrox -o jsonpath='{.spec.host}'):443

  # Checking single image
  roxctl --insecure-skip-tls-verify -e "$ROX_CENTRAL_ADDRESS" \
    image scan --image bastion.ocp4.example.com:5000/openshift/release@sha256:28869cebbf8e5454493def0e6c8eb9bf33bfd8d56d1ce106a6c6708530c2c1c2 -o json
  ```

* Manually check all images in the image registry
  ```
  export LOCAL_REGISTRY="bastion.ocp4.example.com:5000"
  export ROX_API_TOKEN="${ROX_API_TOKEN}"
  export ROX_CENTRAL_ADDRESS=$(oc get route central -n stackrox -o jsonpath='{.spec.host}'):443
  
  allImages=(backend:v1 backend:11-ubuntu backend:CVE-2020-36518 frontend-js:v1 frontend-js:node frontend-js:CVE-2020-28471 log4shell:latest backend-native:v1 backend-native:distroless)
  for image in $allImages
  do
      roxctl --insecure-skip-tls-verify -e "${ROX_CENTRAL_ADDRESS}" image scan --image ${LOCAL_REGISTRY}/$image --output=table
  done
   ```
