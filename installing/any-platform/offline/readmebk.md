## Installing a user-provisioned bare metal cluster on a restricted network

**Server info**
Hostname | Role | IP |
--- |--- |--- 
bastion.ocp4.example.com    | bastion | 10.74.251.171
docker.registry.example.com | bastion | 10.74.251.171
master01.ocp4.example.com   | master | 10.74.251.61
master02.ocp4.example.com   | master | 10.74.254.155
master03.ocp4.example.com   | master | 10.74.253.133
worker01.ocp4.example.com   | worker | 10.74.251.58
worker02.ocp4.example.com   | worker | 10.74.253.49
worker03.ocp4.example.com   | worker/rhel | 10.74.251.9
bootstrap.ocp4.example.com  | bootstrap | 10.74.255.118

### 1.Create the user-provisioned infrastructure (bastion) 

**1.1 Setup subscription:**
~~~
$ subscription-manager register --username=rhn-support-copan --password=pcl102085 --auto-attach

$ subscription-manager list --available |more
  Employee SKU

$ subscription-manager attach --pool=8a85f9a07db4828b017dc5184e5f0863
~~~

**1.2 Install the necessary software:**
~~~
$ yum install -y wget net-tools podman bind-utils bind  haproxy git bash-completion vim jq nfs-utils httpd httpd-tools  skopeo httpd-manual
$ systemctl disable firewalld
$ sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config 
$ systemctl enable httpd --now 
$ reboot 
~~~

**1.3 Modify httpd.conf (file server):**
~~~
$ sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf 

$ cat > /etc/httpd/conf.d/base.conf <<EOF    
<VirtualHost *:8080>
   ServerName bastion
   DocumentRoot /var/www/html/materials/
</VirtualHost>
EOF

$ systemctl restart httpd

$ mkdir -p /var/www/html/materials
$ touch /var/www/html/materials/testfile
$ wget http://10.74.251.171:8080/testfile
~~~

**1.4 Setup DNS server:**

a. Modify named.conf:
~~~
$ vim /etc/named.conf
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

        /* 
         - If you are building an AUTHORITATIVE DNS server, do NOT enable recursion.
         - If you are building a RECURSIVE (caching) DNS server, you need to enable 
           recursion. 
         - If your recursive DNS server has a public IP address, you MUST enable access 
           control to limit queries to your legitimate users. Failing to do so will
           cause your server to become part of large scale DNS amplification 
           attacks. Implementing BCP38 within your network would greatly
           reduce such attack surface 
        */
        recursion yes;
        # mod
        # allow-query-cache { none; };
        #recursion no;
        # mod

        dnssec-enable yes;
        dnssec-validation yes;

        managed-keys-directory "/var/named/dynamic";

        pid-file "/run/named/named.pid";
        session-keyfile "/run/named/session.key";

        /* https://fedoraproject.org/wiki/Changes/CryptoPolicy */
        //include "/etc/crypto-policies/back-ends/bind.config";
};

zone "example.com" IN {
        type master;
        file "example.com.zone";
        allow-query { any; };
};

zone "74.10.in-addr.arpa" IN {
        type master;
        file "74.10.zone";
        allow-query { any; };
};

logging {
        channel default_debug {
                file "data/named.run";
                severity dynamic;
        };
};

zone "." IN {
        type hint;
        file "named.ca";
};

include "/etc/named.rfc1912.zones";
//include "/etc/named.root.key";
~~~

b. Add DNS A/AAAA record:
~~~
$ vim /var/named/example.com.zone
$TTL 1W
@       IN      SOA     ns1.example.com.        root (
                        201907070      ; serial
                        3H              ; refresh (3 hours)
                        30M             ; retry (30 minutes)
                        2W              ; expiry (2 weeks)
                        1W )            ; minimum (1 week)
        IN      NS      ns1.example.com.
