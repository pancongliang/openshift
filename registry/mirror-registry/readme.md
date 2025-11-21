## Install and configure Mirror Registry

### Deploy Mirror Registry

* Deploy the latest version of Mirror Registry
  ```
  curl -sOL https://raw.githubusercontent.com/pancongliang/openshift/main/registry/mirror-registry/inst-quay.sh

  vim inst-mirror-registry.sh
  export REGISTRY_HOST_NAME="mirror.registry.example.com"
  export REGISTRY_HOST_IP="10.184.134.128"
  export REGISTRY_ID="admin"
  export REGISTRY_PW="password"
  export REGISTRY_INSTALL_DIR="/opt/quay-install"
  
  bash inst-mirror-registry.sh
  ```

