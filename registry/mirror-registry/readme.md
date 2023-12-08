## Install and configure Mirror Registry

### Deploy Mirror Registry

* Deploy the latest version of Mirror Registry
  ```
  export REGISTRY_DOMAIN_NAME="mirror.registry.example.com"
  export REGISTRY_ID="root"
  export REGISTRY_PW="password"                         # 8 characters or more
  export REGISTRY_INSTALL_PATH="/opt/quay-install"
  wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/registry/mirror-registry/deploy-mirror-registry.sh
  
  source deploy-mirror-registry.sh
  ```