;
;
ns1     IN      A       10.74.251.171
;
helper  IN      A       10.74.251.171
helper.ocp4     IN      A       10.74.251.171
;
; The api identifies the IP of your load balancer.
api.ocp4.example.com.                  IN      A       10.74.251.171
api-int.ocp4.example.com.              IN      A       10.74.251.171
;
; The wildcard also identifies the load balancer.
*.apps.ocp4.example.com.               IN      A       10.74.251.171
;
; Create entries for the master hosts.
master01.ocp4.example.com.             IN      A       10.74.251.61
master02.ocp4.example.com.             IN      A       10.74.254.155
master03.ocp4.example.com.             IN      A       10.74.253.133
;
; Create entries for the worker hosts.
worker01.ocp4.example.com.             IN      A       10.74.251.58
worker02.ocp4.example.com.             IN      A       10.74.249.234
worker03.ocp4.example.com.             IN      A       10.74.251.9
;
; Create an entry for the bootstrap host.
bootstrap.ocp4.example.com.            IN      A       10.74.255.118
;
; Create entries for the mirror registry hosts.
docker.registry.example.com.           IN      A       10.74.251.171
mirror.registry.example.com.           IN      A       10.74.251.171
~~~

c. Add DNS PTR record:
~~~
$ vim /var/named/74.10.zone
$TTL 1W
@       IN      SOA     ns1.example.com.        root (
                        2019070700      ; serial
                        3H              ; refresh (3 hours)
                        30M             ; retry (30 minutes)
                        2W              ; expiry (2 weeks)
                        1W )            ; minimum (1 week)
        IN      NS      ns1.example.com.
;
; The syntax is "last octet" and the host must have an FQDN
; with a trailing dot.
;
; The api identifies the IP of your load balancer.
171.251            IN      PTR     api.ocp4.example.com.
171.251            IN      PTR     api-int.ocp4.example.com.
;
; Create entries for the master hosts.
61.251             IN      PTR     master01.ocp4.example.com.
155.254            IN      PTR     master02.ocp4.example.com.
133.253            IN      PTR     master03.ocp4.example.com.
;
; Create entries for the worker hosts.
58.251             IN      PTR     worker01.ocp4.example.com.
234.249            IN      PTR     worker02.ocp4.example.com.
9.251              IN      PTR     worker03.ocp4.example.com.
;
; Create an entry for the bootstrap host.
118.255            IN      PTR     bootstrap.ocp4.example.com.
~~~

