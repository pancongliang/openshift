
### After configuring an IP on the node’s secondary network interface, set routingViaHost to true and change ipForwarding to Global to allow Pods to communicate through the node’s secondary network.
```
cat << EOF | oc apply -f -
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: worker02-static-ip-ens35-policy 
spec:
  nodeSelector:
    kubernetes.io/hostname: worker02.ocp.example.com
  desiredState:
    interfaces:
    - name: ens35
      type: ethernet
      state: up
      ipv4:
        address:
        - ip: 10.48.55.133
          prefix-length: 24
        dhcp: false
        enabled: true
EOF

$ ssh core@worker02.ocp.example.com sudo ip ad |grep br-ex
7: br-ex: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN group default qlen 1000
    inet 10.184.134.74/24 brd 10.184.134.255 scope global noprefixroute br-ex
    inet 169.254.0.2/17 brd 169.254.127.255 scope global br-ex

$ ssh core@worker02.ocp.example.com sudo ip ad |grep ens35
21: ens35: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    inet 10.48.55.133/24 brd 10.48.55.255 scope global noprefixroute ens35

$ ssh core@worker02.ocp.example.com sudo ip route
default via 10.184.134.1 dev br-ex proto static metric 48 
10.48.55.0/24 dev ens35 proto kernel scope link src 10.48.55.133 metric 101 
···

$ oc patch network.operator cluster -p '{"spec":{"defaultNetwork":{"ovnKubernetesConfig": {"gatewayConfig": {"routingViaHost": true} }}}}' --type=merge
$ oc patch network.operator cluster --type=merge -p '{"spec":{"defaultNetwork":{"ovnKubernetesConfig":{"gatewayConfig":{"ipForwarding": "Global"}}}}}'

# Waiting for the cluster operator update to complete.
oc get co

$ oc new-project test
$ oc new-app --name loadtest --image quay.io/redhattraining/loadtest:v1.0
$ oc patch deployment loadtest --type='merge' -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"worker02.ocp.example.com"}}}}}'

$ oc get po -o wide
NAME                        READY   STATUS    RESTARTS   AGE    IP           NODE                       NOMINATED NODE   READINESS GATES
loadtest-85748d597d-6dwhk   1/1     Running   0          109s   10.129.2.7   worker02.ocp.example.com   <none>           <none>

$ oc rsh loadtest-85748d597d-6dwhk
(app-root)sh-4.2$ ping 10.48.55.125
PING 10.48.55.125 (10.48.55.125) 56(84) bytes of data.
64 bytes from 10.48.55.125: icmp_seq=1 ttl=63 time=3.41 ms
64 bytes from 10.48.55.125: icmp_seq=2 ttl=63 time=1.60 ms
64 bytes from 10.48.55.125: icmp_seq=3 ttl=63 time=0.588 ms

oc patch network.operator cluster --type=merge -p '{"spec":{"defaultNetwork":{"ovnKubernetesConfig":{"gatewayConfig":{"ipForwarding":null}}}}}'

# Waiting for the cluster operator update to complete.
oc get co

$ oc rsh loadtest-85748d597d-6dwhk
(app-root)sh-4.2$ ping 10.48.55.125
PING 10.48.55.125 (10.48.55.125) 56(84) bytes of data.
^C
--- 10.48.55.125 ping statistics ---
4 packets transmitted, 0 received, 100% packet loss, time 3056ms

(app-root)sh-4.2$ 
```


