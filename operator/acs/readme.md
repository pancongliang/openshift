### Install RHACS Operator

* Install the Operator using the default namespace
  ```
  export CHANNEL_NAME="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/acs/01-operator.yaml | envsubst | oc create -f -

  sleep 6
  
  oc patch installplan $(oc get ip -n rhacs-operator  -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n rhacs-operator --type merge --patch '{"spec":{"approved":true}}'

  oc get ip -n rhacs-operator
  ```

### Create Central instance

* Deploy [NFS Storage Class](https://github.com/pancongliang/openshift/blob/main/storage/nfs-storageclass/readme.md)
  
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


### Installing the roxctl CLI

* Installing the roxctl CLI
  ```
  arch="$(uname -m | sed "s/x86_64//")"; arch="${arch:+-$arch}"
  curl -f -o roxctl "https://mirror.openshift.com/pub/rhacs/assets/4.3.1/bin/Linux/roxctl${arch}"
  chmod +x roxctl
  mv ./roxctl /usr/local/bin/
  ```

### Add an OpenShift cluster to RHACS

* Creating Init Bundle
  ```
  ACS Console Platform → Configuration → Integrations → Cluster Init Bundle
  → Generate bundle → <cluster_init_bundle.yaml> → Generate → Download Kubernetes Secret File

  or
  
  export ROX_CENTRAL_ADDRESS=$(oc get route central -n stackrox -o jsonpath='{.spec.host}'):443
  roxctl -e "$ROX_CENTRAL_ADDRESS" central init-bundles generate cluster_init_bundle.yaml --output-secrets cluster_init_bundle.yaml
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

### Enabling offline mode and updating Scanner and kernel support packages

* Creating an API token and setting environment variables
  ```
  ACS Console → Platform Configuration → Integrations → Authentication Tokens → API Token → <Admin> → Generate Token
  ```
  
* Set the ROX_API_TOKEN variable
  ```
  export ROX_API_TOKEN=eyJhbGciOiJSUzI1NiIsImtpZCI6Imp3dGswIiwidHlwIjoiSldUIn0.eyJhdWQiOlsiaHR0cHM6Ly9zdGFja3JveC5pby9qd3Qtc291cmNlcyNhcGktdG9rZW5zIl0sImV4cCI6MTczNTQxMjIyMCwiaWF0IjoxNzAzODc2MjIwLCJpc3MiOiJodHRwczovL3N0YWNrcm94LmlvL2p3dCIsImp0aSI6IjIwYzQ3OTE0LTJmMjQtNDQzZi05NDFhLWE0ZGQ5MTRiMGQxMSIsIm5hbWUiOiJhZG1pbiIsInJvbGVzIjpbIkFkbWluIl19.BWzkQNPv-lEIviAGiyRByv_0TEHCfXSV17VhMaqQkNE4hgfnPcSs7VtTcFRoVkgpbT6vF0A3yF2T5lYu4_x1W0_QY3N6F5TxKGDPAfXb-lYSx_cRjGaklYJqVgW2g9yxrqG6IpYbi_Eaj7_dhwyBIbisS4olInco4Tmm-I4UsD_fV06Bl2OHz_5vpTlU2lCPEOxizRtCp7ovdQnM0tx-1vDKVjd8kObwVR-3pjv8VFTgZ7d4cPjUyZmiV02A0stRfof5XUuoju_3tVCsXouscffkAVzoSNf2_MnGS3vZPlUgczqzuoE-mNbkOE4I395JnZInbp8bXmpWwN0qBUJPCbe51EO3rk_IcLhR8_bYduUQ4diY-_eAec9xE9vGc5csgklZyITstcioLrunLt1lGgscHAWxKTVGODfTxt8ma11XmBt0wHzmqyCvI1HFe9lbazoCRiTJrZdtpjqSJhAkOiszxXV_pUjeMPzfu4GQY24PDvAySFyhkHnABtzCIWaG0uK8IyFeJhVol-gR4kogdXRVBRNrNJYaHW8i-QU6lgrMMfR-KgDF4Zws7U8RU-iEu5d4LOcm7R9hU_WC4b4JZHv6nxtWEnnwKRDm-wGbtkjnDCL37189jfAcpiLDUuvpZe-8Rpo0i6_TCSF3Z4DD-FQtWakOrIBSt1ZIL3tfGz8
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
  ACS Console → Platform Configuration → Clusters → Select <my-cluster> → Manage delegated scanning
  → Delegate scanning for <All registries> → Select default cluster to delegate to <my-cluter> → Save
  ```

### Periodic scanning of images

* Central fetches the image scan results for all active images from Scanner or other integrated image scanners that you use and updates the results every 4 hours.

* Change the interval for periodic scanning images
  ```
  export ROX_REPROCESSING_INTERVAL="30m"

  # After installation
  oc -n stackrox set env deploy/central ROX_REPROCESSING_INTERVAL=${ROX_REPROCESSING_INTERVAL}

  # Before installation
  oc patch central stackrox-central-services -n stackrox \
     --type=json -p="$(echo '[{"op": "add", "path": "/spec/customize", "value": {"envVars": [{"name": "ROX_REPROCESSING_INTERVAL", "value": "${ROX_REPROCESSING_INTERVAL}"}]}}]' | envsubst)"
  ```

* Fallback to default periodic image scan interval
  ```
  oc patch central stackrox-central-services -n stackrox \
     --type=json -p='[{"op": "remove", "path": "/spec/customize"}]'
  ```
### Checking image scan results

* Manually scan a single image
  ```
  export ROX_API_TOKEN="${ROX_API_TOKEN}"
  export ROX_CENTRAL_ADDRESS=$(oc get route central -n stackrox -o jsonpath='{.spec.host}'):443

  # Checking single image
  roxctl --insecure-skip-tls-verify -e "$ROX_CENTRAL_ADDRESS" \
    image scan --image bastion.ocp4.example.com:5000/openshift/release@sha256:28869cebbf8e5454493def0e6c8eb9bf33bfd8d56d1ce106a6c6708530c2c1c2 -o json
  ```

* Scan all images in docker registry
  ```
  #!/bin/bash
  # Set variables
  export REGISTRY_URL='docker.registry.example.com:5000'
  export REGISTRY_ID="admin"
  export REGISTRY_PW="redhat"
  
  export ROX_API_TOKEN="${ROX_API_TOKEN}"
  export ROX_CENTRAL_ADDRESS=$(oc get route central -n stackrox -o jsonpath='{.spec.host}'):443
  
  
  # Get all repositories
  REPOSITORIES=$(curl -s -u "$REGISTRY_ID:$REGISTRY_PW" "https://$REGISTRY_URL/v2/_catalog" | jq -r '.repositories  []')
  
  # Iterate over each repository, get tags or hashes
  for REPOSITORY in $REPOSITORIES
  do
      # Try to get tags
      TAGS=$(curl -s -u "$REGISTRY_ID:$REGISTRY_PW" "https://$REGISTRY_URL/v2/$REPOSITORY/tags/list" | jq -r '.tags  []' 2>/dev/null || echo "latest")
  
      # If no tags, get digest
      if [ "$TAGS" == "latest" ]; then
          DIGEST=$(curl -s -u "$REGISTRY_ID:$REGISTRY_PW" "https://$REGISTRY_URL/v2/$REPOSITORY/manifests/latest" | jq -r '.config.digest')
          IMAGE_URI="$REGISTRY_URL/$REPOSITORY@$DIGEST"
      elif [ -n "$TAGS" ] && [ "$TAGS" != "null" ]; then
          # Output image URI with tags
          for TAG in $TAGS
          do
              IMAGE_URI="$REGISTRY_URL/$REPOSITORY:$TAG"
              echo "Image URI: $IMAGE_URI"
  
              # Perform roxctl check for each image
              roxctl --insecure-skip-tls-verify -e "$ROX_CENTRAL_ADDRESS" image check --image="$IMAGE_URI"
          done
      fi
  done
  ```
  
* Scan all images in quay registry(public repositories)
  ```
  Create OAuth access token

  1.Log in to Red Hat Quay and select your Organization (or create a new one).
  2.Select the Applications icon from the left navigation.
  3.Select Create New Application and give the new application a name when prompted.
  4.Select the new application.
  5.Select Generate Token from the left navigation.
  6.Select the checkboxes to set the scope of the token and select Generate Access Token.
  7.Review the permissions you are allowing and select Authorize Application to approve it.
  8.Copy the newly generated token to use to access the API.
  ```
  ```
  #!/bin/bash
  export REGISTRY_TOKEN="BGz3ExbSNb5RPewDNvVEZW3EUghHACVBgZ4ijq2q"
  export REGISTRY_URL='mirror.registry.example.com:8443'

  export ROX_API_TOKEN="${ROX_API_TOKEN}"
  export ROX_CENTRAL_ADDRESS=$(oc get route central -n stackrox -o jsonpath='{.spec.host}'):443
  
  # View public repositories in the registry and retrieve namespace and name fields
  REPOSITORIES=$(curl -ks -H "Authorization: Bearer ${REGISTRY_TOKEN}" "https://${REGISTRY_URL}/api/v1/repository?public=true")
  
  # Extract namespace and repository fields
  echo "$REPOSITORIES" | jq -r '.repositories | map(select(.namespace != null and .name != null)) | .[] | "\(.namespace) \(.name)"' | while read -r NS   REPO; do
    TAGS=$(curl -ks -H "Authorization: Bearer ${REGISTRY_TOKEN}" "https://${REGISTRY_URL}/api/v1/repository/${NS}/${REPO}/tag/" | jq -r '.tags | map(select(.name != null)) | .[].name')

    if [ -n "$TAGS" ]; then
      for TAG in $TAGS; do
        # Print image address
        IMAGE_URI="${REGISTRY_URL}/${NS}/${REPO}:${TAG}"
        echo "Image URI: $IMAGE_URI"
  
        # Perform roxctl check for each image
        roxctl --insecure-skip-tls-verify -e "$ROX_CENTRAL_ADDRESS" image check --image="$IMAGE_URI"
      done
    fi
  done
  ```
### More [RHCAS configurations](https://github.com/rhthsa/openshift-demo/blob/main/acs.md#scan-and-check-image-with-roxctl)
