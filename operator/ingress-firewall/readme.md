

## Install and Configure Ingress Node Firewall Operator

### Install Ingress Node Firewall Operator

* To install the Operator using the default namespace, follow these steps:

  ```
  export CHANNEL_NAME="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="openshift-ingress-node-firewall"

  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/ingress-firewall/01-operator.yaml | envsubst | oc create -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```

### Create an IngressNodeFirewallConfig custom resource

* Create an IngressNodeFirewallConfig custom resource:

  ```
  cat << EOF | oc apply -f -
  apiVersion: ingressnodefirewall.openshift.io/v1alpha1
  kind: IngressNodeFirewallConfig
  metadata:
    name: ingressnodefirewallconfig
    namespace: openshift-ingress-node-firewall
  spec:
    nodeSelector:
      node-role.kubernetes.io/worker: ""
  EOF
  ```

### Create an Ingress Node Firewall rules object

* Create a Deny ssh Ingress Node Firewall rules
  ```
  cat << EOF | oc apply -f -
  apiVersion: ingressnodefirewall.openshift.io/v1alpha1
  kind: IngressNodeFirewall
  metadata:
   name: ssh-block-all-worker
  spec:
   interfaces:
   - ens33 
   nodeSelector:
     matchLabels:
       node-role.kubernetes.io/worker: ""
   ingress:
   - sourceCIDRs:
     - 0.0.0.0/0
     rules:
     - order: 10
       protocolConfig:
         protocol: TCP
         tcp:
           ports: 22
       action: Deny
  EOF
  ```
* Allow ssh rules only for specific IP addresses
  ```
  cat << EOF | oc apply -f -
  apiVersion: ingressnodefirewall.openshift.io/v1alpha1
  kind: IngressNodeFirewall
  metadata:
    name: ssh-allow-cidr-worker
  spec:
    interfaces:
      - ens33 
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/worker: ""
    ingress:
      - sourceCIDRs:
          - 10.184.134.243/32
        rules:
          - order: 15
            protocolConfig:
              protocol: TCP
              tcp:
                ports: 22
            action: Allow
      - sourceCIDRs:
          - 0.0.0.0/0
        rules:
          - order: 10
            protocolConfig:
              protocol: TCP
              tcp:
                ports: 22
            action: Deny
  EOF
  ```

* Only allow specific IP addresses to access the specified port rules
  ```
  cat << EOF | oc apply -f -
  apiVersion: ingressnodefirewall.openshift.io/v1alpha1
  kind: IngressNodeFirewall
  metadata:
    name: nodeport-allow-cidr-worker
  spec:
    interfaces:
      - ens33 
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/worker: ""
    ingress:
      - sourceCIDRs:
          - 10.184.134.243/32
        rules:
          - order: 15
            protocolConfig:
              protocol: TCP
              tcp:
                ports: 30768
            action: Allow
      - sourceCIDRs:
          - 0.0.0.0/0
        rules:
          - order: 10
            protocolConfig:
              protocol: TCP
              tcp:
                ports: 30768
            action: Deny
  EOF
  ```
    
* Create a Deny Nodeport Ingress Node Firewall rules
  ```
  cat << EOF | oc apply -f -
  apiVersion: ingressnodefirewall.openshift.io/v1alpha1
  kind: IngressNodeFirewall
  metadata:
    name: nodeport-block-all-worker
  spec:
    interfaces:
    - ens33
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/worker: ""
    ingress:
    - sourceCIDRs:
      - 0.0.0.0/0
      rules:
      - order: 20
        protocolConfig:
          protocol: TCP
          tcp:
            ports: 30000-32767
        action: Deny
  EOF
  ```