### After assigning an IP to the node’s secondary network interface, set routingViaHost to true and enable forwarding (1) on the secondary interface to allow Pods to communicate through the secondary network.
```
cat << EOF | oc apply -f -
apiVersion: nmstate.io/v1
kind: NodeNetworkConfigurationPolicy
metadata:
  name: worker03-static-ip-ens35-policy 
spec:
  nodeSelector:
    kubernetes.io/hostname: worker03.ocp.example.com
  desiredState:
    interfaces:
    - name: ens35
      type: ethernet
      state: up
      ipv4:
        address:
        - ip: 10.48.55.131
          prefix-length: 24
        dhcp: false
        enabled: true
EOF

$ ssh core@worker03.ocp.example.com sudo ip ad |grep br-ex
7: br-ex: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UNKNOWN group default qlen 1000
    inet 10.184.134.59/24 brd 10.184.134.255 scope global noprefixroute br-ex
    inet 169.254.0.2/17 brd 169.254.127.255 scope global br-ex

$ ssh core@worker03.ocp.example.com sudo ip ad |grep ens35
27: ens35: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    inet 10.48.55.131/24 brd 10.48.55.255 scope global noprefixroute ens35

$ ssh core@worker03.ocp.example.com sudo ip route
default via 10.184.134.1 dev br-ex proto static metric 48 
10.48.55.0/24 dev ens35 proto static scope link 
10.48.55.0/24 dev ens35 proto kernel scope link src 10.48.55.131 metric 101 
···

$ oc patch network.operator cluster -p '{"spec":{"defaultNetwork":{"ovnKubernetesConfig": {"gatewayConfig": {"routingViaHost": true} }}}}' --type=merge

$ oc patch deployment loadtest --type='merge' -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"worker03.ocp.example.com"}}}}}'

$ oc get po -o wide
NAME                        READY   STATUS        RESTARTS   AGE   IP           NODE                       NOMINATED NODE   READINESS GATES
loadtest-7bfb9c6b47-zk2bp   1/1     Running       0          29s   10.131.0.9   worker03.ocp.example.com   <none>           <none>

$ oc rsh loadtest-7bfb9c6b47-zk2bp
(app-root)sh-4.2$ ping 10.48.55.125
PING 10.48.55.125 (10.48.55.125) 56(84) bytes of data.
^C
--- 10.48.55.125 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2039ms

$ ssh core@worker03.ocp.example.com sudo sysctl -w net.ipv4.conf.ens35.forwarding=1
$ ssh core@worker03.ocp.example.com sudo sysctl -w net.ipv6.conf.ens35.forwarding=1

$ oc rsh loadtest-7bfb9c6b47-zk2bp
(app-root)sh-4.2$ ping 10.48.55.125
PING 10.48.55.125 (10.48.55.125) 56(84) bytes of data.
64 bytes from 10.48.55.125: icmp_seq=1 ttl=63 time=2.05 ms
64 bytes from 10.48.55.125: icmp_seq=2 ttl=63 time=1.17 ms
64 bytes from 10.48.55.125: icmp_seq=3 ttl=63 time=0.397 ms

# persistence
SECOND_INTERFACE=ens35
BASE64=$(echo -e "net.ipv4.conf.$SECOND_INTERFACE.forwarding = 1\nnet.ipv6.conf.$SECOND_INTERFACE.forwarding = 1" | base64 -w0)

oc apply -f - <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 81-enable-${SECOND_INTERFACE}-forwarding
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf8;base64,${BASE64}
        verification: {}
        filesystem: root
        mode: 420
        path: /etc/sysctl.d/enable-${SECOND_INTERFACE}-forwarding.conf
  osImageURL: ""
EOF



NODE_ROLE=worker
SECOND_INTERFACE=ens35
cat << EOF | oc apply -f -
apiVersion: tuned.openshift.io/v1
kind: Tuned
metadata:
  name: $NODE_ROLE-$SECOND_INTERFACE-forwarding
  namespace: openshift-cluster-node-tuning-operator
spec:
  profile:
  - name: $SECOND_INTERFACE-forwarding-profile
    data: |
      [main]
      summary=Enable IP forwarding on $SECOND_INTERFACE
      include=openshift-node

      [sysctl]
      net.ipv4.conf.$SECOND_INTERFACE.forwarding=1
      net.ipv6.conf.$SECOND_INTERFACE.forwarding=1

  recommend:
  - match:
    - label: node-role.kubernetes.io/$NODE_ROLE
    priority: 20
    profile: $SECOND_INTERFACE-forwarding-profile
EOF
```
