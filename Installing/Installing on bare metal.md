### Installing a user-provisioned bare metal cluster on a restricted network

**Server info**
Hostname | Role | IP |
--- |--- |--- 
bastion.ocp4.example.com  | master | 10.72.36.160
master01.ocp4.example.com | master | 10.72.36.161
master02.ocp4.example.com | master | 10.72.36.162
master03.ocp4.example.com | master | 10.72.36.163
worker01.ocp4.example.com | master | 10.72.36.164
worker02.ocp4.example.com | master | 10.72.36.165
worker02.ocp4.example.com | master | 10.72.36.166
bootstrap.ocp4.example.com | master | 10.72.36.169

#### 1.Create the user-provisioned infrastructure (bastion) 

**1.1 Setup subscription**
~~~
$ subscription-manager register --username=rhn-support-copan --password='!ckdlsk88' --auto-attach

$ subscription-manager list --available |more
  Employee SKU

$ subscription-manager attach --pool=8a85f9833e1404a9013e3cddf99305e6
~~~

**1.2 Install the necessary software**
~~~
$ yum install -y wget net-tools podman bind-utils bind  haproxy git bash-completion vim jq nfs-utils httpd httpd-tools  skopeo httpd-manual
$ systemctl disable firewalld
$ sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config 
$ systemctl enable httpd --now 
$ reboot 
~~~

**1.3 Modify httpd.conf (file server)**
~~~
$ sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf 

$ systemctl restart httpd

- 测试 httpd 功能:**
$ mkdir -p /var/www/html/materials
$ touch /var/www/html/materials/testfile
$ wget http://10.72.36.160:8080/testfile
~~~

**1.4 Setup DNS server:**

