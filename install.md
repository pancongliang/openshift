### Installing a user-provisioned bare metal cluster on a restricted network:

#### - server info：
Hostname | Role | IP |
--- |--- |--- 
bastion.ocp4-6.example.com | master | 10.72.45.160
master01.ocp4-6.example.com | master | 10.72.36.161
master02.ocp4-6.example.com | master | 10.72.36.162
master03.ocp4-6.example.com | master | 10.72.36.163
worker01.ocp4-6.example.com | master | 10.72.36.164
worker02.ocp4-6.example.com | master | 10.72.36.165

#### 1.create the user-provisioned infrastructure:
**1.1 subscription:**
~~~
$ subscription-manager register --username=****** --password='*****' --auto-attach

$ subscription-manager list --available |more
  Employee SKU

$ subscription-manager attach --pool=8a85f9833e1404a9013e3cddf99305e6
~~~

**1.2 install software:**
~~~
$ yum install  -y wget net-tools podman bind-utils bind  haproxy git bash-completion vim jq nfs-utils httpd httpd-tools  skopeo httpd-manual
$ systemctl disable firewalld
$ sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config 
$ systemctl enable httpd --now 
$ reboot 
~~~

**1.3 install httpd (file server) service:**
~~~
$ sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf 

$ systemctl restart httpd

- 测试 httpd 功能:**
$ mkdir -p /var/www/html/materials
$ touch /var/www/html/materials/testfile
$ wget http://10.72.45.160:8080/testfile
~~~


