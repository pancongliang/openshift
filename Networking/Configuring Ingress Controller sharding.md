## Configuring Ingress Controller sharding

### 1.Prerequisites

**1.1 Domain info:**
~~~
default ingress: apps.ocp4.example.com
custom ingress:  apps.test.example.com
~~~

**1.2 bastion(DNS/HAproxy) info:**
~~~
$ cat /etc/sysconfig/network-scripts/ifcfg-ens3 
...
DEVICE=ens3
ONBOOT=yes
IPADDR=10.74.250.185        #<-- api-int/api ip
PREFIX=21
IPADDR2=10.74.250.186       #<-- default ingress: apps.ocp4.example.com
PREFIX2=21
IPADDR3=10.74.250.190       #<-- custom ingress:  apps.test.example.com
PREFIX3=21
GATEWAY=10.74.255.254
DNS1=10.74.250.185
~~~

**1.3 Add DNS resolve:**
~~~
$ cat /var/named/example.com.zone 
$TTL 1W
@       IN      SOA     ns1.example.com.        root (
                        2019070702      ; serial
                        3H              ; refresh (3 hours)
                        30M             ; retry (30 minutes)
                        2W              ; expiry (2 weeks)
                        1W )            ; minimum (1 week)
        IN      NS      ns1.example.com.
        IN      NS      ns2.example.com.
;
ns1     IN      A       10.74.250.185
ns2     IN      A       10.74.251.168
;
; The api identifies the IP of your load balancer.
api.ocp4.example.com.                  IN      A       10.74.250.185
api-int.ocp4.example.com.              IN      A       10.74.250.185
;
; The wildcard also identifies the load balancer.
*.apps.ocp4.example.com.               IN      A       10.74.250.186
*.apps.test.example.com.               IN      A       10.74.250.190   #<-- new add custom ingress
;
; Create entries for the master hosts.
master01.ocp4.example.com.             IN      A       10.74.253.114
master02.ocp4.example.com.             IN      A       10.74.249.135
master03.ocp4.example.com.             IN      A       10.74.249.217
;
; Create entries for the worker hosts.
worker01.ocp4.example.com.             IN      A       10.74.252.87
worker02.ocp4.example.com.             IN      A       10.74.255.215
worker03.ocp4.example.com.             IN      A       10.74.249.22
;
; Create an entry for the bootstrap host.
bootstrap.ocp4.example.com.            IN      A       10.74.252.146
;
; Create entries for the mirror registry hosts.
bastion.ocp4.example.com.              IN      A       10.74.250.185
mirror.registry.example.com.           IN      A       10.74.251.168
~~~

**1.4 Haproxy:**
~~~
$ cat /etc/haproxy/haproxy.cfg
 # all frontend
frontend  default-router-http-traffic              #<-- Default ingress
    bind 10.74.250.186:80                          #<-- Specify default ingress IP:PORT
    default_backend default-router-http-traffic
    mode tcp
    option tcplog
 
frontend  default-router-https-traffic             #<-- Default ingress
    bind 10.74.250.186:443                         #<-- Specify default ingress IP:PORT
    default_backend default-router-https-traffic
    mode tcp
    option tcplog
 
frontend  custom-router-http-traffic               #<-- Custom ingress
    bind 10.74.250.190:80                          #<-- Specify custom ingress IP:PORT
    default_backend custom-router-http-traffic
    mode tcp
    option tcplog

frontend  custom-router-https-traffic              #<-- Custom ingress
    bind 10.74.250.190:443                         #<-- Specify custom ingress IP:PORT
    default_backend custom-router-https-traffic
    mode tcp
    option tcplog

frontend  k8s-api-server
    bind *:6443                                   #<-- Specify api/api-int IP(1.1.1.1:6443,1.1.1.2:6443) or *:6443
    default_backend k8s-api-server
    mode tcp
    option tcplog
 
frontend  machine-config-server
    bind *:22623                                  #<-- Specify api/api-int IP(1.1.1.1:22623,1.1.1.2:22623) or *:22623
    default_backend machine-config-server
    mode tcp
    option tcplog

 # all backend
