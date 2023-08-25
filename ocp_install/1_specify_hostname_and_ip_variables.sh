#!/bin/bash
###Variable needs to be change###

# OpenShift install-config variable
export OCP_RELEASE="4.10.20"
export CLUSTER_NAME="ocp4"
export BASE_DOMAIN="example.com"
export NETWORK_TYPE="OVNKubernetes"              # OVNKubernetes or OpenShiftSDN
export ID_RSA_PUB="/root/.ssh/id_rsa.pub"
export OCP_INSTALL_DIR="/var/www/html/materials/pre"

# OpenShift API/APPS Domain variable
export APPS_HOSTNAME="*.apps.ocp4.example.com"
export API_HOSTNAME="api.ocp4.example.com"
export API_INT_HOSTNAME="api-int.ocp4.example.com"

# OpenShift Node Hostname/IP variable
export BOOTSTRAP_HOSTNAME="bootstrap.ocp4.example.com"
export MASTER01_HOSTNAME="master01.ocp4.example.com"
export MASTER02_HOSTNAME="master02.ocp4.example.com"
export MASTER03_HOSTNAME="master03.ocp4.example.com"
export WORKER01_HOSTNAME="worker01.ocp4.example.com"
export WORKER02_HOSTNAME="worker02.ocp4.example.com"
export BASTION_IP="10.74.251.171"
export MASTER01_IP="10.74.251.61"
export MASTER02_IP="10.74.254.155"
export MASTER03_IP="10.74.253.133"
export WORKER01_IP="10.74.251.58"
export WORKER02_IP="10.74.253.49"
export BOOTSTRAP_IP="10.74.255.118"

# Registry and mirror variable
export REGISTRY_HOSTNAME="docker.registry.example.com"
export REGISTRY_ID="admin"
export REGISTRY_PW="redhat"
export LOCAL_SECRET_JSON="/root/pull-secret"

# Network variable
export GATEWAY_IP="21"
export NETMASK="10.74.255.254"
export DNS_FORWARDER_IP="10.75.5.25"

# Node disk/interface
export NODE_DISK_PARTITION="sda"
export NODE_NETWORK_INTERFACE="ens3"

###No need to change###

# Function to generate reversed DNS
generate_reverse_dns() {
  local ip="$1"
  reversed_dns=$(echo "$ip" | awk -F'.' '{print $4"."$3}')
  echo "$reversed_dns"
}

export # Generate reversed DNS for each IP and store as variables
export BASTION_REVERSE_DNS=$(generate_reverse_dns "$BASTION_IP")
export REGISTRY_REVERSE_DNS=$(generate_reverse_dns "$REGISTRY_IP")
export MASTER01_REVERSE_DNS=$(generate_reverse_dns "$MASTER01_IP")
export MASTER02_REVERSE_DNS=$(generate_reverse_dns "$MASTER02_IP")
export MASTER03_REVERSE_DNS=$(generate_reverse_dns "$MASTER03_IP")
export WORKER01_REVERSE_DNS=$(generate_reverse_dns "$WORKER01_IP")
export WORKER02_REVERSE_DNS=$(generate_reverse_dns "$WORKER02_IP")
export BOOTSTRAP_REVERSE_DNS=$(generate_reverse_dns "$BOOTSTRAP_IP")
export API_REVERSE_DNS=$(generate_reverse_dns "$API_IP")
export API_INT_REVERSE_DNS=$(generate_reverse_dns "$API_INT_IP")

# Function to generate reversed_ip_par/zone name
export IP_PART=$(echo "$BASTION_IP" | cut -d. -f2-3)
export REVERSED_IP_PART=$(echo "$IP_PART" | awk -F'.' '{print $2"."$1}')
export REVERSE_ZONE="${REVERSED_IP_PART}.in-addr.arpa"
export REVERSE_ZONE_FILE_NAME="${REVERSED_IP_PART}.zone"

# Function to generate duplicate IP address
export DNS_IP="$BASTION_IP"
export REGISTRY_IP="$BASTION_IP"
export API_IP="$BASTION_IP"
export API_INT_IP="$BASTION_IP"
export APPS_IP="$BASTION_IP"

source 1_specify_hostname_and_ip_variables.sh
