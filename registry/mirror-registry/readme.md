## Install and configure Mirror Registry

### Deploy Mirror Registry

* Deploy the latest version of Mirror Registry
  ```
  export REGISTRY_DOMAIN_NAME="mirror.registry.example.com"
  export REGISTRY_ID="admin"
  export REGISTRY_PW="password"
  export REGISTRY_INSTALL_PATH="/opt/quay-install"

  curl -sOL https://raw.githubusercontent.com/pancongliang/openshift/main/registry/mirror-registry/inst-mirror-registry.sh
  source inst-mirror-registry.sh
  ```
* Configuring additional [trust](https://github.com/pancongliang/openshift/blob/main/registry/add-trust-registry/readme.md#configuring-additional-trust-stores-for-image-registry-access) stores for image registry access
