~~~
# Specify required parameters for install-config.yaml
export CLUSTER_NAME="abi-ocp"
export BASE_DOMAIN="example.com"
export PULL_SECRET_FILE="$HOME/pull-secret"
export NETWORK_TYPE="OVNKubernetes"
export MACHINE_NETWORK_CIDR="10.184.134.160/27"
export POD_CIDR="10.128.0.0/14"
export HOST_PREFIX="23"
export SERVICE_CIDR="172.30.0.0/16"
export SSH_KEY_PATH="$(cat $HOME/.ssh/id_rsa.pub)"

# Specify the OpenShift node infrastructure network configuration and  installation disk
export COREOS_INSTALL_DEV="/dev/sda"
export NET_IF_NAME="ens33" 
export GATEWAY_IP="10.184.134.1"
export NETMASK="24"
export DNS_IP="10.184.134.1"  

# Specify OpenShift node’s hostname and IP address
export BASTION_HOSTNAME="bastion"
export MASTER01_HOSTNAME="master01"
export MASTER02_HOSTNAME="master02"
export MASTER03_HOSTNAME="master03"
export WORKER01_HOSTNAME="worker01"
export WORKER02_HOSTNAME="worker02"

export RENDEZVOUS_IP="10.184.134.164"

export MASTER01_IP="10.184.134.176"
export MASTER02_IP="10.184.134.177"
export MASTER03_IP="10.184.134.187"
export WORKER01_IP="10.184.134.189"
export WORKER02_IP="10.184.134.190"

export MASTER01_MAC_ADDR="00:50:56:b0:26:c4"
export MASTER02_MAC_ADDR="00:50:56:b0:38:c2"
export MASTER03_MAC_ADDR="00:50:56:b0:b6:16"
export WORKER01_MAC_ADDR="00:50:56:b0:0c:d1"
export WORKER02_MAC_ADDR="00:50:56:b0:72:a5"
~~~

~~~
mkdir ocp-inst

cat << EOF > ocp-inst/agent-config.yaml
apiVersion: v1beta1
kind: AgentConfig
metadata:
  name: my-cluster
rendezvousIP: "${RENDEZVOUS_IP}"
hosts:
  - hostname: "${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    role: master
    rootDeviceHints:
      deviceName: "${COREOS_INSTALL_DEV}"
    interfaces:
      - name: "${NET_IF_NAME}"
        macAddress: "${MASTER01_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "${MASTER01_MAC_ADDR}"
          ipv4:
            enabled: true
            address:
              - ip: "${MASTER01_IP}"
                prefix-length: "${NETMASK}"
            dhcp: false
      dns-resolver:
        config:
          server:
            - "${DNS_IP}"
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: "${GATEWAY_IP}"
            next-hop-interface: "${NET_IF_NAME}"
            table-id: 254
  - hostname: "${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    role: master
    rootDeviceHints:
      deviceName: "${COREOS_INSTALL_DEV}"
    interfaces:
      - name: "${NET_IF_NAME}"
        macAddress: "${MASTER02_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "${MASTER02_MAC_ADDR}"
          ipv4:
            enabled: true
            address:
              - ip: "${MASTER02_IP}"
                prefix-length: "${NETMASK}"
            dhcp: false
      dns-resolver:
        config:
          server:
            - "${DNS_IP}"
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: "${GATEWAY_IP}"
            next-hop-interface: "${NET_IF_NAME}"
            table-id: 254
  - hostname: "${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    role: master
    rootDeviceHints:
      deviceName: "${COREOS_INSTALL_DEV}"
    interfaces:
      - name: "${NET_IF_NAME}"
        macAddress: "${MASTER03_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "${MASTER03_MAC_ADDR}"
          ipv4:
            enabled: true
            address:
              - ip: "${MASTER03_IP}"
                prefix-length: "${NETMASK}"
            dhcp: false
      dns-resolver:
        config:
          server:
            - "${DNS_IP}"
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: "${GATEWAY_IP}"
            next-hop-interface: "${NET_IF_NAME}"
            table-id: 254
  - hostname: "${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    role: worker
    rootDeviceHints:
      deviceName: "${COREOS_INSTALL_DEV}"
    interfaces:
      - name: "${NET_IF_NAME}"
        macAddress: "${WORKER01_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "${WORKER01_MAC_ADDR}"
          ipv4:
            enabled: true
            address:
              - ip: "${WORKER01_IP}"
                prefix-length: "${NETMASK}"
            dhcp: false
      dns-resolver:
        config:
          server:
            - "${DNS_IP}"
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: "${GATEWAY_IP}"
            next-hop-interface: "${NET_IF_NAME}"
            table-id: 254
  - hostname: "${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    role: worker
    rootDeviceHints:
      deviceName: "${COREOS_INSTALL_DEV}"
    interfaces:
      - name: "${NET_IF_NAME}"
        macAddress: "${WORKER02_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "${WORKER02_MAC_ADDR}"
          ipv4:
            enabled: true
            address:
              - ip: "${WORKER02_IP}"
                prefix-length: "${NETMASK}"
            dhcp: false
      dns-resolver:
        config:
          server:
            - "${DNS_IP}"
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: "${GATEWAY_IP}"
            next-hop-interface: "${NET_IF_NAME}"
            table-id: 254
EOF

cat << EOF > ocp-inst/install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
compute: 
- hyperthreading: Enabled 
  name: worker
  replicas: 2
controlPlane:
  hyperthreading: Enabled 
  name: master
  replicas: 3
metadata:
  name: ${CLUSTER_NAME}
networking:
  clusterNetwork:
  - cidr: ${POD_CIDR}
    hostPrefix: ${HOST_PREFIX}
  networkType: ${NETWORK_TYPE}
  serviceNetwork: 
  - ${SERVICE_CIDR}
  machineNetwork:
  - cidr: ${MACHINE_NETWORK_CIDR}
platform:
  none: {} 
fips: false
pullSecret: '$(cat $PULL_SECRET_FILE)'
sshKey: '${SSH_KEY_PATH}'
EOF
~~~

~~~
openshift-install --dir ocp-inst agent create image

openshift-install --dir ocp-inst agent wait-for bootstrap-complete --log-level=info
openshift-install --dir ocp-inst agent agent wait-for install-complete
~~~
