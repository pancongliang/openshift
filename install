### OpenShift Install（UPI）:

### Server info：
Hostname | Role | IP |
--- |--- |--- 
bastion.ocp4-6.example.com | master | 10.72.45.160
master01.ocp4-6.example.com | master | 10.72.36.161
master02.ocp4-6.example.com | master | 10.72.36.162
master03.ocp4-6.example.com | master | 10.72.36.163
worker01.ocp4-6.example.com | master | 10.72.36.164
worker02.ocp4-6.example.com | master | 10.72.36.165

#### 1.创建用户配置的基础架构:
**a. 配置订阅及必要的软件:**
~~~
$ subscription-manager register --username=rhn-support-copan --password='!ckdlsk88' --auto-attach

$ subscription-manager list --available |more
  Employee SKU

$ subscription-manager attach --pool=8a85f9833e1404a9013e3cddf99305e6
~~~

**b. 安装必要的软件:**
~~~
$ yum install  -y wget net-tools podman bind-utils bind  haproxy git bash-completion vim jq nfs-utils httpd httpd-tools  skopeo httpd-manual
$ systemctl disable firewalld
$ sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config 
$ systemctl enable httpd --now 
$ reboot 
~~~

**c. 搭建 httpd 服务，实现文件服务器功能(修改监听端口，因为 80 haproxy 需要监听 80，改成 8080):**
~~~
$ sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf 
~~~
~~~ 
$ systemctl restart httpd
~~~

**测试 httpd 功能:**
~~~
$ mkdir -p /var/www/html/materials
$ touch /var/www/html/materials/testfile
$ wget http://10.72.45.160:8080/testfile
~~~


**d. 配置 DNS 服务器:**
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

**配置ocp正向解析:**
~~~
$ vim /var/named/ocp4-6.example.com.zone
~~~
~~~
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

**配置ocp反向解析:**
~~~
$ vim /var/named/74.10.zone
~~~
~~~
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

