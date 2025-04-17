## Install and configure Mirror Registry

### Deploy Mirror Registry

* Deploy the latest version of Mirror Registry
  ```
  curl -sOL https://raw.githubusercontent.com/pancongliang/openshift/main/registry/mirror-registry/inst-mirror-registry.sh

  vim inst-mirror-registry.sh
  export REGISTRY_DOMAIN_NAME="mirror.registry.example.com"
  export REGISTRY_ID="admin"
  export REGISTRY_PW="password"
  export REGISTRY_INSTALL_PATH="/opt/quay-install"
  
  bash inst-mirror-registry.sh
  ```

