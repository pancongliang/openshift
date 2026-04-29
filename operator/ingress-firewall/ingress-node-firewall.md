## Install and Configure Ingress Node Firewall Operator

### Install Ingress Node Firewall Operator

* To install the Operator using the default namespace, follow these steps:

  ```bash
  export SUB_CHANNEL="stable"

  cat << EOF | oc apply -f -
  apiVersion: v1
  kind: Namespace
  metadata:
    labels:
      pod-security.kubernetes.io/enforce: privileged
      pod-security.kubernetes.io/enforce-version: v1.24
    name: openshift-ingress-node-firewall
  ---
  apiVersion: operators.coreos.com/v1
  kind: OperatorGroup
  metadata:
    name: ingress-node-firewall-operators
    namespace: openshift-ingress-node-firewall
  ---
  apiVersion: operators.coreos.com/v1alpha1
  kind: Subscription
  metadata:
    name: ingress-node-firewall-sub
    namespace: openshift-ingress-node-firewall
  spec:
    channel: ${SUB_CHANNEL}
    installPlanApproval: Automatic
    name: ingress-node-firewall
    source: redhat-operators
    sourceNamespace: openshift-marketplace
  EOF
  ```

### Create an IngressNodeFirewallConfig custom resource

* Create an IngressNodeFirewallConfig custom resource:

  ```bash
  oc get nodes -o name | xargs -I {} oc label {} ingressnodefirewall.openshift.io/openshift-ingress-node-firewall=''
  
  cat << EOF | oc apply -f -
  apiVersion: ingressnodefirewall.openshift.io/v1alpha1
  kind: IngressNodeFirewallConfig
  metadata:
    name: ingressnodefirewallconfig
    namespace: openshift-ingress-node-firewall
  spec:
    nodeSelector:
      ingressnodefirewall.openshift.io/openshift-ingress-node-firewall: ""
  EOF
  ```

### Create an Ingress Node Firewall rules object

* Create a Deny ssh Ingress Node Firewall rules
  ```bash
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
       ingressnodefirewall.openshift.io/openshift-ingress-node-firewall: ""
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
  ```bash
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
        ingressnodefirewall.openshift.io/openshift-ingress-node-firewall: ""
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
  ```bash
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
        ingressnodefirewall.openshift.io/openshift-ingress-node-firewall: ""
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
          - order: 20
            protocolConfig:
              protocol: TCP
              tcp:
                ports: 30768
            action: Deny
  EOF
  ```
    
* Create a Deny Nodeport Ingress Node Firewall rules
  ```bash
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
        ingressnodefirewall.openshift.io/openshift-ingress-node-firewall: ""
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
