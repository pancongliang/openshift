## Install and configure NMState Operator

### Install NMState Operator
* Install the Operator using the openshift-nmstate namespace
  ```
  export CHANNEL_NAME="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="openshift-nmstate"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/nmstate/operator.yaml | envsubst | oc apply -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```


* Create an instance of the nmstate Operator:
  ```
  cat << EOF | oc apply -f -
  apiVersion: nmstate.io/v1
  kind: NMState
  metadata:
    name: nmstate
  EOF
  ```

### Configure Static IP
* Configure Static IP for worker03 node
  ```
  cat << EOF | oc apply -f -
  apiVersion: nmstate.io/v1
  kind: NodeNetworkConfigurationPolicy
  metadata:
    name: worker03-static-ip-ens8-policy 
  spec:
    nodeSelector:
      kubernetes.io/hostname: worker03.ocp4.example.com
    desiredState:
      interfaces:
      - name: ens8
        type: ethernet
        state: up
        ipv4:
          address:
          - ip: 10.74.253.220
            prefix-length: 21
          dhcp: false
          enabled: true
  EOF
  ```

* Confirming node network policy updates on nodes
  ```
  $ oc get nnce
  NAME                                                       STATUS      REASON
  worker03.ocp4.example.com.worker03-static-ip-ens8-policy   Available   SuccessfullyConfigured

  $ oc get nncp
  NAME                             STATUS      REASON
  worker03-static-ip-ens8-policy   Available   SuccessfullyConfigured

  $ ssh core@worker03 sudo  ip a | grep ens8 
  12: ens8: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
      inet 10.74.253.220/21 brd 10.74.255.255 scope global noprefixroute ens8
  ```

### Configure DNS IP
* Configure DNS IP
  ```
  cat << EOF | oc apply -f -
  apiVersion: nmstate.io/v1
  kind: NodeNetworkConfigurationPolicy
  metadata:
    name: worker01-modify-dns
  spec:
    nodeSelector: 
      kubernetes.io/hostname: worker01.ocp4.example.com
    desiredState:
      dns-resolver:
        config:
          search:
          - ocp4.example.com
          server:
          - 10.184.134.94
  EOF
  ```


  ### Delete network settings configured through the NMState operator
* Delete network settings configured through the NMState operator
  ```
  # Create policy
  cat << EOF | oc apply -f -
  apiVersion: nmstate.io/v1
  kind: NodeNetworkConfigurationPolicy
  metadata:
    name: worker03-static-ip-ens8-policy 
  spec:
    nodeSelector:
      kubernetes.io/hostname: worker03.ocp.example.com
    desiredState:
      routes:
        config:
        - destination: 10.49.56.0/24
          metric: 150
          next-hop-address: 10.48.55.1
          next-hop-interface: ens35
          table-id: 254
  EOF

  ssh core@worker03 sudo ip route
  default via 10.184.134.1 dev br-ex proto static metric 48 
  default via 10.48.55.1 dev ens35 proto dhcp src 10.48.55.102 metric 101 
  10.48.55.0/24 dev ens35 proto kernel scope link src 10.48.55.102 metric 101 
  10.49.56.0/24 via 10.48.55.1 dev ens35 proto static metric 150              # Added routing entries
  10.128.0.0/14 via 10.128.2.1 dev ovn-k8s-mp0 
  10.128.2.0/23 dev ovn-k8s-mp0 proto kernel scope link src 10.128.2.2 
  10.184.134.0/24 dev br-ex proto kernel scope link src 10.184.134.204 metric 48 
  169.254.169.0/29 dev br-ex proto kernel scope link src 169.254.169.2 
  169.254.169.1 dev br-ex src 10.184.134.204 
  169.254.169.3 via 10.128.2.1 dev ovn-k8s-mp0 
  172.30.0.0/16 via 169.254.169.4 dev br-ex src 169.254.169.2 mtu 1400  


  # Delete policy
  oc edit nncp worker03-static-ip-ens8-policy
  ···
    desiredState:
      routes:
        config:
        - destination: 10.49.56.0/24
          metric: 150
          next-hop-address: 10.48.55.1
          next-hop-interface: ens35
          state: absent       # <--- Add the line "state: absent" to remove the route.
          table-id: 254

  # OR
  
  oc delete nncp worker03-static-ip-ens8-policy
  
  cat << EOF | oc apply -f -
  apiVersion: nmstate.io/v1
  kind: NodeNetworkConfigurationPolicy
  metadata:
    name: delete-worker03-static-ip-ens8-policy 
  spec:
    nodeSelector:
      kubernetes.io/hostname: worker03.ocp.example.com
    desiredState:
      routes:
        config:
        - destination: 10.49.56.0/24
          metric: 150
          next-hop-address: 10.48.55.1
          next-hop-interface: ens35
          state: absent       # <--- Add the line "state: absent" to remove the route.
          table-id: 254
  EOF

  ssh core@worker03 sudo ip route
  default via 10.184.134.1 dev br-ex proto static metric 48 
  default via 10.48.55.1 dev ens35 proto dhcp src 10.48.55.102 metric 101 
  10.48.55.0/24 dev ens35 proto kernel scope link src 10.48.55.102 metric 101 
  10.128.0.0/14 via 10.128.2.1 dev ovn-k8s-mp0 
  10.128.2.0/23 dev ovn-k8s-mp0 proto kernel scope link src 10.128.2.2 
  10.184.134.0/24 dev br-ex proto kernel scope link src 10.184.134.204 metric 48 
  169.254.169.0/29 dev br-ex proto kernel scope link src 169.254.169.2 
  169.254.169.1 dev br-ex src 10.184.134.204 
  169.254.169.3 via 10.128.2.1 dev ovn-k8s-mp0 
  172.30.0.0/16 via 169.254.169.4 dev br-ex src 169.254.169.2 mtu 1400  
  ```
