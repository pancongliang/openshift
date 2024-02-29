## Install and configure Docker Registry


### Deploy Docker Registry

* Generate self-signed certificate and deploy Docker Registry
  ```
  export REGISTRY_DOMAIN_NAME="docker.registry.example.com"
  export USER="admin"
  export PASSWD="redhat"
  export REGISTRY_CERT_PATH="/etc/crts"
  export REGISTRY_INSTALL_PATH="/opt/docker-registry"
  export CONTAINER_NAME="docker-registry"
  wget -q  https://raw.githubusercontent.com/pancongliang/openshift/main/registry/docker-registry/deploy-docker-registry.sh
  
  source deploy-docker-registry.sh
  ```
* Configuring additional [trust](https://github.com/pancongliang/openshift/blob/main/registry/add-trust-registry/readme.md#configuring-additional-trust-stores-for-image-registry-access) stores for image registry access