backend default-router-http-traffic                                #<-- Default ingress
        balance source                                           
        mode tcp
        server          worker01.ocp4.example.com 10.74.252.87:80 check   #<-- Specify the node info of the default ingress pod
        server          worker02.ocp4.example.com 10.72.255.215:80 check  #<-- Specify the node info of the default ingress pod
 
backend default-router-https-traffic                               #<-- Default ingress
        balance source
        mode tcp
        server          worker01.ocp4.example.com 10.74.252.87:443 check  #<-- Specify the node info of the default ingress pod
        server          worker02.ocp4.example.com 10.72.255.215:443 check #<-- Specify the node info of the default ingress pod

backend custom-router-http-traffic                                 #<-- Custom ingress
        balance source 
        mode tcp
        server          worker03.ocp4.example.com 10.74.249.22:80 check   #<-- Specify the node info of the default ingress pod

backend custom-router-https-traffic                                #<-- Custom ingress
        balance source                                               
        mode tcp
        server          worker03.ocp4.example.com 10.74.249.22:443 check  #<-- Specify the node info of the default ingress pod

backend k8s-api-server
        balance source
        mode tcp
        server          bootstrap.ocp4.example.com 10.74.252.146:6443 check
        server          master01.ocp4.example.com 10.74.253.114:6443 check
        server          master02.ocp4.example.com 10.74.249.135:6443 check
        server          master03.ocp4.example.com 10.74.249.217:6443 check

backend machine-config-server
        balance source
        mode tcp
        server          bootstrap.ocp4.example.com 10.74.252.146:22623 check
        server          master01.ocp4.example.com 10.74.253.114:22623 check
        server          master02.ocp4.example.com 10.74.249.135:22623 check
        server          master03.ocp4.example.com 10.74.249.217:22623 chec
~~~


### 2.Create custom ingress

**2.1 Create mcp:**
~~~
$ cat single.mcp.yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfigPool
metadata:
  name: infra
spec:
  machineConfigSelector:
    matchExpressions:
      - {key: machineconfiguration.openshift.io/role, operator: In, values: [worker,infra]}
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/infra: ""

$ oc label node worker03.ocp4.example.com node-role.kubernetes.io/infra="" 
~~~

**2.2 Create custom ingress:**
~~~
$ vim custom-ingress.yaml
apiVersion: v1
items:
- apiVersion: operator.openshift.io/v1
  kind: IngressController
  metadata:
    name: router-custom
    namespace: openshift-ingress-operator
  spec:
    replicas: 1
    domain: apps.test.example.com
    nodePlacement:
      nodeSelector:
        matchLabels:
          node-role.kubernetes.io/infra: ""
    namespaceSelector:
      matchLabels:
        type: sharded
  status: {}
kind: List
metadata:
  resourceVersion: ""
  selfLink: ""

$ oc apply -f custom-ingress.yaml
~~~

**2.3 Confirm status:**
~~~
$ oc get po -o wide -n openshift-ingress
NAME                                     READY   STATUS    RESTARTS   AGE     IP              NODE                      
router-custom-5cf4598ccb-lr8wp           1/1     Running   2          39h     10.74.249.22    worker03.ocp4.example.com  #<-- custom ingress
router-default-6c8b4d6c7c-4xgzm          1/1     Running   1          2d11h   10.74.255.215   worker02.ocp4.example.com 
router-default-6c8b4d6c7c-rf6vv          1/1     Running   2          2d11h   10.74.252.87    worker01.ocp4.example.com

$ oc get ingresscontroller -n openshift-ingress-operator
NAME             AGE
router-custom    39h
default          37d

$ oc get co 
~~~

### 3. Test custom ingress
~~~
$ oc new-project nginx
$ oc label namespaces nginx type=sharded
$ oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
$ oc get svc
$ oc expose svc/nginx --hostname nginx.apps.test.example.com
$ curl nginx.apps.test.example.com | grep Hello
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100    72  100    72    0     0  14400      0 --:--:-- --:--:-- --:--:-- 14400
    <h1>Hello, world from nginx!</h1>
~~~
