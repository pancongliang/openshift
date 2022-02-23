## Configuring egress IPs for a project

### 介绍
默认情况下，所有 namespace 出口网络都将使用 pod 所在的主机 IP 作为 SNAT 规则，类似于我们的家庭路由器如何访问互联网。
对于访问控制和可追溯性，这会带来一些困难和安全问题，因为所有 pod，无论其当前部署的是哪个命名空间，都将使用运行该 pod 的公共主机 IP。
对于 OpenShift，我们有一个称为EgressIP的概念。使用 EgressIP，我们可以配置一个 IP（或一组 IP）以分配给我们需要对出口路由进行更细粒度控制的特定命名空间。在整个命名空间生命周期中，它将使用分配的 EgressIP(s) 用于到外部网络的任何出口连接（从 SDN 层出来).

**两种类型的 EgressIP 配置:**
   - Automatically assigned EgressIP
   - Manually assigned EgressIP


### 为了测试先准备环境

**1. 创建一个简单的 httpd 服务器**
~~~
$ yum install -y httpd

$ sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf 

$ cat > /var/www/html/index.html << EOF
<html>
  <body>
    <h1>Hello, world from nginx!</h1>
  </body>
</html>
EOF

$ systemctl restart httpd

$ curl http://10.72.37.162:8080/index.html | grep Hello

$ tail -10 /var/log/httpd/access_log  #<-- 在这里可以确认访问 ip 地址
  10.72.36.156 - - [18/Feb/2022:14:12:48 +0800] "GET /index.html HTTP/1.1" 200 72 "-" "curl/7.29.0"
~~~


### Automatically assigned EgressIP（高可用）

**1. 创建需要设置 egress ip 的 project:**
~~~
$ oc new-project test
$ oc new-app --name loadtest --docker-image=quay.io/redhattraining/loadtest:v1.0
~~~

**2. 为 namespace/node 手动设置 static egress ip（namespace ip 为高可用，因此可以在配置 egress ip的 node 之间进行漂移）:**

**- 选项 A: 设置 node egress ip 范围:**

a. 为 test namespace 设置 egress ip:
~~~
$ oc patch netnamespace test --type=merge -p \
  '{"egressIPs": [ "10.72.36.156" ]}'

$ oc get netnamespace test
NAME   NETID     EGRESS IPS
test   8747060   ["10.72.36.156"]
~~~

b. 为 node 设置 egress ip 范围:
~~~
$ oc patch hostsubnet worker01.ocp4.example.com --type=merge -p \
  '{"egressCIDRs": ["10.72.36.0/23"]}'

$ oc patch hostsubnet worker02.ocp4.example.com --type=merge -p \
  '{"egressCIDRs": ["10.72.36.0/23"]}'

$ oc get hostsubnet 
NAME                        HOST                        HOST IP        SUBNET          EGRESS CIDRS        EGRESS IPS
worker01.ocp4.example.com   worker01.ocp4.example.com   10.72.36.154   10.131.0.0/23   ["10.72.36.0/23"]   ["10.72.36.156"]
worker02.ocp4.example.com   worker02.ocp4.example.com   10.72.36.155   10.128.2.0/23   ["10.72.36.0/23"]   []

$ ssh core@worker01.ocp4.example.com ip a show dev ens3
2: ens3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:1a:4a:16:02:a3 brd ff:ff:ff:ff:ff:ff
    inet 10.72.36.154/23 brd 10.72.37.255 scope global noprefixroute ens3
       valid_lft forever preferred_lft forever
    inet 10.72.36.156/23 brd 10.72.37.255 scope global secondary ens3:eip
       valid_lft forever preferred_lft forever 

$ ssh core@worker02.ocp4.example.com ip a show dev ens3
2: ens3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:1a:4a:16:02:22 brd ff:ff:ff:ff:ff:ff
    inet 10.72.36.155/23 brd 10.72.37.255 scope global noprefixroute ens3
       valid_lft forever preferred_lft forever
~~~

