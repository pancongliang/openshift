## Agent-based Installer

### Defining environment variables
~~~
# Specify required parameters for install-config.yaml
export CLUSTER_NAME="abi-ocp"
export BASE_DOMAIN="example.com"
export PULL_SECRET_FILE="$HOME/pull-secret"
export SSH_KEY_PATH="$(cat $HOME/.ssh/id_rsa.pub)"

# Specify the OpenShift node infrastructure network configuration and  installation disk
# export COREOS_INSTALL_DEV="/dev/sda"
export COREOS_INSTALL_DEV="/dev/disk/by-path/pci-0000:02:00.0-scsi-0:0:0:0"
export NET_IF_NAME="ens33" 
export GATEWAY_IP="10.184.134.1"
export NETMASK="24"

# Specify OpenShift node’s hostname and IP address
export BASTION_IP="10.184.134.128"  
export MASTER01_HOSTNAME="master01"
export MASTER02_HOSTNAME="master02"
export MASTER03_HOSTNAME="master03"
export WORKER01_HOSTNAME="worker01"
export WORKER02_HOSTNAME="worker02"

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

export RENDEZVOUS_IP="$MASTER01_IP"
export NTP_SERVER="0.rhel.pool.ntp.org"
export NSLOOKUP_TEST_PUBLIC_DOMAIN="redhat.com"
export DNS_SERVER_IP="$BASTION_IP"
export API_IP="$BASTION_IP"
export API_INT_IP="$BASTION_IP"
export APPS_IP="$BASTION_IP"
export LB_IP="$BASTION_IP"
~~~

### Installing the Infrastructure
~~~
sudo dnf install -y bind-utils bind haproxy
sudo dnf install /usr/bin/nmstatectl -y
bash inst-Infrastructure.sh
~~~

### Create Agent Config
~~~
mkdir ocp-inst

cat << EOF > ocp-inst/agent-config.yaml
apiVersion: v1beta1
kind: AgentConfig
metadata:
  name: my-cluster
additionalNTPSources:
- "${NTP_SERVER}"
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
            - "${DNS_SERVER_IP}"
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
            - "${DNS_SERVER_IP}"
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
            - "${DNS_SERVER_IP}"
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
            - "${DNS_SERVER_IP}"
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
            - "${DNS_SERVER_IP}"
      routes:
        config:
          - destination: 0.0.0.0/0
            next-hop-address: "${GATEWAY_IP}"
            next-hop-interface: "${NET_IF_NAME}"
            table-id: 254
EOF
~~~

### Create install-config
~~~
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
  - cidr: "10.128.0.0/14"
    hostPrefix: "23"
  networkType: "OVNKubernetes"
  serviceNetwork: 
  - "172.30.0.0/16"
  machineNetwork:
  - cidr: "10.184.134.1/24"
platform:
  none: {} 
fips: false
pullSecret: '$(cat $PULL_SECRET_FILE)'
sshKey: '${SSH_KEY_PATH}'
EOF
~~~

### Creating and booting the agent image

- If it is a vmware environment, enable [disk.EnableUUID](https://access.redhat.com/solutions/4606201) for all nodes)
~~~
openshift-install --dir ocp-inst agent create image
~~~


### Tracking and verifying installation progress 
~~~
openshift-install --dir ocp-inst agent wait-for bootstrap-complete --log-level=info
openshift-install --dir ocp-inst agent wait-for install-complete
~~~
