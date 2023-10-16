### Deploy Mirror Registry

* Deploy the latest version of Mirror Registry
  ```
  export REGISTRY_HOSTNAME="mirror.registry"
  export REGISTRY_ID="root"
  export REGISTRY_PW="password"                         # 8 characters or more
  export REGISTRY_INSTALL_DIR="/opt/quay-install"

  wget https://raw.githubusercontent.com/pancongliang/openshift/main/registry/deploy_mirror_registry.sh
  source deploy_mirror_registry.sh
```
