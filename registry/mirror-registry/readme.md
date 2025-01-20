## Install and configure Mirror Registry

### Deploy Mirror Registry

* Deploy the latest version of Mirror Registry
  ```
  export REGISTRY_DOMAIN_NAME="mirror.registry.example.com"
  export REGISTRY_ID="root"
  export REGISTRY_PW="password"                         # 8 characters or more
  export REGISTRY_INSTALL_PATH="/opt/quay-install"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/registry/mirror-registry/inst-mirror-registry.sh | bash
  ```
* Configuring additional [trust](https://github.com/pancongliang/openshift/blob/main/registry/add-trust-registry/readme.md#configuring-additional-trust-stores-for-image-registry-access) stores for image registry access
