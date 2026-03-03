```
$ yum install -y httpd
$ sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf 

$ cat > /var/www/html/materials/index.html << EOF
Hello, world from nginx!
EOF

$ systemctl restart httpd
$ curl http://10.184.134.30:8080/index.html | grep Hello
$ tail -10 /var/log/httpd/access_log 

$ cat << EOF | oc apply -f -
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

$ oc new-project test
$ oc new-app --name loadtest --image quay.io/redhattraining/loadtest:v1.0

$ oc label ns test env=egress-ip
$ oc label nodes worker03.ocp.example.com k8s.ovn.org/egress-assignable="" 

$ cat << EOF | oc apply -f -
apiVersion: k8s.ovn.org/v1
kind: EgressIP
metadata:
  name: egress-project
spec:
  egressIPs:
  - 10.48.55.137
  namespaceSelector:
    matchLabels:
      env: egress-ip
EOF

$ oc get eip
NAME             EGRESSIPS      ASSIGNED NODE              ASSIGNED EGRESSIPS
egress-project   10.48.55.135   worker03.ocp.example.com   10.48.55.135

$ ssh core@worker03.ocp.example.com sudo ip ad |grep ens35
27: ens35: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    inet 10.48.55.131/24 brd 10.48.55.255 scope global noprefixroute ens35
    inet 10.48.55.135/32 scope global ens35

$ oc -n test rsh deployments/loadtest 
(app-root)sh-4.2$ ping 10.48.55.125
PING 10.48.55.125 (10.48.55.125) 56(84) bytes of data.
^C

$ NODE_ROLE=worker
$ SECOND_INTERFACE=ens35
$ cat << EOF | oc apply -f -
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

$ oc get tuned -n openshift-cluster-node-tuning-operator

$ oc rsh deployments/loadtest 
(app-root)sh-4.2$ ping 10.48.55.125
PING 10.48.55.125 (10.48.55.125) 56(84) bytes of data.
64 bytes from 10.48.55.125: icmp_seq=28 ttl=62 time=1.41 ms
64 bytes from 10.48.55.125: icmp_seq=29 ttl=62 time=1.29 ms
64 bytes from 10.48.55.125: icmp_seq=30 ttl=62 time=1.70 ms
64 bytes from 10.48.55.125: icmp_seq=31 ttl=62 time=1.43 ms
64 bytes from 10.48.55.125: icmp_seq=32 ttl=62 time=0.487 ms

(app-root)sh-4.2$ curl http://10.48.55.125:8080/index.html
Hello, world from nginx!

tail -10 /var/log/httpd/access_log 
10.184.134.30 - - [02/Feb/2026:00:59:21 +0000] "GET /index.html HTTP/1.1" 404 196 "-" "curl/7.76.1"
10.48.55.137 - - [02/Feb/2026:01:07:23 +0000] "GET /index.html HTTP/1.1" 200 72 "-" "curl/7.29.0"
10.48.55.137 - - [02/Feb/2026:01:07:28 +0000] "GET /index.html HTTP/1.1" 200 72 "-" "curl/7.29.0
```
