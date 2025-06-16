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
  ```
  cat << EOF | oc apply -f -
  apiVersion: nmstate.io/v1
  kind: NodeNetworkConfigurationPolicy
  metadata:
    name: worker01-dns
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
