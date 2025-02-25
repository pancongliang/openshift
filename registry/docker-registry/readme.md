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
  wget -q  https://raw.githubusercontent.com/pancongliang/openshift/main/registry/docker-registry/inst-docker-registry.sh
  
  source inst-docker-registry.sh
  ```
* Configuring additional [trust](/registry/add-trust-registry/readme.md) stores for image registry access