**a. Modify named.conf**
~~~
$ vim /etc/named.conf
options {
        listen-on port 53 { any; };             #<-- change to { any; }
        listen-on-v6 port 53 { ::1; };
        directory       "/var/named";
        dump-file       "/var/named/data/cache_dump.db";
        statistics-file "/var/named/data/named_stats.txt";
        memstatistics-file "/var/named/data/named_mem_stats.txt";
        secroots-file   "/var/named/data/named.secroots";
        recursing-file  "/var/named/data/named.recursing";
        allow-query     { any; };               #<-- change to { any; }
        forwarders      { 10.75.5.25; };        #<-- upstream dns address

//include "/etc/crypto-policies/back-ends/bind.config";   #<-- delete

zone "example.com" IN {                #<-- Add DNS A/AAAA record
        type master;
        file "example.com.zone";
        forwarders {};
};

zone "72.10.in-addr.arpa" IN {         #<-- Add DNS PTR record
        type master;
        file "72.10.zone";
        forwarders {};
};

//include "/etc/named.root.key";       #<-- delete
~~~

**b. Add DNS A/AAAA record**
~~~
$ vim /var/named/ocp4.example.com.zone

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
ns1     IN      A       10.72.36.160
;
helper  IN      A       10.72.36.160
helper.ocp4     IN      A       10.72.36.160
;
; The api identifies the IP of your load balancer.
api.ocp4.example.com.                  IN      A       10.72.36.160
api-int.ocp4.example.com.              IN      A       10.72.36.160
;
; The wildcard also identifies the load balancer.
*.apps.ocp4.example.com.               IN      A       10.72.36.160
*.apps.ocp4-7.example.com.             IN      A       10.72.37.100
*.apps.ocp4-8.example.com.             IN      A       10.74.251.14
;
; Create entries for the master hosts.
master01.ocp4.example.com.             IN      A       10.72.36.161
master02.ocp4.example.com.             IN      A       10.72.36.162
master03.ocp4.example.com.             IN      A       10.72.36.163
;
; Create entries for the worker hosts.
worker01.ocp4.example.com.             IN      A       10.72.36.164
worker02.ocp4.example.com.             IN      A       10.72.36.165
worker03.ocp4.example.com.             IN      A       10.72.36.166
;
; Create an entry for the bootstrap host.
bootstrap.ocp4.example.com.            IN      A       10.72.36.169
;
; Create entries for the mirror registry hosts.
bastion.ocp4.example.com.              IN      A       10.72.36.160
mirror.registry.example.com.           IN      A       10.74.251.168
harbor.registry.example.com.           IN      A       10.72.37.162
~~~

**c. Add DNS PTR record**
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
;
; The syntax is "last octet" and the host must have an FQDN
; with a trailing dot.
;
; The api identifies the IP of your load balancer.
160.36             IN      PTR     api.ocp4.example.com.
160.36             IN      PTR     api-int.ocp4.example.com.
;
; Create entries for the master hosts.
161.36             IN      PTR     master01.ocp4.example.com.
162.36             IN      PTR     master02.ocp4.example.com.
163.36             IN      PTR     master03.ocp4.example.com.
;
; Create entries for the worker hosts.
164.36             IN      PTR     worker01.ocp4.example.com.
165.36             IN      PTR     worker02.ocp4.example.com.
166.36             IN      PTR     worker03.ocp4.example.com.
;
; Create an entry for the bootstrap host.
169.36             IN      PTR     bootstrap.ocp4.example.com.
~~~

**d. Start/Test DNS**
~~~
$ chown named. /var/named/*.zone
$ systemctl enable named --now

- 测试解析
$ vim /etc/resolv.conf  
nameserver 10.72.36.160

$ vim /etc/sysconfig/network-scripts/ifcfg-ens3 
DNS1=10.72.36.160

$ nslookup bootstrap.ocp4.example.com
$ nslookup master01.ocp4.example.com
$ nslookup master02.ocp4.example.com
$ nslookup master03.ocp4.example.com
$ nslookup worker01.ocp4.example.com
$ nslookup worker02.ocp4.example.com
$ nslookup worker03.ocp4.example.com
$ nslookup api.ocp4.example.com
$ nslookup api-int.ocp4.example.com
$ nslookup 10.72.36.160~169
~~~

**1.5 Setup haproxy（load balancer）**

**a. Modify haproxy.cfg**
~~~
$ cat /dev/null > /etc/haproxy/haproxy.cfg 
$ vim /etc/haproxy/haproxy.cfg 
global
    maxconn     20000
    log         /dev/log local0 info
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    user        haproxy
    group       haproxy
    daemon
 
    #turn on stats unix socket
    stats socket /var/lib/haproxy/stats

defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
   #option http-server-close
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

frontend  router-http-traffic               #<-- ingress 80 port traffic
    bind *:80                               #<-- multiple ingress need to specify ip（e.g. 1.1.1.1:80,1.1.1.2:80）
    default_backend router-http-traffic
    mode tcp
    option tcplog
 
frontend  router-https-traffic              #<-- ingress 443 port traffic
    bind *:443                              #<-- multiple ingress need to specify ip（e.g. 1.1.1.1:443,1.1.1.2:443）
    default_backend router-https-traffic
    mode tcp
    option tcplog
 
frontend  k8s-api-server                    #<-- api-server traffic
    bind *:6443                             #<-- api-server and machine-config ip are different, need to specify the ip（e.g. 1.1.1.5:6443,1.1.1.2:6443）
    default_backend k8s-api-server
    mode tcp
    option tcplog

frontend  machine-config-server             #<-- machine-config server traffic
    bind *:22623                            #<-- api-server and machine-config ip are different, need to specify the ip（e.g. 1.1.1.5:22623,1.1.1.2:22623）
    default_backend machine-config-server
    mode tcp
    option tcplog
                          
backend router-http-traffic                 #<-- ingress pod running node
        balance source
        mode tcp
        server          worker01.ocp4.example.com 10.72.36.164:80 check
        server          worker02.ocp4.example.com 10.72.36.165:80 check
        server          worker03.ocp4.example.com 10.72.36.166:80 check

backend router-https-traffic                #<-- ingress pod running node
        balance source
        mode tcp
        server          worker01.ocp4.example.com 10.72.36.164:443 check
        server          worker02.ocp4.example.com 10.72.36.165:443 check
        server          worker03.ocp4.example.com 10.72.36.166:443 check

backend k8s-api-server                      #<-- api-server pod running node and bootstrap
        balance source
        mode tcp
        server          bootstrap.ocp4.example.com 10.72.36.169:6443 check
        server          master01.ocp4.example.com 10.72.36.161:6443 check
        server          master02.ocp4.example.com 10.72.36.162:6443 check
        server          master03.ocp4.example.com 10.72.36.163:6443 check

backend machine-config-server               #<-- api-server pod running node and bootstrap
        balance source
        mode tcp
        server          bootstrap.ocp4.example.com 10.72.36.169:22623 check
        server          master01.ocp4.example.com 10.72.36.161:22623 check
        server          master02.ocp4.example.com 10.72.36.162:22623 check
        server          master03.ocp4.example.com 10.72.36.163:22623 check
~~~

**b. Start haproxy**
~~~
$ systemctl enable haproxy --now
~~~

**1.6 [Download/Install OC Tool](https://access.redhat.com/downloads/content/290/ver=4.7/rhel---8/4.7.13/x86_64/product-software)**
~~~
- openshift-install
$ tar xvf oc-4.7.18-linux.tar.gz
$ scp -r copan root@10.72.37.100:/root/

- CLI Command
$ tar xvf openshift-install-linux-4.7.18.tar.gz
$ mv oc kubectl openshift-install /usr/local/bin/

$ oc version
~~~

**1.7 [Self-signed cert](https://access.redhat.com/documentation/en-us/red_hat_codeready_workspaces/2.1/html/installation_guide/installing-codeready-workspaces-in-tls-mode-with-self-signed-certificates_crw) and create offline mirror registry**
 
**a. Create registry directory**
~~~
$ mkdir -p /opt/registry/{auth,certs,data}
~~~

**b. Set the required environment variables**
~~~
$ CA_CN="Local Red Hat CodeReady Workspaces Signer"
$ DOMAIN='docker.registry.example.com'
$ OPENSSL_CNF=/etc/pki/tls/openssl.cnf
~~~

**c. Generate root ca.key**
~~~
$ mkdir -p /etc/crts/ && cd /etc/crts/
$ openssl genrsa -out /etc/crts/${DOMAIN}.ca.key 4096
~~~

**d. Generate root ca.crt**
~~~
$ openssl req -x509 \
  -new -nodes \
  -key /etc/crts/${DOMAIN}.ca.key \
  -sha256 \
  -days 36500 \
  -out /etc/crts/${DOMAIN}.ca.crt \
  -subj /CN="${CA_CN}" \
  -reqexts SAN \
  -extensions SAN \
  -config <(cat ${OPENSSL_CNF} \
      <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature'))
~~~

**e. Generate domain key**
~~~
$ openssl genrsa -out ${DOMAIN}.key 2048
~~~

**f. Generate domain cert csr**
~~~
$ openssl req -new -sha256 \
    -key /etc/crts/${DOMAIN}.key \
    -subj "/O=Local Red Hat CodeReady Workspaces/CN=${DOMAIN}" \
    -reqexts SAN \
    -config <(cat ${OPENSSL_CNF} \
        <(printf "\n[SAN]\nsubjectAltName=DNS:${DOMAIN}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
    -out /etc/crts/${DOMAIN}.csr
~~~

**g. Generate domain crt**
~~~
$ openssl x509 \
    -req \
    -sha256 \
    -extfile <(printf "subjectAltName=DNS:${DOMAIN}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth") \
    -days 365 \
    -in /etc/crts/${DOMAIN}.csr \
    -CA /etc/crts/${DOMAIN}.ca.crt \
    -CAkey /etc/crts/${DOMAIN}.ca.key \
    -CAcreateserial -out /etc/crts/${DOMAIN}.crt
    
$ openssl x509 -in /etc/crts/${DOMAIN}.cert.crt -text
~~~

**h. Copy and trust the cert**
~~~
$ cp /etc/crts/${DOMAIN}ca.crt ${DOMAIN}.crt /etc/pki/ca-trust/source/anchors/
$ update-ca-trust extract
$ cp /etc/crts/${DOMAIN}.key ${DOMAIN}.crt /opt/registry/certs/
$ update-ca-trust
~~~

**i. Create username and password for offline mirror repository**
~~~
$ htpasswd -bBc /opt/registry/auth/htpasswd admin redhat
~~~

**j. Running docker registry**
~~~
$ podman run --name mirror-registry -p 5000:5000 -v /opt/registry/data:/var/lib/registry:z -v /opt/registry/auth:/auth:z -e "REGISTRY_AUTH=htpasswd" -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd -v /opt/registry/certs:/certs:z -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/${DOMAIN}.crt -e REGISTRY_HTTP_TLS_KEY=/certs/${DOMAIN}.key -d docker.io/library/registry:2

$ podman ps
  CONTAINER ID  IMAGE                         COMMAND               CREATED         STATUS             PORTS                   NAMES
  8a80baf5ee9e  docker.io/library/registry:2  /entrypoint.sh /e...  33 seconds ago  Up 33 seconds ago  0.0.0.0:5000->5000/tcp  mirror-registry
 
$ curl -u admin:redhat -k https://${DOMAIN}:5000/v2/_catalog
  {"repositories":[]}

$ podman login https://${DOMAIN}:5000
~~~

**k.Automatically start docker registry**
~~~
$ cat << EOF > /etc/systemd/system/mirror-registry.service
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
EOF

$ systemctl enable mirror-registry.service --now
~~~

**1.8 Download ocp image to docker registry:**

**a. [Download pull-secret](https://cloud.redhat.com/openshift/install/metal/installer-provisioned)**

**b. Add repository authentication to pull-secret**
~~~
$ podman login --authfile /root/pull-secret docker.registry.example.com:5000    
  Username: admin
  Password: redhat
  Login Succeeded!
~~~

**c. Set the required environment variables**
~~~
$ export OCP_RELEASE=4.6.8
$ export LOCAL_REGISTRY='docker.registry.example.com:5000'
$ export LOCAL_REPOSITORY='ocp4/openshift4'
$ export PRODUCT_REPO='openshift-release-dev' 
$ export LOCAL_SECRET_JSON='/root/pull-secret'
$ export RELEASE_NAME="ocp-release"
$ export ARCHITECTURE=x86_64
~~~

**d. Download ocp image to docker registry**
~~~
$ oc adm -a ${LOCAL_SECRET_JSON} release mirror \
  --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
  --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
  --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE} 
...
 #record image content source
- mirrors:
  - docker.registry.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - docker.registry.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
~~~

**Optional:**
~~~
- Download image to directory:
$ oc adm -a /root/pull-secret release mirror --from=quay.io/openshift-release-dev/ocp-release:4.8.2-x86_64 --to-dir=/root/mirror

- Sync image to registory:
$ oc image mirror -a pull-secret --dir=/root/mirror file://openshift/release:4.8.2* docker.registry.example.com:5000/ocp4/openshift4
~~~

#### 2. Install OpenShift Container Platform 4

**2.1 Create the SSH Key for logging in to the node**
~~~
$ ssh-keygen
$ cat .ssh/id_rsa.pub
~~~

**2.2 Create install-config.yaml**
[view install-config](https://docs.openshift.com/container-platform/4.6/installing/installing_bare_metal/installing-restricted-networks-bare-metal.html#installation-bare-metal-config-yaml_installing-restricted-networks-bare-metal)
~~~
$ vim install-config.yaml 
apiVersion: v1
baseDomain: example.com   #<--base domain name
compute:
- hyperthreading: Enabled  
  name: worker
  replicas: 0    
controlPlane:
  hyperthreading: Enabled  
  name: master
  replicas: 3   
metadata:
  name: ocp4   #<--cluster name
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

 # Refer to pull secret to add information
pullSecret: '{"auths":{"docker.registry.example.com:5000": {"auth": "YWRtaW46cmVkaGF0","email": "copan@redhat.com"}}}' 

 # cat /root/.ssh/id_rsa.pub
sshKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7Un3CDuXdwV38dGCzRTP0qvoJiEjWFbf9KKeSM+/sEon82/WJYMIWcXyO2tkuPysq6WtqKiVN6vzJG7Y6fHQxuI1hTnb7f43rOh9pZmeFDp3dQwm7t6ZR141uVCe19zvuz8SUhKHMqlqm56kYSLwLjRcDqa0sv8lqX2M2zwlpehkfnKMR0AIcqbXZgjhIWyEkcriVRdq130F3mdNmTseSqgH3UL+1yW7n49iglPB10oO80bkwZVYuYqrkH30avH2PnbuR3IiaO1wO4LlQaIsdQaNmVOfcQO5QMTRrptVXpIlgK2gdvHNWrQZFKrePxpBFDnd732f4T1oXim/McqitOeR1ZEym8nIzXFW6ZIPgGcURmyo99vOiQoYwI1klDUaM4aAt8Cw7AoHn8iIvgcc7BKRbvppL18tsbBIxTVwBoQEHg8ETu4CATHSeLVKcsPPvjtWD9MpPHPsxdrtbyUEgw46PMcOxUFjxBRURTVVFzx7YTLImSem5NcrZ2C+rbck= root@bastion'

 # cat /etc/crts/${DOMAIN}..ca.crt 
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

 # a step output image content source
imageContentSources:
- mirrors:
  - bastion.ocp4.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - bastion.ocp4.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
~~~

**2.3 Create kubernetes manifests**
~~~
$ mkdir /var/www/html/materials/pre

$ cp /root/install-config.yaml  /var/www/html/materials/pre
 
$ cd /var/www/html/materials

$ openshift-install create manifests --dir pre/ 

$ vim /var/www/html/materials/pre/manifests/cluster-scheduler-02-config.yml
  masterSchedulable: false    #<----- master does not run custom pods
~~~

**2.4 Create ignition configuration files**
~~~
$ openshift-install create ignition-configs --dir pre
$ chmod a+r pre/*.ign
~~~

**2.5 Mount the ISO to create the RHCOS machine**

**a.Install bootstrap:**
~~~
- Mount ISO，
- Boot and confirm the disk name
- Restart and press the "Tab" key to enter the kernel editing page
- add install command

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.36.160:8080/pre/bootstrap.ign
ip=10.72.36.169::10.72.37.254:255.255.254.0:bootstrap.ocp4.example.com::none 
nameserver=10.72.36.160

- After the restart is complete, access the bootstrap node
$ ssh core@bootstrap.ocp4.example.com
$ sudo -i
- Check if it is normal or not
$ netstat -ntplu |grep 6443
$ netstat -ntplu |grep 22623
$ podman ps
$ journalctl -b -f -u bootkube.service
~~~

**b.Install master 01 - 03:**
~~~
$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.36.160:8080/pre/master.ign  
ip=10.72.36.161::10.72.37.254:255.255.254.0:master01.ocp4.example.com::none 
nameserver=10.72.36.160

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.36.160:8080/pre/master.ign  
ip=10.72.36.162::10.72.37.254:255.255.254.0:master02.ocp4.example.com::none 
nameserver=10.72.36.160

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.36.160:8080/pre/master.ign  
ip=10.72.36.163::10.72.37.254:255.255.254.0:master03.ocp4.example.com::none 
nameserver=10.72.36.160
~~~

**c. Check if master is installed**
~~~
$ ssh core@bootstrap.ocp4.example.com
$ sudo -i
$ journalctl -b -f -u bootkube.service
···Wait···
bootkube.service complete  #<--Show this content to complete the master installation.
~~~

**d. Install worker 01 - 03:**
~~~
$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.36.160:8080/pre/worker.ign  
ip=10.72.36.164::10.72.37.254:255.255.254.0:worker01.ocp4.example.com::none 
nameserver=10.72.36.160

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.36.160:8080/pre/worker.ign  
ip=10.72.36.165::10.72.37.254:255.255.254.0:worker02.ocp4.example.com::none 
nameserver=10.72.36.160

- Wait for the reboot to complete
~~~

**2.6 login ocp**
~~~
- add variable
$ vim .bash_profile
export KUBECONFIG=/var/www/html/materials/pre/auth/kubeconfig

- completion command
$ export KUBECONFIG=/var/www/html/materials/pre/auth/kubeconfig
$ oc completion bash >> /etc/bash_completion.d/oc_completion
$ oc whoami
system:admin
~~~

**2.7 approval csr，Allow adding worker nodes**
~~~
$ oc get csr
$ oc adm certificate approve csr-4zmjc
$ oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
~~~

**2.8 Check OCP Cluster**
~~~
$ oc get node
$ oc get co
~~~

**2.9 Modify image-registry storage**

**a.Setup NFS**
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

**b.Create PV:**
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
    server: 10.72.36.160
  persistentVolumeReclaimPolicy: Retain
EOF

$ oc create -f nfs-pv.yaml
~~~

**c.Modify image-registry operator:**
~~~
$ oc edit configs.imageregistry.operator.openshift.io
spec:
  logLevel: Normal
  managementState: Managed    ##<-- Removed to Managed

 storage:                     ##<-- add
   pvc:
     claim:
~~~

**2.10 Trust the docker repository**

**a.Create configmap:**
~~~
$ oc create configmap registry-config --from-file=mirror.registry.example.com=/etc/pki/ca-trust/source/anchors/mirror.registry.example.com.ca.crt \
   --from-file=docker.registry.example.com..5000=/etc/pki/ca-trust/source/anchors/docker.registry.example.com.ca.crt -n openshift-config
~~~
**b.Trust repository**
~~~
$ oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-config"}}}' --type=merge
~~~

**2.11 Set “samples operator” to specify the docker registry**
~~~
$ oc patch configs.samples.operator.openshift.io cluster  --patch '[{"op": "replace", "path": "/spec/managementState", "value":"Removed"}]'   --type=json

$ oc patch configs.samples.operator.openshift.io cluster --patch '{"spec":{"samplesRegistry":null,"skippedImagestreams":null}}' --type=merge

$ oc patch configs.samples.operator.openshift.io cluster  --patch '[{"op": "replace", "path": "/spec/managementState", "value":"Managed"}]'   --type=json

$ oc patch configs.samples.operator.openshift.io   cluster   --patch   '{"spec":{"samplesRegistry":"bastion.ocp4.example.com:5000","skippedImagestreams":["jenkins","jenkins-agent-nodejs","jenkins-agent-maven"]}}'    	--type=merge
~~~