c. 测试可用性:
~~~
$ oc get po -o wide -n test
NAME                        READY   STATUS    RESTARTS   AGE    IP            NODE
loadtest-584bc4f487-kgz8d   1/1     Running   0          143m   10.130.1.53   master03.ocp4.example.com 

$ oc get no
NAME                        STATUS   ROLES           AGE   VERSION
worker01.ocp4.example.com   Ready    worker          62d   v1.20.0+558d959
worker02.ocp4.example.com   Ready    worker          50d   v1.20.0+558d959

$ oc rsh loadtest-584bc4f487-kgz8d curl http://10.72.37.162:8080/index.html | grep Hello
    <h1>Hello, world from nginx!</h1>

$ tail -1 /var/log/httpd/access_log
10.72.36.156 - - [18/Feb/2022:16:32:25 +0800] "GET /index.html HTTP/1.1" 200 72 "-" "curl/7.29.0"

$ oc get no
NAME                        STATUS     ROLES         AGE   VERSION
worker01.ocp4.example.com   NotReady   worker        62d   v1.20.0+558d959
worker02.ocp4.example.com   Ready      worker        50d   v1.20.0+558d959

$ oc get hostsubnet
NAME                        HOST                        HOST IP        SUBNET        EGRESS CIDRS          EGRESS IPS
worker01.ocp4.example.com   worker01.ocp4.example.com   10.72.36.154   10.131.0.0/23   ["10.72.36.0/23"]   
worker02.ocp4.example.com   worker02.ocp4.example.com   10.72.36.155   10.128.2.0/23   ["10.72.36.0/23"]   ["10.72.36.156"]

$ ssh core@worker02.ocp4.example.com ip a show dev ens3
2: ens3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:1a:4a:16:02:22 brd ff:ff:ff:ff:ff:ff
    inet 10.72.36.155/23 brd 10.72.37.255 scope global noprefixroute ens3
       valid_lft forever preferred_lft forever
    inet 10.72.36.156/23 brd 10.72.37.255 scope global secondary ens3:eip
       valid_lft forever preferred_lft forever

$ oc rsh loadtest-584bc4f487-kgz8d curl http://10.72.37.162:8080/index.html | grep Hello
    <h1>Hello, world from nginx!</h1>

- 关闭了worker01节点后，需要等待片刻，egress ip 依旧可用:
$ tail -1 /var/log/httpd/access_log
10.72.36.156 - - [18/Feb/2022:16:35:08 +0800] "GET /index.html HTTP/1.1" 200 72 "-" "curl/7.29.0"

- worker01 启动后 ns egress ip 不会漂移回去，继续在worker02上工作:
$ oc get hostsubnet
NAME                        HOST                          HOST IP        SUBNET        EGRESS CIDRS        EGRESS IPS
worker01.ocp4.example.com   worker01.ocp4.example.com   10.72.36.154   10.131.0.0/23   ["10.72.36.0/23"]   
worker02.ocp4.example.com   worker02.ocp4.example.com   10.72.36.155   10.128.2.0/23   ["10.72.36.0/23"]   ["10.72.36.156"]

$ oc get no
NAME                        STATUS     ROLES         AGE   VERSION
worker01.ocp4.example.com   Ready      worker        62d   v1.20.0+558d959
worker02.ocp4.example.com   NotReady   worker        50d   v1.20.0+558d959

$ oc get hostsubnet
NAME                        HOST                          HOST IP        SUBNET        EGRESS CIDRS        EGRESS IPS
worker01.ocp4.example.com   worker01.ocp4.example.com   10.72.36.154   10.131.0.0/23   ["10.72.36.0/23"]   ["10.72.36.156"]
worker02.ocp4.example.com   worker02.ocp4.example.com   10.72.36.155   10.128.2.0/23   ["10.72.36.0/23"]
 
$ oc rsh loadtest-584bc4f487-kgz8d curl http://10.72.37.162:8080/index.html | grep Hello
    <h1>Hello, world from nginx!</h1>

