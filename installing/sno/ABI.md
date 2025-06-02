~~~
# Specify required parameters for install-config.yaml
export CLUSTER_NAME="pan"
export BASE_DOMAIN="example.com"
export NETWORK_TYPE="OVNKubernetes"

# Specify the OpenShift node infrastructure network configuration and  installation disk
export COREOS_INSTALL_DEV="/dev/sda"
export NET_IF_NAME="ens33" 

export GATEWAY_IP="10.184.134.1"
export NETMASK="24"
export DNS_IP="10.184.134.1"  
export MACHINE_NETWORK_CID="10.184.134.1/24"

# Specify OpenShift node’s hostname and IP address
export BASTION_HOSTNAME="bastion"
export MASTER01_HOSTNAME="master01"
export MASTER02_HOSTNAME="master02"
export MASTER03_HOSTNAME="master03"
export WORKER01_HOSTNAME="worker01"
export WORKER02_HOSTNAME="worker02"
export WORKER03_HOSTNAME="worker03"
export RENDEZVOUS_IP="10.184.134.128"
export BASTION_IP="10.184.134.128"
export MASTER01_IP="10.184.134.243"
export MASTER02_IP="10.184.134.241"
export MASTER03_IP="10.184.134.207"
export WORKER01_IP="10.184.134.238"
export WORKER02_IP="10.184.134.246"
export WORKER03_IP="10.184.134.202"
export MASTER01_MAC_ADDR=""
export MASTER02_MAC_ADDR=""
export MASTER03_MAC_ADDR=""
export WORKER01_MAC_ADDR=""
export WORKER02_MAC_ADDR=""
export WORKER03_MAC_ADDR=""
~~~

~~~
cat << EOF > agent-config.yaml
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
        macAddress: "{MASTER01_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "{MASTER01_MAC_ADDR}"
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
        macAddress: "{MASTER02_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "MASTER02_MAC_ADDR"
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
        macAddress: "{MASTER03_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "MASTER03_MAC_ADDR"
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
        macAddress: "{WORKER01_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "WORKER01_MAC_ADDR"
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
        macAddress: "{WORKER02_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "WORKER02_MAC_ADDR"
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
  - hostname: "${WORKER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    role: worker
    rootDeviceHints:
      deviceName: "${COREOS_INSTALL_DEV}"
    interfaces:
      - name: "${NET_IF_NAME}"
        macAddress: "{WORKER03_MAC_ADDR}"
    networkConfig:
      interfaces:
        - name: "${NET_IF_NAME}"
          type: ethernet
          state: up
          mac-address: "WORKER03_MAC_ADDR"
          ipv4:
            enabled: true
            address:
              - ip: "${WORKER03_IP}"
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

cat << EOF > install-config.yaml
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
compute: 
- hyperthreading: Enabled 
  name: worker
  replicas: 3 
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
  - cidr: ${MACHINE_NETWORK_CID}
platform:
  none: {} 
fips: false
pullSecret: '$(cat $PULL_SECRET_FILE)'
sshKey: '${SSH_PUB_STR}'
EOF
~~~