**1.4 configure dns server:**
~~~
$ vim /etc/named.conf
~~~
~~~
options {
        listen-on port 53 { any; };
        listen-on-v6 port 53 { ::1; };
        directory       "/var/named";
        dump-file       "/var/named/data/cache_dump.db";
        statistics-file "/var/named/data/named_stats.txt";
        memstatistics-file "/var/named/data/named_mem_stats.txt";
        secroots-file   "/var/named/data/named.secroots";
        recursing-file  "/var/named/data/named.recursing";
        allow-query     { any; };
        forwarders      { 10.75.5.25; };

//include "/etc/crypto-policies/back-ends/bind.config";

zone "example.com" IN {
        type master;
        file "example.com.zone";
        forwarders {};
};

zone "72.10.in-addr.arpa" IN {
        type master;
        file "72.10.zone";
        forwarders {};
};

//include "/etc/named.root.key";
~~~

**1.4.1 configure dns resolve:**
~~~
$ vim /var/named/ocp4-6.example.com.zone

$TTL 1W
@       IN      SOA     ns1.example.com.        root (
                        2019070701      ; serial
                        3H              ; refresh (3 hours)
                        30M             ; retry (30 minutes)
                        2W              ; expiry (2 weeks)
                        1W )            ; minimum (1 week)
        IN      NS      ns1.example.com.
        IN      NS      ns2.example.com.
;
;
ns1     IN      A       10.74.250.185
ns2     IN      A       10.74.251.168
;
helper  IN      A       10.74.250.185
helper.ocp4     IN      A       10.74.250.185
;
; The api identifies the IP of your load balancer.
api.ocp4.example.com.                  IN      A       10.74.250.186
api-int.ocp4.example.com.              IN      A       10.74.250.189
api.ocp4-7.example.com.                IN      A       10.72.37.100
api-int.ocp4-7.example.com.            IN      A       10.72.37.100
api.ocp4-8.example.com.                IN      A       10.74.251.14
api-int.ocp4-8.example.com.            IN      A       10.74.251.14
;
; The wildcard also identifies the load balancer.
*.apps.ocp4.example.com.               IN      A       10.74.250.186
*.apps.test.example.com.               IN      A       10.74.250.190
*.apps.ocp4-7.example.com.             IN      A       10.72.37.100
*.apps.ocp4-8.example.com.             IN      A       10.74.251.14
;
; Create entries for the master hosts.
master01.ocp4.example.com.             IN      A       10.74.253.114
master02.ocp4.example.com.             IN      A       10.74.249.135
master03.ocp4.example.com.             IN      A       10.74.249.217
master01.ocp4-7.example.com.           IN      A       10.72.36.151
master02.ocp4-7.example.com.           IN      A       10.72.36.152
master03.ocp4-7.example.com.           IN      A       10.72.36.153
master01.ocp4-8.example.com.           IN      A       10.74.253.116
master02.ocp4-8.example.com.           IN      A       10.74.253.211
master03.ocp4-8.example.com.           IN      A       10.74.254.226
;
; Create entries for the worker hosts.
worker01.ocp4.example.com.             IN      A       10.74.252.87
worker02.ocp4.example.com.             IN      A       10.74.255.215
worker03.ocp4.example.com.             IN      A       10.74.249.22
worker01.ocp4-7.example.com.           IN      A       10.72.36.154
worker02.ocp4-7.example.com.           IN      A       10.72.36.155
worker03.ocp4-7.example.com.           IN      A       10.72.36.156
worker01.ocp4-8.example.com.           IN      A       10.74.251.178
worker02.ocp4-8.example.com.           IN      A       10.74.252.120
;
; Create an entry for the bootstrap host.
bootstrap.ocp4.example.com.            IN      A       10.74.252.146
bootstrap.ocp4-7.example.com.          IN      A       10.72.36.157
bootstrap.ocp4-8.example.com.          IN      A       10.74.255.22
;
; Create entries for the mirror registry hosts.
bastion.ocp4.example.com.              IN      A       10.74.250.185
bastion.ocp4-7.example.com.            IN      A       10.72.37.100
bastion.ocp4-8.example.com.            IN      A       10.74.251.14
mirror.registry.example.com.           IN      A       10.74.251.168
harbor.registry.example.com.           IN      A       10.72.37.162
~~~

~~~
$ vim /var/named/74.10.zone

$TTL 1W
@	IN	SOA	ns1.example.com.	root (
			2019070700	; serial
			3H		; refresh (3 hours)
			30M		; retry (30 minutes)
			2W		; expiry (2 weeks)
			1W )		; minimum (1 week)
        IN      NS      ns1.example.com.
        IN      NS      ns2.example.com.
;
; The syntax is "last octet" and the host must have an FQDN
; with a trailing dot.
;
; The api identifies the IP of your load balancer.
100.37             IN      PTR     api.ocp4-7.example.com.
100.37             IN      PTR     api-int.ocp4-7.example.com.
;
; Create entries for the master hosts.
151.36             IN      PTR     master01.ocp4-7.example.com.
152.36             IN      PTR     master02.ocp4-7.example.com.
153.36             IN      PTR     master03.ocp4-7.example.com.
;
; Create entries for the worker hosts.
154.36             IN      PTR     worker01.ocp4-7.example.com.
155.36             IN      PTR     worker02.ocp4-7.example.com.
156.36             IN      PTR     worker03.ocp4-7.example.com.
;
; Create an entry for the bootstrap host.
157.36             IN      PTR     bootstrap.ocp4-7.example.com.
;
~~~

**1.4.2 start/test dns server:**
~~~
$ chown named. /var/named/*.zone
$ systemctl enable named --now
$ systemctl restart named

- 测试解析正确与否**

$ vim /etc/resolv.conf  
nameserver 10.72.45.160

$ vim /etc/sysconfig/network-scripts/ifcfg-ens3 
DNS1=10.72.45.160

$ nslookup bootstrap.ocp4-6.example.com
$ nslookup master01.ocp4-6.example.com
$ nslookup master02.ocp4-6.example.com
$ nslookup master03.ocp4-6.example.com
$ nslookup worker01.ocp4-6.example.com
~~~

**1.5 install haproxy（load balancer）**
~~~
$ cat /dev/null > /etc/haproxy/haproxy.cfg 
$ vim /etc/haproxy/haproxy.cfg 
```shell
# Global settings
#---------------------------------------------------------------------
global
    maxconn     20000
    log         /dev/log local0 info
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    user        haproxy
    group       haproxy
    daemon
 
    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats
#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
#   option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          300s
    timeout server          300s
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 20000
listen stats
    bind :9000
    mode http
    stats enable
    stats uri / 
# all frontend
frontend  router-http-traffic
    bind *:80
    default_backend router-http-traffic
    mode tcp
    option tcplog
 
frontend  router-https-traffic
    bind *:443
    default_backend router-https-traffic
    mode tcp
    option tcplog
 
frontend  k8s-api-server
    bind *:6443
    default_backend k8s-api-server
    mode tcp
    option tcplog
 
frontend  machine-config-server
    bind *:22623
    default_backend machine-config-server
    mode tcp
    option tcplog

#all backend

backend router-http-traffic
        balance source
        mode tcp
        server          worker01.ocp4-6.example.com 10.72.36.164:80 check
        server          worker02.ocp4-6.example.com 10.72.36.165:80 check
        server          worker03.ocp4-6.example.com 10.72.36.166:80 check
backend router-https-traffic
        balance source
        mode tcp
        server          worker01.ocp4-6.example.com 10.72.36.164:443 check
        server          worker02.ocp4-6.example.com 10.72.36.165:443 check
        server          worker03.ocp4-6.example.com 10.72.36.166:443 check
backend k8s-api-server
        balance source
        mode tcp
        server          bootstrap.ocp4-6.example.com 10.72.36.167:6443 check
        server          master01.ocp4-6.example.com 10.72.36.161:6443 check
        server          master02.ocp4-6.example.com 10.72.36.162:6443 check
        server          master03.ocp4-6.example.com 10.72.36.163:6443 check

backend machine-config-server
        balance source
        mode tcp
        server          bootstrap.ocp4-6.example.com 10.72.36.167:22623 check
        server          master01.ocp4-6.example.com 10.72.36.161:22623 check
        server          master02.ocp4-6.example.com 10.72.36.162:22623 check
        server          master03.ocp4-6.example.com 10.72.36.163:22623 check
```
~~~

**1.5.1 start haproxy:**
~~~
$ systemctl enable haproxy --now
$ systemctl restart haproxy 
~~~


**1.6.download/install OC tools:**
[OpenShift安装程序及映象下载](https://access.redhat.com/downloads/content/290/ver=4.7/rhel---8/4.7.13/x86_64/product-software)
~~~
- CLI Command/openshift-install
$ tar xvf oc-4.7.18-linux.tar.gz
$ tar xvf openshift-install-linux-4.7.18.tar.gz
$ mv oc kubectl openshift-install /usr/local/bin/
$ oc version
~~~

**1.7 create offline mirror registry:**
**1.7.1 设置变量:**
~~~
$ CA_CN="Local Red Hat CodeReady Workspaces Signer"  <-- 国家及签发机构  
$ DOMAIN=bastion.ocp4.example.com                    <-- domain name，如果使用通配符域名:*.apps.ocp4.example.com
$ OPENSSL_CNF=/etc/pki/tls/openssl.cnf               <-- openssl.cnf 路径，此路径为默认路径
$ CERT=bastion.ocp4.example.com                      <-- cert file name
~~~

**1.7.2 创建存放证书目录:**
~~~
$ mkdir -p /crts/ && cd /crts
~~~

**1.7.3 生成 root ca key:**
~~~
$ openssl genrsa -out /crts/${CERT}.ca.key 4096
~~~

**1.7.4 生成 root ca crt证书:**
~~~
$ openssl req -x509 \
  -new -nodes \
  -key /crts/${CERT}.ca.key \
  -sha256 \
  -days 36500 \
  -out /crts/${CERT}.ca.crt \
  -subj /CN="${CA_CN}" \
  -reqexts SAN \
  -extensions SAN \
  -config <(cat ${OPENSSL_CNF} \
      <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature'))
~~~

**1.7.5 生成 domain key:**
~~~
$ openssl genrsa -out /crts/${CERT}.key 2048
~~~

**1.7.6 为domain生成CSR:**
~~~
$ openssl req -new -sha256 \
    -key /crts/${CERT}.key \
    -subj "/O=Local Cert/CN=${DOMAIN}" \
    -reqexts SAN \
    -config <(cat ${OPENSSL_CNF} \
        <(printf "\n[SAN]\nsubjectAltName=DNS:${DOMAIN}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
    -out /crts/${CERT}.csr
~~~

**1.7.7 生成 domain 证书:**
~~~
$ openssl x509 \
    -req \
    -sha256 \
    -extfile <(printf "subjectAltName=DNS:${DOMAIN}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth") \
    -days 3650 \
    -in /crts/${CERT}.csr \
    -CA /crts/${CERT}.ca.crt \
    -CAkey /crts/${CERT}.ca.key \
    -CAcreateserial -out /crts/${CERT}.crt
~~~

**1.7.8 查看生成的 domain 证书:**
~~~
$ yum install -y tree
$ tree /crts/
  /crts/
  ├── bastion.ocp4.example.com.crt
  ├── bastion.ocp4.example.com.csr
  ├── bastion.ocp4.example.com.key
  ├── bastion.ocp4.example.com.ca.crt
  ├── bastion.ocp4.example.com.ca.key
  └── bastion.ocp4.example.com.ca.srl
~~~

**1.7.9 转移 domain 证书:**
$ /bin/cp -f /crts/bastion.ocp4.example.com.ca.crt /etc/pki/ca-trust/source/anchors/
$ update-ca-trust extract
$ cp /crts/bastion.ocp4.example.com.key  /opt/registry/certs/
$ cp /crts/bastion.ocp4.example.com.ca.crt  /opt/registry/certs/
$ cp /opt/registry/certs/ocp4.example.com.crt /etc/pki/ca-trust/source/anchors/