$ tail -1 /var/log/httpd/access_log
10.72.36.156 - - [18/Feb/2022:16:47:04 +0800] "GET /index.html HTTP/1.1" 200 72 "-" "curl/7.29.0"
~~~


**- 选项 B: 设置 node egress 固定 ip（使用不同的掩码固定ip，但子网相同）**

a. 为 test namespace 设置 egress ip:
~~~
$ oc patch netnamespace test --type=merge -p \
  '{"egressIPs": [ "10.72.36.156" ]}'

$ oc get netnamespace test
NAME   NETID     EGRESS IPS
test   8747060   ["10.72.36.156"]
~~~

b. 为 node 设置 egress 固定ip:
~~~
- 使用 egressCIDRs 固定 egress ip，因掩码是23位（254个ip可用），因此报掩码错误，无法通信

$ oc patch hostsubnet worker01.ocp4.example.com --type=merge -p \
  '{"egressCIDRs": ["10.72.36.156/23"]}'  

$ oc patch hostsubnet worker02.ocp4.example.com --type=merge -p \
  '{"egressCIDRs": ["10.72.36.156/23"]}'

$ oc logs sdn-bd96x -c sdn -n openshift-sdn
E0218 10:45:00.414705    2545 egressip.go:183] Ignoring invalid HostSubnet worker01.ocp4.example.com (host: "worker01.ocp4.example.com", ip: "10.72.36.154", subnet: "10.131.0.0/23"): egressCIDRs[0]: Invalid value: "10.72.36.156/23": CIDR network specification "10.72.36.156/23" is not in canonical form (should be 10.72.36.0/23 or 10.72.36.156/32?)
E0218 10:45:04.120290    2545 egressip.go:183] Ignoring invalid HostSubnet worker02.ocp4.example.com (host: "worker02.ocp4.example.com", ip: "10.72.36.155", subnet: "10.128.2.0/23"): egressCIDRs[0]: Invalid value: "10.72.36.156/23": CIDR network specification "10.72.36.156/23" is not in canonical form (should be 10.72.36.0/23 or 10.72.36.156/32?)

$ oc rsh -n test loadtest-584bc4f487-kgz8d curl http://10.72.37.162:8080/index.html | grep Hello
command terminated with exit code 130

- 使用 egressCIDRs 固定 egress ip，指定一个子网内的正确掩码（这个32位掩码可用 ip 仅限于10.72.36.156）, 测试可行:
$ oc patch hostsubnet worker01.ocp4.example.com --type=merge -p \
  '{"egressCIDRs": ["10.72.36.156/32"]}'

$ oc patch hostsubnet worker02.ocp4.example.com --type=merge -p \
  '{"egressCIDRs": ["10.72.36.156/32"]}'

$ oc get hostsubnet
NAME                        HOST                        HOST IP        SUBNET          EGRESS CIDRS          EGRESS IPS
worker01.ocp4.example.com   worker01.ocp4.example.com   10.72.36.154   10.131.0.0/23   ["10.72.36.156/32"]   ["10.72.36.156"]
worker02.ocp4.example.com   worker02.ocp4.example.com   10.72.36.155   10.128.2.0/23   ["10.72.36.156/32"] 

$ ssh core@worker01.ocp4.example.com ip a show dev ens3
2: ens3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:1a:4a:16:02:a3 brd ff:ff:ff:ff:ff:ff
    inet 10.72.36.154/23 brd 10.72.37.255 scope global noprefixroute ens3
       valid_lft forever preferred_lft forever
    inet 10.72.36.156/23 brd 10.72.37.255 scope global secondary ens3:eip
       valid_lft forever preferred_lft forever

$ ssh core@worker02.ocp4.example.com ip a show dev ens3
2: ens3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:1a:4a:16:02:22 brd ff:ff:ff:ff:ff:ff
    inet 10.72.36.155/23 brd 10.72.37.255 scope global noprefixroute ens3
       valid_lft forever preferred_lft forever