**修改 zone 文件权限，启动 DNS 服务:**
~~~
$ chown named. /var/named/*.zone
$ systemctl enable named --now
$ systemctl restart named
~~~

**测试解析正确与否**
~~~
$ vim /etc/resolv.conf  
nameserver 10.72.45.160

$ vim /etc/sysconfig/network-scripts/ifcfg-ens3 
DNS1=10.72.45.160
~~~
~~~
$ nslookup bootstrap.ocp4-6.example.com
$ nslookup master01.ocp4-6.example.com
$ nslookup master02.ocp4-6.example.com
$ nslookup master03.ocp4-6.example.com
$ nslookup worker01.ocp4-6.example.com
~~~

**e.安装 Haproxy 做 load balancer:**
~~~
$ cat /dev/null > /etc/haproxy/haproxy.cfg 
$ vim /etc/haproxy/haproxy.cfg 
~~~
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

**检查 haproxy 状态:**
~~~
$ systemctl enable haproxy --now
$ systemctl restart haproxy 
~~~

**f.下载 OC 工具，并把它放到 /usr/local/bin 目录:**
[OpenShift安装程序及映象下载](https://access.redhat.com/downloads/content/290/ver=4.7/rhel---8/4.7.13/x86_64/product-software)

**openshift-install 工具:**
~~~
$ tar xvf oc-4.7.18-linux.tar.gz
$ scp -r copan root@10.72.37.100:/root/
~~~
**CLI Command**
~~~
$ tar xvf openshift-install-linux-4.7.18.tar.gz
$ mv oc kubectl openshift-install /usr/local/bin/
~~~

**可选工具:**
docker registry image:
~~~
$ podman load -i registry.tar
~~~
grpcurl 工具:
~~~
$ tar -xvf grpcurl_1.7.0_linux_x86_64.tar.gz
$ cp grpcurl /usr/local/bin/; chmod +x /usr/local/bin/grpcurl
~~~
opm 工具:
~~~
$ tar -xvf opm-linux4.6.tar.gz
$ cp ./opm /usr/local/bin; chmod +x /usr/local/bin/opm
~~~
验证 oc 是否可以正常使用:
~~~
$ oc version
~~~

**g.创建离线镜像仓库:**

[自签名证书参考](https://access.redhat.com/documentation/en-us/red_hat_codeready_workspaces/2.1/html/installation_guide/installing-codeready-workspaces-in-tls-mode-with-self-signed-certificates_crw)
 
**签发步骤以我的主机为 bastion.ocp4-8.example.com 为准，请自行替换 image registry 的 hostname:**
~~~
$ mkdir -p /opt/registry/{auth,certs,data}

$ mkdir -p /etc/crts/ && cd /etc/crts/
~~~
~~~
$ openssl genrsa -out /etc/crts/cert.ca.key 4096
~~~
~~~
$ openssl req -x509 \
  -new -nodes \
  -key /etc/crts/cert.ca.key \
  -sha256 \
  -days 36500 \
  -out /etc/crts/cert.ca.crt \
  -subj /CN="Local Red Hat Ren Signer" \
  -reqexts SAN \
  -extensions SAN \
  -config <(cat /etc/pki/tls/openssl.cnf \
      <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature'))
~~~
~~~
$ openssl genrsa -out /etc/crts/cert.key 2048
~~~
~~~
$ openssl req -new -sha256 \
    -key /etc/crts/cert.key \
    -subj "/O=Local Cert/CN=bastion.ocp4-6.example.com" \
    -reqexts SAN \
    -config <(cat /etc/pki/tls/openssl.cnf \
        <(printf "\n[SAN]\nsubjectAltName=DNS:bastion.ocp4-6.example.com\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
    -out /etc/crts/cert.csr
~~~
~~~
$ openssl x509 \
    -req \
    -sha256 \
    -extfile <(printf "subjectAltName=DNS:bastion.ocp4-6.example.com\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth") \
    -days 3650 \
    -in /etc/crts/cert.csr \
    -CA /etc/crts/cert.ca.crt \
    -CAkey /etc/crts/cert.ca.key \
    -CAcreateserial -out /etc/crts/cert.crt
~~~
~~~
$ openssl x509 -in /etc/crts/cert.crt -text

$ /bin/cp -f /etc/crts/cert.ca.crt /etc/pki/ca-trust/source/anchors/

$ update-ca-trust extract

$ cp /etc/crts/cert.key  /opt/registry/certs/ocp4-6.example.com.key

$ cp /etc/crts/cert.crt  /opt/registry/certs/ocp4-6.example.com.crt
~~~

**利用 bcrypt 格式，创建离线镜像仓库的用户名和密码:**
~~~
$ htpasswd -bBc /opt/registry/auth/htpasswd admin redhat
~~~
**信任自签证书，启动离线镜像仓库:**
~~~
$ cp /opt/registry/certs/ocp4-6.example.com.crt /etc/pki/ca-trust/source/anchors/

$ update-ca-trust
 
$ podman run --name mirror-registry -p 5000:5000 -v /opt/registry/data:/var/lib/registry:z \
  -v /opt/registry/auth:/auth:z -e "REGISTRY_AUTH=htpasswd" -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd -v /opt/registry/certs:/certs:z \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/ocp4-6.example.com.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/ocp4-6.example.com.key -d docker.io/library/registry:2
~~~
**验证容器镜像仓库是否可以正常工作:**
~~~
$ podman ps
  CONTAINER ID  IMAGE                         COMMAND               CREATED         STATUS             PORTS                   NAMES
  8a80baf5ee9e  docker.io/library/registry:2  /entrypoint.sh /e...  33 seconds ago  Up 33 seconds ago  0.0.0.0:5000->5000/tcp  mirror-registry
 
$ curl -u admin:redhat -k https://bastion.ocp4-6.example.com:5000/v2/_catalog
  {"repositories":[]}
~~~

**开机自动重启conatiner:**
~~~
$ vim /etc/systemd/system/mirror-registry.service
[Unit]
Description= registry service
After=network.target
After=network-online.target
[Service]
Restart=always
ExecStart=/usr/bin/podman start -a mirror-registry
ExecStop=/usr/bin/podman stop -t 10 mirror-registry
[Install]
WantedBy=multi-user.target

$ systemctl enable mirror-registry.service --now
~~~

**h.缓存ocp安装镜像到镜像仓库:**
[下载pull-secret](https://cloud.redhat.com/openshift/install/metal/installer-provisioned)

~~~
$ vim /root/pull-secret
{"auths":{"cloud.openshift.com":{"auth":"b3BlbnNoaWZ0LXJlbGVhc2UtZGV2K29jbV9hY2Nlc3NfYzE4NjVmZmNjNzM0NDNhODljNDZlZjEyMDlhOTlmMGE6WlBCM0JLSlpGUlVJMENBQjdMNTA1Nk01UTZXMjRNME4wUFMxVVlPVFU2RFZDN0c5TDBQVTFGUVhJMDNNMjlRWg==","email":"copan@redhat.com"},"quay.io":{"auth":"b3BlbnNoaWZ0LXJlbGVhc2UtZGV2K29jbV9hY2Nlc3NfYzE4NjVmZmNjNzM0NDNhODljNDZlZjEyMDlhOTlmMGE6WlBCM0JLSlpGUlVJMENBQjdMNTA1Nk01UTZXMjRNME4wUFMxVVlPVFU2RFZDN0c5TDBQVTFGUVhJMDNNMjlRWg==","email":"copan@redhat.com"},"registry.connect.redhat.com":{"auth":"fHVoYy1wb29sLWIwMGNjN2I5LTQ4NGMtNGU4Mi1iZmI0LTEzN2E1NDhjYWU1NjpleUpoYkdjaU9pSlNVelV4TWlKOS5leUp6ZFdJaU9pSmpZVE5qWVRFd05qa3hPVGMwWlRCbE9HTXdOR0U1T1dabE1qSTFaRE0wTWlKOS5zTC0yZTYwV0xCWlpfaU1sdVNoS0hDN1Nsd3lSSUJuU282U1hUck5aLWwxRUlITlZiaEFFNXpZQm5OdUNuRV9RNzJKLWpUZXpTNm5jVlJqYUd1d3FjWDN1U2JGUF9FUGZqNHR0dDRuVHFlaXc2cVJBSzI0clAwQWNoWWN2X3NYRkpLUDR2cVZOR1pfWFBhQV8yek9UcGg1U3JKYktPZGxPVmF1V1ZHTWZwT3dNVWhwOVYyVzJPbkhHa2daU1FFVkRqRlM5R3VSYkpZa2hzXzRHbURZZjZYWWh0U2xwdGVuU25pTS1SQzRxTTFRNDdEZ2JMeVA4VFY2UGt6bU9aQ2lZN0tfWEFmQU1hUEk0QTN0Y1dSeUN1YWl1QXdlVGc5QmtDRngyUXNPMUg5OVFzWjFSbnMyTHhOVWVPd2dNTGVCc1JVeFJUQUE4VHZJdE1nLUVuelZyUFV2RC1ONzVIeUU3eGRYaWZyTGVlcG9nMmRPWTlNZDNKN0Jza2ttLUxtdkFBcmxkNkp5S1dPTlA1aUZNUE92MDh1bDZ0UEJZSUxCYlVWMFQ0WUxaMDJoZ3RzNVdLZnpLdGxubElQLWNCbk9qUXY5cGF1Vlp6TTI0NHF3MUFIeXJjaHVPbUlSWmtVZ1VaNk5XZm5ZbUlOVHd1OFQ1UVVFTVUtRFRKX3FnTExnZFhfNm5xeHYtR0V2aGNjTFVreXVmT0xURl9CZjRBUlcycmJucDB6ZWhyZU11VVV0SGlOWHkxcU5SM0g1R09IbjJSTFBySUZ1Zm1yZmk3cEVnUlZRYmhFNzJ2SU02MmZ1dGw5THZad0V0bDNNQUxEOTl5MXRrblZCLUFGVEtNMnMwWWdyLU5Gb3hwZGt6ZC14Q2gtQThZUkFabkFPb19BbVBxT19TUkRqRmpqZw==","email":"copan@redhat.com"},"registry.redhat.io":{"auth":"fHVoYy1wb29sLWIwMGNjN2I5LTQ4NGMtNGU4Mi1iZmI0LTEzN2E1NDhjYWU1NjpleUpoYkdjaU9pSlNVelV4TWlKOS5leUp6ZFdJaU9pSmpZVE5qWVRFd05qa3hPVGMwWlRCbE9HTXdOR0U1T1dabE1qSTFaRE0wTWlKOS5zTC0yZTYwV0xCWlpfaU1sdVNoS0hDN1Nsd3lSSUJuU282U1hUck5aLWwxRUlITlZiaEFFNXpZQm5OdUNuRV9RNzJKLWpUZXpTNm5jVlJqYUd1d3FjWDN1U2JGUF9FUGZqNHR0dDRuVHFlaXc2cVJBSzI0clAwQWNoWWN2X3NYRkpLUDR2cVZOR1pfWFBhQV8yek9UcGg1U3JKYktPZGxPVmF1V1ZHTWZwT3dNVWhwOVYyVzJPbkhHa2daU1FFVkRqRlM5R3VSYkpZa2hzXzRHbURZZjZYWWh0U2xwdGVuU25pTS1SQzRxTTFRNDdEZ2JMeVA4VFY2UGt6bU9aQ2lZN0tfWEFmQU1hUEk0QTN0Y1dSeUN1YWl1QXdlVGc5QmtDRngyUXNPMUg5OVFzWjFSbnMyTHhOVWVPd2dNTGVCc1JVeFJUQUE4VHZJdE1nLUVuelZyUFV2RC1ONzVIeUU3eGRYaWZyTGVlcG9nMmRPWTlNZDNKN0Jza2ttLUxtdkFBcmxkNkp5S1dPTlA1aUZNUE92MDh1bDZ0UEJZSUxCYlVWMFQ0WUxaMDJoZ3RzNVdLZnpLdGxubElQLWNCbk9qUXY5cGF1Vlp6TTI0NHF3MUFIeXJjaHVPbUlSWmtVZ1VaNk5XZm5ZbUlOVHd1OFQ1UVVFTVUtRFRKX3FnTExnZFhfNm5xeHYtR0V2aGNjTFVreXVmT0xURl9CZjRBUlcycmJucDB6ZWhyZU11VVV0SGlOWHkxcU5SM0g1R09IbjJSTFBySUZ1Zm1yZmk3cEVnUlZRYmhFNzJ2SU02MmZ1dGw5THZad0V0bDNNQUxEOTl5MXRrblZCLUFGVEtNMnMwWWdyLU5Gb3hwZGt6ZC14Q2gtQThZUkFabkFPb19BbVBxT19TUkRqRmpqZw==","email":"copan@redhat.com"}}}
~~~

**整合 pull-secret 文件(使用login --authfile方式整合镜像仓库身份信息）:**
~~~
$ podman login --authfile /root/pull-secret bastion.ocp4-6.example.com:5000
$ podman login --authfile /root/pull-secret mirror.registry.example.com      
  Username: admin
  Password: redhat
  Login Succeeded!
~~~

**缓存ocp image:**
~~~
$ export OCP_RELEASE=4.6.8
$ export LOCAL_REGISTRY='bastion.ocp4-6.example.com:5000'
$ export LOCAL_REPOSITORY='ocp4/openshift4'
$ export PRODUCT_REPO='openshift-release-dev' 
$ export LOCAL_SECRET_JSON='/root/pull-secret'
$ export RELEASE_NAME="ocp-release"
$ export ARCHITECTURE=x86_64
~~~

**缓存ocp image到离线容器仓库(缓存最后输出保留:image content source)**
~~~
$ oc adm -a ${LOCAL_SECRET_JSON} release mirror \
  --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
  --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
  --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE} 
...
保存如下image content source内容:
- mirrors:
  - bastion.ocp4-6.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - bastion.ocp4-6.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
~~~

**可选: 缓存image到本地目录:**
~~~
缓存 image 到本地目录:
$ oc adm -a /root/pull-secret release mirror --from=quay.io/openshift-release-dev/ocp-release:4.8.2-x86_64 --to-dir=/root/mirror

同步 image 到私有仓库:
$ oc image mirror -a pull-secret --dir=/root/mirror file://openshift/release:4.8.2* bastion.ocp4-8.example.com:5000/ocp4/openshift4
~~~

####2. 安装 OpenShift Container Platform 4
**a.创建登录 CoreOS 的 SSH Key 并确认仓库CA证书:**
~~~
$ ssh-keygen
$ cat .ssh/id_rsa.pub
$ cat /etc/crts/cert.ca.crt 
~~~

**b.手动创建 install-config.yaml 文件:**
> 参考文档:
> https://docs.openshift.com/container-platform/4.6/installing/installing_bare_metal/installing-restricted-networks-bare-metal.html#installation-bare-metal-config-yaml_installing-restricted-networks-bare-metal
~~~
$ vim install-config.yaml 
apiVersion: v1
baseDomain: example.com 
compute:
- hyperthreading: Enabled  
  name: worker
  replicas: 0    
controlPlane:
  hyperthreading: Enabled  
  name: master 
  replicas: 3
metadata:
  name: ocp4-7 
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14    
    hostPrefix: 23 
  networkType: OpenShiftSDN 
  serviceNetwork: 
  - 172.30.0.0/16  
 
platform:
  none: {}  
fips: false 
pullSecret: '{"auths":{"bastion.ocp4-6.example.com:5000": {"auth": "YWRtaW46cmVkaGF0","email": "copan@redhat.com"}}}'
sshKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7Un3CDuXdwV38dGCzRTP0qvoJiEjWFbf9KKeSM+/sEon82/WJYMIWcXyO2tkuPysq6WtqKiVN6vzJG7Y6fHQxuI1hTnb7f43rOh9pZmeFDp3dQwm7t6ZR141uVCe19zvuz8SUhKHMqlqm56kYSLwLjRcDqa0sv8lqX2M2zwlpehkfnKMR0AIcqbXZgjhIWyEkcriVRdq130F3mdNmTseSqgH3UL+1yW7n49iglPB10oO80bkwZVYuYqrkH30avH2PnbuR3IiaO1wO4LlQaIsdQaNmVOfcQO5QMTRrptVXpIlgK2gdvHNWrQZFKrePxpBFDnd732f4T1oXim/McqitOeR1ZEym8nIzXFW6ZIPgGcURmyo99vOiQoYwI1klDUaM4aAt8Cw7AoHn8iIvgcc7BKRbvppL18tsbBIxTVwBoQEHg8ETu4CATHSeLVKcsPPvjtWD9MpPHPsxdrtbyUEgw46PMcOxUFjxBRURTVVFzx7YTLImSem5NcrZ2C+rbck= root@bastion'
additionalTrustBundle: | 
  -----BEGIN CERTIFICATE-----
  MIIE9jCCAt6gAwIBAgIUCQ12MPLlbtZ5icKSO0cMR0gyjkwwDQYJKoZIhvcNAQEL
  BQAwIzEhMB8GA1UEAwwYTG9jYWwgUmVkIEhhdCBSZW4gU2lnbmVyMCAXDTIxMTAw
  ODA4NTg0NVoYDzIxMjEwOTE0MDg1ODQ1WjAjMSEwHwYDVQQDDBhMb2NhbCBSZWQg
  SGF0IFJlbiBTaWduZXIwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCt
  1F22hjhXSP3pgDygStNoklNm7sqwLc9ZlUl39aqu75FJyqAanf4PTLUnMnF1dWJ1
  mLEcHMpqRDj7vSFhqHf45zyHSmEHJRrtew2BcJ1EKQFU9avkhOlQZ58q4yw9C5Si
  AIZtEKpHelzR5LrZj9pc2wTrI0l/gOuPcDBsOfVZpfBK9hXRiFW+CSm7KKoqzsDE
  R1yas0DgicPm/qFGQhrHEBJGwtWSxQ7qaspQSP+lP77g0ZuM/ItVfSdSJ/yINQCb
  vbo5Fi1poqE8Gc+zk8Bj2sWncykm/gIZ08x1+aNKlHpWwt8b+p+NFws3VD/+TzQz
  3R1YSM5eOCBBK4Nz9GD9aXyeQfyF82Hak0fqOekHR7D+fL3/1D+t8pDKA+nFzQYO
  bBwm3N9FLXkJ0hiS6ZuuuW0Fy6vds5fI4fzTGv20qsC55qTC2zCEynCdB5Civuu6
  BQSG6GW/FID5TEXAYdBXkBubZAVkxBkofJH0MamU8BZjdaVA7gxtfvoNQfRg/p8k
  Tspl4bx5UprkitxWi8a+YQjNEN5vfZ+u1LeivNgnjwTku4GKd0kTqYL4gnSbhutp
  OmGyAs7nK3KUg7to2VNDjRVKj9ghGQvNIlE5HvzpAuPCNsM9Bft3UNYQxUH62Wbv
  ATsSBimL5JgrQibAKZyn2cgXRa3BCQpzqjuoQwBWkQIDAQABoyAwHjAPBgNVHRMB
  Af8EBTADAQH/MAsGA1UdDwQEAwIBhjANBgkqhkiG9w0BAQsFAAOCAgEApBFX97TF
  D+U/GrGg7hXYnUZ/saNHgnDuf46NOvQkf30zPfaUoj9en45dYn0iE4iYBWMetOW0
  lp0/ojUvEemGM3mYeItS3iU4Atkp0DSX2brHxvD2c8q2F91w89st7zKyZIOlmkPF
  Eudmp0G1VaOmUgYUQUIowHHcipdvovVFZPRIblXV2LAdBOVMTMN3CYIgCV8mdE4Q
  g5a3WSV2a3HeFL8DW/+VEo5Se83WGPGuqoBpl1Q/BMbZLNT2UM4ZB+P/cPpsbVOs
  4b4IlM4/wGdbPV6Zq5qXQ/uXe8fSzl+z7f+SgS0BGGOhXgVLzWD086R7ruUxkGNj
  kdk7SH1eVQGehaVg4eVLNu9lvZwqkGB+/c59w9b//m0k4Ooh8vaAe2QfqGk2R578
  CaYtg89SgyD//36/P9HxnGfqn1Aoqb1DenDBbKGqggNqDBUVdLD9dzPmVmJ1Oc64
  7Lhm51D0OUR75znKWiDD+HeMQS0iWhx8rD5pvw5TjW8yHu7IzOs+k8DMtcMTj5Ae
  +Xtz3Bb4SVBmBKCWfM8TjBwG0o2FTLGtAW2+5R9LK4D9xkdSx3Ku5Is4TJXdp+xE
  WlVPK4gNPiqAHJTYuuW4Tn4BFVXtaqiJuP3LFOQRoMYPrRTEHgsGe9Mxa2cFk5+T
  oBXt6TOI46jTnh+Cwg8r9aLXh7rSWroaKj4=
  -----END CERTIFICATE-----
imageContentSources:
- mirrors:
  - bastion.ocp4-6.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - bastion.ocp4-6.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
~~~~

**c.利用 openshift-installer 工具创建 ignition 文件:**
~~~
$ mkdir /var/www/html/materials/pre

$ cp ~/install-config.yaml  /var/www/html/materials/pre
 
$ cd /var/www/html/materials

$ openshift-install create manifests --dir pre/ 

$ vim /var/www/html/materials/pre/manifests/cluster-scheduler-02-config.yml
  masterSchedulable: true    -----> false 这个地方改成 false，这样可以让 master node 不参与调度

$ openshift-install create ignition-configs --dir pre
$ chmod a+r pre/*.ign
~~~

####3. 使用 ISO 创建 RHCOS 机器:
**a.安装bootstrap:**
>挂载iso文件，启动后确认ip及disk，然后重启并按两次 Tab 键进入内核编辑页面:
~~~
$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.45.160:8080/pre/bootstrap.ign
ip=10.72.36.167::10.72.37.254:255.255.254.0:bootstrap.ocp4-6.example.com::none 
nameserver=10.72.45.160

$ ssh core@bootstrap.ocp4-6.example.com
$ sudo -i
$ netstat -ntplu |grep 6443
$ netstat -ntplu |grep 22623
$ podman ps
$ journalctl -b -f -u bootkube.service
~~~

**b.安装master 01 - 03:**
> master安装完成时，在bootstrap机器 journalctl -b -f -u bootkube.service 日志中显示安装完成的提示: 
~~~
$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.45.160:8080/pre/master.ign  
ip=10.72.36.161::10.72.37.254:255.255.254.0:master01.ocp4-6.example.com::none 
nameserver=10.72.45.160

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.45.160:8080/pre/master.ign  
ip=10.72.36.162::10.72.37.254:255.255.254.0:master02.ocp4-6.example.com::none 
nameserver=10.72.45.160

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.45.160:8080/pre/master.ign  
ip=10.72.36.163::10.72.37.254:255.255.254.0:master03.ocp4-6.example.com::none 
nameserver=10.72.45.160
~~~



**c.安装worker 01 - 03:**
>worker节点自动重启完成即可: 
~~~
$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.45.160:8080/pre/worker.ign  
ip=10.72.36.164::10.72.37.254:255.255.254.0:worker01.ocp4-6.example.com::none 
nameserver=10.72.45.160

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.45.160:8080/pre/worker.ign  
ip=10.72.36.165::10.72.37.254:255.255.254.0:worker02.ocp4-6.example.com::none 
nameserver=10.72.45.160
~~~

####4.登录ocp并审批csr:
**a.添加kubeconfig变量:**
~~~
$ vim .bash_profile
export KUBECONFIG=/var/www/html/materials/pre/auth/kubeconfig
~~~
**CLI 补全:**
~~~
$ export KUBECONFIG=/var/www/html/materials/pre/auth/kubeconfig
$ oc completion bash >> /etc/bash_completion.d/oc_completion
$ oc whoami
system:admin
~~~

**b.批准证书，让 worker node 加入:**
~~~
$ oc get csr
$ oc adm certificate approve csr-4zmjc
$ oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
~~~

**c.确认环境正常:**
~~~
$ oc get node
$ oc get co
~~~

####5.调整 image-registry 存储:
**a.配置nfs并创建pv:**
~~~
$ mkdir /nfs
$ mkdir -p /nfs/image
$ useradd nfsnobody
$ chown -R nfsnobody.nfsnobody /nfs
$ chmod -R 777 /nfs
$ vim /etc/exports
/nfs    **(rw,sync,no_wdelay,no_root_squash,insecure,fsid=0)
$ systemctl enable nfs-server --now
~~~
**b.创建 PV:**
~~~
$ cat << EOF > ./nfs-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteMany
  nfs:
    path: /nfs
    server: 10.72.45.160
  persistentVolumeReclaimPolicy: Retain
EOF

$ oc create -f nfs-pv.yaml
~~~

**c.修改 image-registry operator:**
~~~
$ oc edit configs.imageregistry.operator.openshift.io
spec:
  logLevel: Normal
  managementState: Managed    --> 从Removed改为Managed

 storage:
   pvc:
     claim:
~~~

####6.把 private image registry 证书添加到 configmap:
**a.创建configmap:**
~~~
$ oc create configmap registry-config --from-file=mirror.registry.example.com=/etc/pki/ca-trust/source/anchors/mirror.registry.example.com.ca.crt \
   --from-file=bastion.ocp4-6.example.com..5000=/etc/pki/ca-trust/source/anchors/cert.ca.crt -n openshift-config
~~~
**b.添加信任自签名证书:**
~~~
$ oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-config"}}}' --type=merge
~~~

####7.修改 samples operator 配置:
~~~
$ oc patch configs.samples.operator.openshift.io cluster  --patch '[{"op": "replace", "path": "/spec/managementState", "value":"Removed"}]'   --type=json

$ oc patch configs.samples.operator.openshift.io cluster --patch '{"spec":{"samplesRegistry":null,"skippedImagestreams":null}}' --type=merge

$ oc patch configs.samples.operator.openshift.io cluster  --patch '[{"op": "replace", "path": "/spec/managementState", "value":"Managed"}]'   --type=json

$ oc patch configs.samples.operator.openshift.io   cluster   --patch   '{"spec":{"samplesRegistry":"bastion.ocp4-6.example.com:5000","skippedImagestreams":["jenkins","jenkins-agent-nodejs","jenkins-agent-maven"]}}'    	--type=merge
~~~
