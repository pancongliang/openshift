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

### Deploy Docker Registry

* Generate self-signed certificate and deploy Docker Registry
  ```
  export REGISTRY_DOMAIN="docker.registry.example.com"
  export USER="admin"
  export PASSWD="redhat"
  export REGISTRY_CERT_PATH="/cert"
  export REGISTRY_INSTALL_PATH="/regitry"
  export CONTAINER_NAME="docker-registry"

  wget https://raw.githubusercontent.com/pancongliang/openshift/main/registry/deploy_docker_registry.sh
  source deploy_docker_registry.sh
  ```