~~~

c. 测试可用性:
~~~
$ oc rsh -n test loadtest-584bc4f487-kgz8d curl http://10.72.37.162:8080/index.html | grep Hello
    <h1>Hello, world from nginx!</h1>

$ tail -1 /var/log/httpd/access_log
10.72.36.156 - - [18/Feb/2022:18:48:52 +0800] "GET /index.html HTTP/1.1" 200 72 "-" "curl/7.29.0"

$ oc get no
NAME                        STATUS     ROLES           AGE   VERSION
worker01.ocp4.example.com   NotReady   worker          62d   v1.20.0+558d959
worker02.ocp4.example.com   Ready      worker          50d   v1.20.0+558d959

$ oc get hostsubnet
NAME                        HOST                        HOST IP        SUBNET          EGRESS CIDRS          EGRESS IPS
worker01.ocp4.example.com   worker01.ocp4.example.com   10.72.36.154   10.131.0.0/23   ["10.72.36.156/32"]   
worker02.ocp4.example.com   worker02.ocp4.example.com   10.72.36.155   10.128.2.0/23   ["10.72.36.156/32"]   ["10.72.36.156"]

$ ssh core@worker02.ocp4.example.com ip a show dev ens3
2: ens3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:1a:4a:16:02:22 brd ff:ff:ff:ff:ff:ff
    inet 10.72.36.155/23 brd 10.72.37.255 scope global noprefixroute ens3
       valid_lft forever preferred_lft forever
    inet 10.72.36.156/23 brd 10.72.37.255 scope global secondary ens3:eip
       valid_lft forever preferred_lft forever

$ oc rsh -n test loadtest-584bc4f487-kgz8d curl http://10.72.37.162:8080/index.html | grep Hello
    <h1>Hello, world from nginx!</h1>

$ tail -1 /var/log/httpd/access_log
10.72.36.156 - - [18/Feb/2022:18:56:54 +0800] "GET /index.html HTTP/1.1" 200 72 "-" "curl/7.29.0"

$ oc get no
NAME                        STATUS     ROLES           AGE   VERSION
worker01.ocp4.example.com   Ready      worker          62d   v1.20.0+558d959
worker02.ocp4.example.com   NotReady   worker          50d   v1.20.0+558d959

$ oc get hostsubnet
NAME                        HOST                        HOST IP        SUBNET          EGRESS CIDRS          EGRESS IPS
worker01.ocp4.example.com   worker01.ocp4.example.com   10.72.36.154   10.131.0.0/23   ["10.72.36.156/32"]   ["10.72.36.156"]
worker02.ocp4.example.com   worker02.ocp4.example.com   10.72.36.155   10.128.2.0/23   ["10.72.36.156/32"]  

$ ssh core@worker01.ocp4.example.com ip a show dev ens3
2: ens3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:1a:4a:16:02:a3 brd ff:ff:ff:ff:ff:ff
    inet 10.72.36.154/23 brd 10.72.37.255 scope global noprefixroute ens3
       valid_lft forever preferred_lft forever
    inet 10.72.36.156/23 brd 10.72.37.255 scope global secondary ens3:eip
       valid_lft forever preferred_lft forever

$ oc rsh -n test loadtest-584bc4f487-kgz8d curl http://10.72.37.162:8080/index.html | grep Hello
    <h1>Hello, world from nginx!</h1>

$ tail -1 /var/log/httpd/access_log
10.72.36.156 - - [18/Feb/2022:19:08:53 +0800] "GET /index.html HTTP/1.1" 200 72 "-" "curl/7.29.0"
~~~


### Manually assigned EgressIP

**1. 创建需要设置 egress ip 的 project**

~~~
$ oc new-project test
$ oc new-app --name loadtest --docker-image=quay.io/redhattraining/loadtest:v1.0
~~~

**2. 为 namespace/node 手动设置 static egress ip**

**- 选项 A: 无需高可用性时指定一个 egress ip (存在单点故障)**