d. Start/Test DNS:
~~~
$ chown named. /var/named/*.zone
$ systemctl enable named --now

$ vim /etc/resolv.conf  
nameserver 10.74.251.171

$ vim /etc/sysconfig/network-scripts/ifcfg-ens3 
DNS1=10.74.251.171

$ nslookup bootstrap.ocp4.example.com
$ nslookup master01.ocp4.example.com
$ nslookup master02.ocp4.example.com
$ nslookup master03.ocp4.example.com
$ nslookup worker01.ocp4.example.com
$ nslookup worker02.ocp4.example.com
$ nslookup api.ocp4.example.com
$ nslookup api-int.ocp4.example.com
$ nslookup 10.74.251.171
$ nslookup 10.74.251.61
$ nslookup 10.74.254.155
$ nslookup 10.74.253.133
$ nslookup 10.74.251.58
$ nslookup 10.74.253.49
$ nslookup 10.74.255.118
~~~

**1.5 Setup haproxy（load balancer）:**

a. Modify haproxy.cfg
~~~
$ cat /dev/null > /etc/haproxy/haproxy.cfg 
$ vim /etc/haproxy/haproxy.cfg 
global
  log         127.0.0.1 local2
  pidfile     /var/run/haproxy.pid
  maxconn     4000
  daemon

defaults
  mode                    http
  log                     global
  option                  dontlognull
  option http-server-close
  option                  redispatch
  retries                 3
  timeout http-request    10s
  timeout queue           1m
  timeout connect         10s
  timeout client          1m
  timeout server          1m
  timeout http-keep-alive 10s
  timeout check           10s
  maxconn                 3000

frontend stats
  bind *:1936
  mode            http
  log             global
  maxconn 10
  stats enable
  stats hide-version
  stats refresh 30s
  stats show-node
  stats show-desc Stats for ocp4 cluster 
  stats auth admin:passwd
  stats uri /stats

listen api-server-6443 
  bind 10.74.251.171:6443
  mode tcp
  server     bootstrap.ocp4.example.com 10.74.255.118:6443 check inter 1s backup
  server     master01.ocp4.example.com 10.74.251.61:6443 check inter 1s
  server     master02.ocp4.example.com 10.74.254.155:6443 check inter 1s
  server     master03.ocp4.example.com 10.74.253.133:6443 check inter 1s

listen machine-config-server-22623 
  bind 10.74.251.171:22623
  mode tcp
  server     bootstrap.ocp4.example.com 10.74.255.118:22623 check inter 1s backup
  server     master01.ocp4.example.com 10.74.251.61:22623 check inter 1s
  server     master02.ocp4.example.com 10.74.254.155:22623 check inter 1s
  server     master03.ocp4.example.com 10.74.253.133:22623 check inter 1s

listen default-ingress-router-80
  bind 10.74.251.204:80
  mode tcp
  balance source
  server     worker01.ocp4.example.com 10.74.251.58:80 check inter 1s
  server     worker02.ocp4.example.com 10.74.249.234:80 check inter 1s
  server     worker03.ocp4.example.com 10.74.251.9:80 check inter 1s

listen default-ingress-router-443
  bind 10.74.251.204:443
  mode tcp
  balance source
  server     worker01.ocp4.example.com 10.74.251.58:443 check inter 1s
  server     worker02.ocp4.example.com 10.74.249.234:443 check inter 1s
  server     worker03.ocp4.example.com 10.74.251.9:443 check inter 1s
~~~

b. Start haproxy:
~~~
$ systemctl enable haproxy --now
~~~

**1.6 Install oc  CLI/openshift install tools:**

- [Download oc CLI/openshift install tools](https://access.redhat.com/downloads/content/290/ver=4.10/rhel---8/4.10.13/x86_64/product-software)
~~~
- openshift-install:
$ wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.14.16/openshift-install-linux.tar.gz
$ tar xvf openshift-install-linux.tar.gz -C /usr/local/bin/

- oc CLI tools:
$ wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz 
$ tar xvf openshift-client-linux.tar.gz -C /usr/local/bin/ && rm -rf /usr/local/bin/README.md

- oc-mirror tools:
$ curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz
$ tar -xvf oc-mirror.tar.gz -C /usr/local/bin/ && chmod a+x /usr/local/bin/oc-mirror

- butane tools:
$ wget https://mirror.openshift.com/pub/openshift-v4/clients/butane/latest/butane
$ chmod a+x butane && mv butane /usr/local/bin/
~~~

**1.7 Self-signed cert and create offline mirror registry:**

- [View self-signed certificate](https://access.redhat.com/documentation/en-us/red_hat_codeready_workspaces/2.1/html/installation_guide/installing-codeready-workspaces-in-tls-mode-with-self-signed-certificates_crw)

a. Create registry directory:
~~~
$ mkdir -p /opt/registry/{auth,certs,data}
~~~

b. Set the required environment variables:
~~~
$ CA_CN="Local Red Hat Signer"
$ DOMAIN='docker.registry.example.com'
$ OPENSSL_CNF=/etc/pki/tls/openssl.cnf
~~~

c. Generate root ca.key:
~~~
$ mkdir -p /etc/crts/ && cd /etc/crts/
$ openssl genrsa -out /etc/crts/${DOMAIN}.ca.key 4096
~~~

d. Generate root ca.crt:
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

e. Generate domain key:
~~~
$ openssl genrsa -out ${DOMAIN}.key 2048
~~~

f. Generate domain cert csr:
~~~
$ openssl req -new -sha256 \
    -key /etc/crts/${DOMAIN}.key \
    -subj "/O=Local Red Hat CodeReady Workspaces/CN=${DOMAIN}" \
    -reqexts SAN \
    -config <(cat ${OPENSSL_CNF} \
        <(printf "\n[SAN]\nsubjectAltName=DNS:${DOMAIN}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
    -out /etc/crts/${DOMAIN}.csr
~~~

g. Generate domain crt:
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
    
$ openssl x509 -in /etc/crts/${DOMAIN}.ca.crt -text
~~~

h. Copy and trust the cert:
~~~
$ cp /etc/crts/${DOMAIN}.ca.crt ${DOMAIN}.crt /etc/pki/ca-trust/source/anchors/
$ update-ca-trust extract
$ cp /etc/crts/${DOMAIN}.key ${DOMAIN}.crt /opt/registry/certs/
$ update-ca-trust
~~~

i. Create username and password for offline mirror repository:
~~~
$ htpasswd -bBc /opt/registry/auth/htpasswd admin redhat
~~~

j. Running docker registry:
~~~
$ podman run --name mirror-registry \
    -p 5000:5000 \
    -e "REGISTRY_AUTH=htpasswd" \
    -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/${DOMAIN}.crt \
    -e REGISTRY_HTTP_TLS_KEY=/certs/${DOMAIN}.key \
    -e REGISTRY_STORAGE_DELETE_ENABLED=true \
    -v /opt/registry/data:/var/lib/registry:z \
    -v /opt/registry/auth:/auth:z \
    -v /opt/registry/certs:/certs:z \
    -d docker.io/library/registry:2

podmanrun -it -p 8080:8081 --name docker-registry-web --link docker-registry -e REGISTRY_URL=https://docker.registry.example.com:5000/v2 -e REGISTRY_NAME=docker.registry.example.com:5000 hyper/docker-registry-web

$ podman ps
  CONTAINER ID  IMAGE                         COMMAND               CREATED         STATUS             PORTS                   NAMES
  8a80baf5ee9e  docker.io/library/registry:2  /entrypoint.sh /e...  33 seconds ago  Up 33 seconds ago  0.0.0.0:5000->5000/tcp  mirror-registry
 
$ curl -u admin:redhat -k https://${DOMAIN}:5000/v2/_catalog
  {"repositories":[]}

$ podman login ${DOMAIN}:5000
~~~

k.Automatically start docker registry:
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

a. Download pull-secret:

- [Download pull-secret](https://cloud.redhat.com/openshift/install/metal/installer-provisioned)

b. Add repository authentication to pull-secret:
~~~
$ podman login --authfile /root/pull-secret docker.registry.example.com:5000   
$ podman login --authfile /root/pull-secret mirror.registry.example.com:8443 
  Username: admin
  Password: redhat
  Login Succeeded!
~~~

c. Set the required environment variables:
~~~
$ export OCP_RELEASE=4.10.20
$ export LOCAL_REGISTRY='docker.registry.example.com:5000'
$ export LOCAL_REPOSITORY='ocp4/openshift4'
$ export PRODUCT_REPO='openshift-release-dev' 
$ export LOCAL_SECRET_JSON='/root/pull-secret'
$ export RELEASE_NAME="ocp-release"
$ export ARCHITECTURE=x86_64
~~~

d. Download ocp image to docker registry:
Optional: Mirror repositories have internet access.
~~~
- Download image to registry:
$ oc adm -a ${LOCAL_SECRET_JSON} release mirror \
  --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
  --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
  --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE} 
...
- mirrors:                                      #<-- record image content source
  - docker.registry.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - docker.registry.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
~~~

Optional: Mirror repositories in restricted networks.
~~~
- Use “dry-run” parameter to get only “image Content Sources”, but not download images:
$ oc adm -a ${LOCAL_SECRET_JSON} release mirror \
     --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
     --to=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY} \
     --to-release-image=${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE} --dry-run

- Download image to directory:
$ oc adm -a /root/pull-secret release mirror --from=quay.io/openshift-release-dev/ocp-release:4.10.14-x86_64 --to-dir=/root/mirror

- Move the directory to the registry host on the restricted network, and then sync to the restricted network registry:
$ oc image mirror -a pull-secret --dir=/root/mirror file://openshift/release:4.10.14* docker.registry.example.com:5000/ocp4/openshift4
~~~

### 2. Install OpenShift Container Platform 4

**2.1 Create the SSH Key for logging in to the node:**
~~~
$ ssh-keygen
$ cat .ssh/id_rsa.pub
~~~

**2.2 Create install-config.yaml:**

- [View install-config](https://docs.openshift.com/container-platform/4.6/installing/installing_bare_metal/installing-restricted-networks-bare-metal.html#installation-bare-metal-config-yaml_installing-restricted-networks-bare-metal)
- [install-config](https://github.com/openshift/installer/blob/master/docs/user/customization.md#cluster-customization)
~~~
$ cat << EOF > /root/install-config.yaml 
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
  name: ocp4
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
pullSecret: '{"auths":{"docker.registry.example.com:5000": {"auth": "YWRtaW46cmVkaGF0","email": "copan@redhat.com"}}}' 
sshKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDGieiPgeguW4PZpCA7/U1EGlzR3gRRTaZ9KBaqmTnpelSuRiv5HbuHu2tel2quI2vEah264lgGyqt9uuOGKZg8/gtze8nmlTxrmjZGuW3+sCIUvC5gkySbmP5qgj7IgJE5CGj6mW7eLMNGgaFZQgAHzoZZwb+d1h+0N+i5KW+FhQETydX1R58oSmEbNTK2eXB0gzShKLXzoMEp+jvIcWtg4mgADGCYe3RPZtwoCj+P1aAKyaAFDQk7gFk1wYyjxD3VHeID82v81Ieu6dPG0bp1KFKanIfKIeSi1rIb/pemZSZmTq9t3fIuLMZjHzSF7GTkftWNJR1VGveUuNywTPhcccEusAO6Y1jf33yUD3m7sTPsgegjV/u2g3KasI+qmGml5rnrLBTxWGGMtKrq9mkB6YGa2Pz7CpzmlMp2LHMR4Uuysy0+j3C4LGBiPPW2uonx+8FbEkZTv38/96hbBOWEexqsO8PYjbhuNC8tdrmmo1MXwshIBxjLp/7SihUay1c= root@bastion'
additionalTrustBundle: | 
  -----BEGIN CERTIFICATE-----
  MIIE7jCCAtagAwIBAgIUTEqQ/sV+Ll9TZzWS2TRopnUcsaswDQYJKoZIhvcNAQEL
  BQAwHzEdMBsGA1UEAwwUTG9jYWwgUmVkIEhhdCBTaWduZXIwIBcNMjMwMzI5MDYx
  MjQ0WhgPMjEyMzAzMDUwNjEyNDRaMB8xHTAbBgNVBAMMFExvY2FsIFJlZCBIYXQg
  U2lnbmVyMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA7oqBgXQ1LyAJ
  Os1hLJUQ4GDhraesxhynnM3QdmvxqlOg4GQcsbXtyIDM2yUVLlT1sAXPRM0lrfJ9
  zvDTtV5o2tZilGbvxs6/vY7PhDLcyCMgfr+2YxBNh896DyB4hyO/j8l8JCFe5iyZ
  pX+mIgoQuTUWV8w8AGgkddQi66dxAetqxfBWksZJ+lmiMB2jGWZ9iY5LvPacB6ev
  lIX7/GWbhiz2xx2Tz48qC0l3gvT3LqRc6HokNamlTBy2nJ+Y0E202HDgHgUzLHs7
  u9tDwEC9QYOrXgtK725k6Lpih1FKItddBA6MYt6lAStpsAdWb9YtfhKH+W/N51+0
  eLDvm4iGIxZa1ZQ18YscAeAAhfbYBv61MWpqIGW9o3LlF6CsNW6VkttYTtzKgElB
  Crtdd33yo8vGAPC7mlz0Tr4gtONsxnf3bY97nT8W9pauxNGLUvsYhP2lCRZEQG9v
  z2SlXhHyaDzllgxrBB03XlnmNE1EUTUrGNXoCLGgOxV7D3fR4SpsYmBPlywHn/j0
  BnL0V8LX6T09xacmkKh12nunOfprwYv3vXgkXsZI29OWAH+6IJTh5EuewyViZiLs
  GZznrEWvov3+n8DITMmaL0bot2f9Vh/g28XNtNvALb+GkjP/UIweO3+rDYhDCtEL
  Cd1klqay/hlWdM1/y2r6Q1DyBU6XLbkCAwEAAaMgMB4wDwYDVR0TAQH/BAUwAwEB
  /zALBgNVHQ8EBAMCAYYwDQYJKoZIhvcNAQELBQADggIBAN6HMCofNXFfzWEieH2f
  VyFcit5ThMxt7+iFkZqzUOZiWwoHMXB+I3Y+bWyFK8l++MiDmqxA3mKHxgN8EtSZ
  k8dO5poHTEUcxuYNKzU8GG5aBi46ZUiSOGl+P9JHuklaO7lKTdcxLh9p/uupwj/L
  CJhsFVKmTZDQCsSkOEy0UxQUqdAvjc7yOJLRYuHCIqA9sWORY2ltRUUPZnMT2CZu
  Hy1AS8Vh9NHc4JTlGwmiuFUE+YZggSFPoPVKY1KqTF6Pfg04t33XGRlp8DTgQa2U
  Hik8HkWjSNrape25SG1Ftl7VmmPZSSAlDNoUDaYAcZTL/90fb0tm73r9uDUeYTSH
  iWNQiWZxVegAzq/82X0LvulIT6gG3XA62/AxhJ40JljMudGl81vN69dsnyhhVBVt
  ryiSRfaV7zfRuRZ+BZO6KMsY8++uW/TM1XFcQa1kCJGBKc24qjK546K4/Lqk8nwR
  devSNoRxGwgRb2ioKvmhjELnBViQw3Oap+FQd3PxjX3lnVtwX4T0yMTEvYpj45l4
  rtV+pXDnU+a1ZiZ5trv2Hfy7ov1H4GjjdD7V6vuuAU01uX0OmSg8y1fo6xS8bdyN
  BlktY9DxKjVjtJRwdxtZ8Jh3mP4kl+CVn4hRGRKKhEl+mHaDZPB7HXbrl6t0E7fW
  A2YPIaaC0DOH6Y+57oVMfAtr
  -----END CERTIFICATE-----
imageContentSources:
- mirrors:
  - docker.registry.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - docker.registry.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF
~~~

**2.3 Create kubernetes manifests:**
~~~
$ mkdir /var/www/html/materials/pre

$ cp /root/install-config.yaml  /var/www/html/materials/pre
 
$ cd /var/www/html/materials

$ openshift-install create manifests --dir pre/ 

$ sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' /var/www/html/materials/pre/manifests/cluster-scheduler-02-config.yml

OR

$ vim /var/www/html/materials/pre/manifests/cluster-scheduler-02-config.yml
  masterSchedulable: false    #<----- master does not run custom pods
~~~

**2.4 Create ignition configuration files:**
~~~
$ openshift-install create ignition-configs --dir pre
$ chmod a+r pre/*.ign
~~~

**2.5 Mount the ISO to create the RHCOS machine:**

a.Download RHCOS.iso

> **IMPORTANT**
 The RHCOS images might not change with every release of OpenShift Container Platform. You must download images with the highest version that is less than or equal to the OpenShift Container Platform version that you install. Use the image versions that match your OpenShift Container Platform version if they are available. Use only ISO images for this procedure. RHCOS qcow2 images are not supported for this installation type.

~~~
$ curl -s https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.10/latest/sha256sum.txt | awk '{print $2}' | grep rhcos

$ echo ${RHCOS_RELEASE}

$ wget https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.10/${RHCOS_RELEASE}/rhcos-${RHCOS_RELEASE}-x86_64-live.x86_64.iso
~~~

b.Install bootstrap:
~~~
- 1.Mount ISO，
- 2.Boot and confirm the disk name
- 3.Restart and press the "Tab" key to enter the kernel editing page
- 4.enter install command

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.74.251.171:8080/pre/bootstrap.ign
ip=10.74.255.118::10.74.255.254:255.255.248.0:bootstrap.ocp4.example.com:ens3:none
nameserver=10.74.251.171 nameserver=10.74.251.204

- After the restart is complete, access the bootstrap node:
$ ssh core@bootstrap.ocp4.example.com
$ sudo -i

- Check if it is normal or not:
$ netstat -ntplu |grep 6443
$ netstat -ntplu |grep 22623
$ podman ps
$ journalctl -b -f -u release-image.service -u bootkube.service
~~~

c.Install master 01 - 03:
~~~
$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.74.251.171:8080/pre/master.ign  
ip=10.74.251.61::10.74.255.254:255.255.248.0:master01.ocp4.example.com:ens3:none
nameserver=10.74.251.171 nameserver=10.74.251.204

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.74.251.171:8080/pre/master.ign  
ip=10.74.254.155::10.74.255.254:255.255.248.0:master02.ocp4.example.com:ens3:none
nameserver=10.74.251.171 nameserver=10.74.251.204

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.74.251.171:8080/pre/master.ign  
ip=10.74.253.133::10.74.255.254:255.255.248.0:master03.ocp4.example.com:ens3:none
nameserver=10.74.251.171 nameserver=10.74.251.204
~~~

d. Check if master is installed:
~~~
$ ssh core@bootstrap.ocp4.example.com
$ sudo -i
$ journalctl -b -f -u bootkube.service
···Wait···
bootkube.service complete    #
bootkube.service: Succeeded  #<--Show this content to complete the master installation.
~~~

e. Install worker 01 - 02:
~~~
$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.74.251.171:8080/pre/worker.ign  
ip=10.74.251.58::10.74.255.254:255.255.248.0:worker01.ocp4.example.com:ens3:none
nameserver=10.74.251.171 nameserver=10.74.251.204

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.74.251.171:8080/pre/worker.ign  
ip=10.74.249.234::10.74.255.254:255.255.248.0:worker02.ocp4.example.com:ens3:none
nameserver=10.74.251.171 nameserver=10.74.251.204

- Wait for the reboot to complete:
~~~

**2.6 login ocp:**
~~~
- kubeconfig login:
$ echo export KUBECONFIG=/var/www/html/materials/pre/auth/kubeconfig >> /root/.bash_profile

or

- kubeadmin login 
$ cat /var/www/html/materials/pre/auth/kubeadmin-password
$ vim /root/.bash_profile
if [ ! -f "$HOME/.oc_login_executed" ]; then
    oc login -u kubeadmin -p UDhyZ-t3iHt-hzF9M-RU7Mr https://api.ocp4.example.com:6443
    touch "$HOME/.oc_login_executed"
fi

- Save the file either as $XDG_RUNTIME_DIR/containers/auth.json.
$ echo PROMPT_COMMAND='podman login -u admin -p redhat docker.registry.example.com:5000; cat /root/pull-secret | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json'
$ echo export LANG=“en_US.UTF-8” >> ~/.bash_profile
$ source ~/.bash_profile

- completion command:
$ oc completion bash >> /etc/bash_completion.d/oc_completion
$ oc whoami
system:admin

$ source ~/.bash_profile
~~~

**2.7 approval csr，Allow adding worker nodes:**
~~~
$ oc get csr
$ oc get csr -o name | xargs oc adm certificate approve
~~~

**2.8 Check OCP Cluster:**
~~~
$ oc get node
$ oc get mcp
$ oc get co | grep -v '.True.*False.*False'
~~~

**2.9 Modify image-registry storage:**

a.Setup NFS:
~~~
$ mkdir /nfs
$ mkdir /nfs/image-registry
$ mkdir /nfs/pv001 pv002 pv003 pv004 pv005 pv006 pv007 pv008 pv009
$ useradd nfsnobody
$ chown -R nfsnobody.nfsnobody /nfs
$ chmod -R 777 /nfs
$ echo '/nfs    **(rw,sync,no_wdelay,no_root_squash,insecure,fsid=0)' >> /etc/exports
$ systemctl enable nfs-server --now
~~~

b.Create PV:
~~~
$ cat << EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: image-registry
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteOnce
  nfs:
    path: /nfs/image-registry
    server: 10.74.251.171
  persistentVolumeReclaimPolicy: Retain
EOF
~~~



c.Modify image-registry operator:
~~~
$ oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed"}}'
$ oc patch configs.imageregistry.operator.openshift.io/cluster --type merge --patch '{"spec":{"storage":{"pvc":{"claim":""}}}}'
oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Removed"}}'
or

$ oc edit configs.imageregistry.operator.openshift.io
spec:
  logLevel: Normal
  managementState: Managed    ##<-- Removed to Managed
 storage:                     ##<-- add
   pvc:
     claim:
~~~

**2.10 Trust the external registry:**

a.Create configmap:
~~~
$ oc create configmap registry-cas \
     --from-file=docker.registry.example.com..5000=/etc/pki/ca-trust/source/anchors/docker.registry.example.com.ca.crt \
     -n openshift-config
~~~
b.Trust repository
~~~
$ oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}' --type=merge

$ ssh core@master01.ocp4.example.com ls -ltr /etc/docker/certs.d/
~~~