a. 为 test namespace 手动设置 static egress ip: 
~~~
$ oc patch netnamespace test --type=merge -p \
  '{"egressIPs": [ "10.72.36.156" ]}'

$ oc get netnamespace test
NAME   NETID     EGRESS IPS
test   8747060   ["10.72.36.156"]
~~~

b. 为 node 手动设置 static egress ip: 
~~~
- 为 node 设置 static egress ip 时 node egress ip 与 namespace egress ip 相同
$ oc patch hostsubnet worker01.ocp4.example.com --type=merge -p \
  '{"egressIPs": [ "10.72.36.156"]}'

$ oc get hostsubnet
NAME                          HOST                          HOST IP        SUBNET          EGRESS CIDRS   EGRESS IPS                  
worker01.ocp4.example.com   worker01.ocp4.example.com   10.72.36.154   10.131.0.0/23                      ["10.72.36.156"]
worker02.ocp4.example.com   worker02.ocp4.example.com   10.72.36.155   10.128.2.0/23

$ ssh core@worker01.ocp4.example.com ip a show dev ens3
2: ens3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:1a:4a:16:02:a3 brd ff:ff:ff:ff:ff:ff
    inet 10.72.36.154/23 brd 10.72.37.255 scope global noprefixroute ens3
       valid_lft forever preferred_lft forever
    inet 10.72.36.156/23 brd 10.72.37.255 scope global secondary ens3:eip   #<-- egress ip 会自动附加到worker网卡上
       valid_lft forever preferred_lft forever          
~~~

c. 测试可用性:
~~~
$ oc get po -o wide -n test
NAME                        READY   STATUS    RESTARTS   AGE    IP            NODE
loadtest-584bc4f487-kgz8d   1/1     Running   0          143m   10.130.1.53   master03.ocp4.example.com 

$ oc rsh loadtest-584bc4f487-kgz8d curl http://10.72.37.162:8080/index.html | grep Hello
    <h1>Hello, world from nginx!</h1>

$ tail -1 /var/log/httpd/access_log
10.72.36.156 - - [18/Feb/2022:15:41:10 +0800] "GET /index.html HTTP/1.1" 200 72 "-" "curl/7.29.0"

$ oc get no
NAME                        STATUS     ROLES           AGE   VERSION
worker01.ocp4.example.com   NotReady   worker          62d   v1.20.0+558d959

$ oc rsh loadtest-584bc4f487-kgz8d curl http://10.72.37.162:8080/index.html | grep Hello
^Ccommand terminated with exit code 130
~~~

**- 选项 B: 为了考虑高可用性，可以指定多个 egress ip**

a. 为 test namespace 手动设置两个 static egress ip 
~~~
$ oc patch netnamespace test --type=merge -p \
  '{"egressIPs": [ "10.72.36.156","10.72.36.157" ]}'

$ oc get netnamespace test
NAME   NETID     EGRESS IPS
test   8747060   ["10.72.36.156","10.72.36.157"]
~~~

b. 为 node 手动设置 static egress ip:
~~~
- 为 node 设置 static egress ip 时 node egress ip 与 ns egress ip 相同，
- 每个节点都应该有一个特定的 egress ip，并且该 egress ip 不能分配给另一个节点，不然sdn pod会报错(Multiple nodes (10.72.36.154, 10.72.36.155) claiming EgressIP 10.72.36.156)。

$ oc patch hostsubnet worker01.ocp4.example.com --type=merge -p \
  '{"egressIPs": [ "10.72.36.156"]}'

$ oc patch hostsubnet worker02.ocp4.example.com --type=merge -p \
  '{"egressIPs": [ "10.72.36.157"]}'

$ oc get hostsubnet
NAME                        HOST                        HOST IP        SUBNET          EGRESS CIDRS   EGRESS IPS                 
worker01.ocp4.example.com   worker01.ocp4.example.com   10.72.36.154   10.131.0.0/23                  ["10.72.36.156"]
worker02.ocp4.example.com   worker02.ocp4.example.com   10.72.36.155   10.128.2.0/23                  ["10.72.36.157"]

$ ssh core@worker01.ocp4.example.com ip a show dev ens3
2: ens3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:1a:4a:16:02:a3 brd ff:ff:ff:ff:ff:ff
    inet 10.72.36.154/23 brd 10.72.37.255 scope global noprefixroute ens3
       valid_lft forever preferred_lft forever
    inet 10.72.36.156/23 brd 10.72.37.255 scope global secondary ens3:eip   #<-- egress ip 会自动附加到worker网卡上
       valid_lft forever preferred_lft forever

$ ssh core@worker02.ocp4.example.com ip a show dev ens3
2: ens3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    link/ether 00:1a:4a:16:02:22 brd ff:ff:ff:ff:ff:ff
    inet 10.72.36.155/23 brd 10.72.37.255 scope global noprefixroute ens3
       valid_lft forever preferred_lft forever
    inet 10.72.36.157/23 brd 10.72.37.255 scope global secondary ens3:eip  #<-- egress ip 会自动附加到worker网卡上
       valid_lft forever preferred_lft forever
~~~

c. 测试可用性:
~~~
$ oc get po -o wide -n test
NAME                        READY   STATUS    RESTARTS   AGE    IP            NODE
loadtest-584bc4f487-kgz8d   1/1     Running   0          143m   10.130.1.53   master03.ocp4.example.com 

$ oc get no
NAME                        STATUS     ROLES         AGE   VERSION
worker01.ocp4.example.com   Ready    worker          62d   v1.20.0+558d959
worker02.ocp4.example.com   Ready    worker          50d   v1.20.0+558d959

$ oc rsh loadtest-584bc4f487-kgz8d curl http://10.72.37.162:8080/index.html | grep Hello
    <h1>Hello, world from nginx!</h1>

$ tail -1 /var/log/httpd/access_log
10.72.36.156 - - [18/Feb/2022:15:53:11 +0800] "GET /index.html HTTP/1.1" 200 72 "-" "curl/7.29.0"

$ oc get no
NAME                        STATUS     ROLES           AGE   VERSION
worker01.ocp4.example.com   NotReady   worker          62d   v1.20.0+558d959
worker02.ocp4.example.com   Ready      worker          50d   v1.20.0+558d959

$ oc rsh loadtest-584bc4f487-kgz8d curl http://10.72.37.162:8080/index.html | grep Hello
    <h1>Hello, world from nginx!</h1>

- 关闭了worker01节点后，需要等待片刻，可以看到egress ip发生了变化，使用了第二个egress ip，此项是根据设置egress ip顺序排序
$ tail -1 /var/log/httpd/access_log
10.72.36.157 - - [18/Feb/2022:16:02:27 +0800] "GET /index.html HTTP/1.1" 200 72 "-" "curl/7.29.0"

$ oc get no
NAME                        STATUS     ROLES           AGE   VERSION
worker01.ocp4.example.com   Ready      worker          62d   v1.20.0+558d959
worker02.ocp4.example.com   NotReady   worker          50d   v1.20.0+558d959

- 当关闭了worker02节点后可以看到egress ip使用了第一个egress ip，
$ oc rsh loadtest-584bc4f487-kgz8d curl http://10.72.37.162:8080/index.html
    <h1>Hello, world from nginx!</h1>

$ tail -1 /var/log/httpd/access_log
10.72.36.156 - - [18/Feb/2022:16:12:50 +0800] "GET /index.html HTTP/1.1" 200 72 "-" "curl/7.29.0"
~~~

**删除namespace的Egress IP**
~~~
$ oc patch --type=merge netnamespace <project-name> -p '{"egressIPs":[]}' 
~~~

**删除节点的hostsubnet**
~~~
$ oc patch --type=merge hostsubnet <node-name> -p '{"egressIPs":[]}' 
$ oc patch --type=merge hostsubnet <node-name> -p '{"egressCIDRs":[]}' 
~~~
