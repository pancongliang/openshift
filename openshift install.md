## Installing a user-provisioned bare metal cluster on a restricted network

**Server info**
Hostname | Role | IP | OS |
--- |--- |--- |--- 
bastion.ocp4.example.com    | bastion | 10.72.36.200     |rhel8
docker.registry.example.com | bastion | 10.72.36.200     |rhel8
master01.ocp4.example.com   | master | 10.72.36.151      |coreos
master02.ocp4.example.com   | master | 10.72.36.152      |coreos
master03.ocp4.example.com   | master | 10.72.36.153      |coreos
worker01.ocp4.example.com   | worker | 10.72.36.154      |coreos
worker02.ocp4.example.com   | worker | 10.72.36.155      |coreos
bootstrap.ocp4.example.com  | bootstrap | 10.72.36.159   |coreos


### 1.Create the user-provisioned infrastructure (bastion) 

**1.1 Setup subscription:**
~~~
$ subscription-manager register --username=xxx --password=xxx --auto-attach

$ subscription-manager list --available |more
  Employee SKU

$ subscription-manager attach --pool=xxxxx
~~~

**1.2 Install the necessary software:**
~~~
$ yum install -y wget net-tools podman bind-utils bind haproxy git bash-completion vim jq nfs-utils httpd httpd-tools skopeo httpd-manual
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
$ wget http://10.72.36.200:8080/testfile
~~~

**1.4 Setup DNS server:**

a. Modify named.conf:
~~~
$ vim /etc/named.conf
//
// named.conf
//
// Provided by Red Hat bind package to configure the ISC BIND named(8) DNS
// server as a caching only nameserver (as a localhost DNS resolver only).
//
// See /usr/share/doc/bind*/sample/ for example named configuration files.
//
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

        dnssec-enable yes;
        dnssec-validation yes;

        managed-keys-directory "/var/named/dynamic";

        pid-file "/run/named/named.pid";
        session-keyfile "/run/named/session.key";

        /* https://fedoraproject.org/wiki/Changes/CryptoPolicy */
        #include "/etc/crypto-policies/back-ends/bind.config";
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


include "/etc/named.rfc1912.zones";
#include "/etc/named.root.key";
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
ns1     IN      A       10.72.36.200
;
helper  IN      A       10.72.36.200
helper.ocp4     IN      A       10.72.36.200
;
; The api identifies the IP of your load balancer.
api.ocp4.example.com.                  IN      A       10.72.36.200
api-int.ocp4.example.com.              IN      A       10.72.36.200
;
; The wildcard also identifies the load balancer.
*.apps.ocp4.example.com.               IN      A       10.72.36.200
;
; Create entries for the master hosts.
master01.ocp4.example.com.             IN      A       10.72.36.151
master02.ocp4.example.com.             IN      A       10.72.36.152
master03.ocp4.example.com.             IN      A       10.72.36.153
;
; Create entries for the worker hosts.
worker01.ocp4.example.com.             IN      A       10.72.36.154
worker02.ocp4.example.com.             IN      A       10.72.36.155
;
; Create an entry for the bootstrap hosts.
bootstrap.ocp4.example.com.            IN      A       10.72.36.159
;
; Create entries for the mirror registry hosts.
docker.registry.example.com.           IN      A       10.72.36.200
~~~

c. Add DNS PTR record:
~~~
$ vim /var/named/72.10.zone
$TTL 1W
@       IN      SOA     ns1.example.com.      root (
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
200.36             IN      PTR     api.ocp4.example.com.
200.36             IN      PTR     api-int.ocp4.example.com.
;
; Create entries for the master hosts.
151.36             IN      PTR     master01.ocp4.example.com.
152.36             IN      PTR     master02.ocp4.example.com.
153.36             IN      PTR     master03.ocp4.example.com.
;
; Create entries for the worker hosts.
154.36             IN      PTR     worker01.ocp4.example.com.
155.36             IN      PTR     worker02.ocp4.example.com.
;
; Create an entry for the bootstrap hosts.
159.36             IN      PTR     bootstrap.ocp4.example.com.
~~~

d. Start/Test DNS:
~~~
$ chown named. /var/named/*.zone
$ systemctl enable named --now

$ vim /etc/resolv.conf  
nameserver 10.72.36.200

$ vim /etc/sysconfig/network-scripts/ifcfg-ens3 
DNS1=10.72.36.200

$ nslookup bootstrap.ocp4.example.com
$ nslookup master01.ocp4.example.com
$ nslookup master02.ocp4.example.com
$ nslookup master03.ocp4.example.com
$ nslookup worker01.ocp4.example.com
$ nslookup worker02.ocp4.example.com
$ nslookup api.ocp4.example.com
$ nslookup api-int.ocp4.example.com
$ nslookup *.apps.ocp4.example.com
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
# option http-server-close
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
  bind 10.72.36.200:6443
  mode tcp
  server     bootstrap.ocp4.example.com 10.72.36.159:6443 check
  server     master01.ocp4.example.com 10.72.36.151:6443 check
  server     master02.ocp4.example.com 10.72.36.152:6443 check
  server     master03.ocp4.example.com 10.72.36.153:6443 check

listen machine-config-server-22623 
  bind 10.72.36.200:22623
  mode tcp
  server     bootstrap.ocp4.example.com 10.72.36.159:22623 check
  server     master01.ocp4.example.com 10.72.36.151:22623 check
  server     master02.ocp4.example.com 10.72.36.152:22623 check
  server     master03.ocp4.example.com 10.72.36.153:22623 check

listen default-ingress-router-80
  bind 10.72.36.200:80
  mode tcp
  balance source
  server     worker01.ocp4.example.com 10.72.36.154:80 check
  server     worker02.ocp4.example.com 10.72.36.155:80 check

listen default-ingress-router-443
  bind 10.72.36.200:443
  mode tcp
  balance source
  server     worker01.ocp4.example.com 10.72.36.154:443 check
  server     worker02.ocp4.example.com 10.72.36.155:443 check
~~~

b. Start haproxy:
~~~
$ systemctl enable haproxy --now
~~~

**1.6 Install oc  CLI/openshift install tools:**

- [Download oc CLI/openshift install tools](https://access.redhat.com/downloads/content/290/ver=4.10/rhel---8/4.10.20/x86_64/product-software)
~~~
- openshift-install:
$ wget https://access.redhat.com/downloads/content/290/ver=4.10/rhel---8/4.10.20/x86_64/product-software/openshift-install-linux-4.10.20.tar.gz
$ tar xvf openshift-install-linux-4.10.20.tar.gz
$ mv openshift-install /usr/local/bin/

- oc CLI tools:
$ wget https://access.redhat.com/downloads/content/290/ver=4.10/rhel---8/4.10.20/x86_64/product-software/oc-4.10.20-linux.tar.gz
$ tar xvf oc-4.10.20-linux.tar.gz
$ mv oc kubectl /usr/local/bin/
$ oc version
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
$ podman run \
    --name mirror-registry \
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

$ podman ps
  CONTAINER ID  IMAGE                         COMMAND               CREATED         STATUS             PORTS                   NAMES
  8a80baf5ee9e  docker.io/library/registry:2  /entrypoint.sh /e...  33 seconds ago  Up 33 seconds ago  0.0.0.0:5000->5000/tcp  mirror-registry
 
$ curl -u admin:redhat -k https://docker.registry.example.com:5000/v2/_catalog
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
- mirrors:                                      #<-- record ImageContentSourcePolicies
  - docker.registry.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - docker.registry.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
~~~

### 2. Install OpenShift Container Platform 4

**2.1 Create the SSH Key for logging in to the node:**
~~~
$ ssh-keygen
$ cat .ssh/id_rsa.pub
~~~

**2.2 Create install-config.yaml:**

- [View install-config](https://docs.openshift.com/container-platform/4.6/installing/installing_bare_metal/installing-restricted-networks-bare-metal.html#installation-bare-metal-config-yaml_installing-restricted-networks-bare-metal)
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
pullSecret: '{"auths":{"docker.registry.example.com:5000": {"auth": "xxxxxx","email": "xxxxx@xxxxx.com"}}}'
sshKey: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC2W5zGDsgPmEqph1piJRl/BO1yETKt7U2kUJFnkJ7VEj62ZubhPI16gTjhvO+kWl1yN6oDo840hVtmHKT799euBI82EyeeGdmgxbq0vFTs36+Np76jhaSsvCo+GLb7Si8j8PFnxEAmZ14byxqLR6XY6YUkQrk9+T6dINziiOHhkdATrOr1qbL/YSjm/nPVjFpV60IGzBOZ47ILJIVSNRLHrC/Pf+vxkRQvfQ9IAwTQDMV1t6vbxI8c+TJ9iI0SFJZvNaHiNVxa4NwBf3t0Uqr8xJhH5pWZFX3oP4RuQECgbvKuefAC3N+Ww5oMsTYgdj1bvs1ofvBT2P6s4EVKzxifcppT413O4fGiy7TEBd5ggeX0UghQ1JVhhF7YBQ9cYat8Ag6zWHd5AZYF5JSh+RFAclGLKdCnluWeNGFHeXTkVQcpMfUFaCiuocxgeS07MnNuwTUXAhBh2X7I1E3Qy0DmcJw8EF3DMvq9PmbM9IavDxcO6i40dMM1bdWDF6wwY60= root@bastion'      #<-- bastion server(cat .ssh/id_rsa.pub)
additionalTrustBundle: |         #<--- Registry's root ca certificate(cat /etc/crts/docker.registry.example.com.ca.crt)
  -----BEGIN CERTIFICATE-----
  MIIFGDCCAwCgAwIBAgIUMOHuyhyVNF3K3pB8jfcFMNDwEaYwDQYJKoZIhvcNAQEL
  BQAwNDEyMDAGA1UEAwwpTG9jYWwgUmVkIEhhdCBDb2RlUmVhZHkgV29ya3NwYWNl
  cyBTaWduZXIwIBcNMjMwMTAzMDM1NjA1WhgPMjEyMjEyMTAwMzU2MDVaMDQxMjAw
  BgNVBAMMKUxvY2FsIFJlZCBIYXQgQ29kZVJlYWR5IFdvcmtzcGFjZXMgU2lnbmVy
  MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEApDWp7g9zdbDAjrMb+bhF
  zr6xYuFib9MpmT8c9KCILjxKpdt8rFtZ6XI/cCWy/lN1MCBe+cIetsYOwAn1y1dI
  CBAHQkJwfd2DpUwvKL3n/5a9t4eVn8RE/Bbp7otg0i9Aks8d787dUrAvhzQiowbb
  jk6UPg3lrmLbq5ZggTk+vBnSbhB2pVeN3GEpHyOINbHfPa4ZNsfOFkdYqQddrQXz
  shOq8zrIMWRRzJUY3D1kzN28IpCp7T2KPixYT8bv3tJBMRzequAyVlefsU6pYLjx
  IMbXhHNN5EwDPgPrrZstCZY/qneQxNvzBxAYr3fnqRjf9nINbKWpgPH8kRBMos7o
  bWBVgYkfsDlWULxrLbujJDcJWbymMRYnLNj8BMKiG/u3RSj52zDjiiqp290ID+VI
  4B2Lf6qd2QKCv42FgjMo3tcpzSqcJytWfAdF0MR0VV86ffexsMXntd+2E7edzSdu
  7aK9SKXq18Hpjcn6o4hN04q+6pO5mYYyX635NqnSRX3OhGqgVT8doEYWlVHslzFD
  q8l6TIJck17vMuu/xxh20CF6ophy3tYqhD1QeXPZGDfS6CXokYuWOxqHTQ+WzTeB
  5b/BdQdgLwaNKPHoZERU0azpbnFaiFwmfmdsmpOGn/HSwOwgP9vt16OhF12vGlNE
  gFr3ZnzsZRHA4/CWoEbqA9kCAwEAAaMgMB4wDwYDVR0TAQH/BAUwAwEB/zALBgNV
  HQ8EBAMCAYYwDQYJKoZIhvcNAQELBQADggIBAGKrPgfHXcSlgeSaP0lyeugwX38h
  vJ64v8qnHRIqh2R7v9ZoMh0WdAEyrdXQjoCegipZXq7lLX8oEGu2mewc+l1ZT+z8
  b7bBJvqrm4IXIpg+sy+Yinu+c8rEflsK7aV5Vd/2QV2OH1lpkCM1cDtN6meGn0Bm
  c+RFLWfBBa38+6zvUuQCFlesxExqbLA4ZWd1OrDVHrsXE67Te35tbKfv5gAuXBcd
  2xwSTtrxMXCHsUksgVgA4vgfQ16DlLeYCYooOEsnKNujechYl2a81w/Wz4DwxRnd
  /d/Hj8NwJengxeLBn7szIM1zqSiQyYHUbxsE64MRe5FthIgMVIsOjIJHYq2+SWrJ
  gC8BNvlrKuvZBKl2twSXEpNlMF6KFlu7D49y+IMSJjh9rFB2+V+C8f5W+LXqYJPk
  DjK51J/0dP+ol8b3ecFQ2+x0qG42esOKg0r8suGWsWwNMBKK3blZ30fzEarSKC7R
  HfII9vInVXJ01aVIEqIFikNPCdlYOUxFOd8jcVC5f/jNtlKHh+JBdZcvoAf6bMYQ
  7g5nG7Daycn2hAehNIVDkwXNsC+Z8XoLognIWj6Sx3Zu01LgoeA57PY+/2fx/+Kk
  0JaAkROB5kLYL6cmfJwMeAPQJo2iI6COGOb6gLIoOe4BXzGEklIgdHIWj0TEvGC1
  5dnZNuPpqP/oxMwv
  -----END CERTIFICATE-----
imageContentSources:      #<-- ImageContentSourcePolicies output in step 1.8-d
- mirrors:
  - docker.registry.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - docker.registry.example.com:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
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

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.36.200:8080/pre/bootstrap.ign
ip=10.72.36.159::10.72.37.254:255.255.254.0:bootstrap.ocp4.example.com:ens3:none
nameserver=10.72.36.200 nameserver=10.72.36.199

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
$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.36.200:8080/pre/master.ign  
ip=10.72.36.151::10.72.37.254:255.255.254.0:master01.ocp4.example.com:ens3:none
nameserver=10.72.36.200 nameserver=10.72.36.199

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.36.200:8080/pre/master.ign  
ip=10.72.36.152::10.72.37.254:255.255.254.0:master02.ocp4.example.com:ens3:none
nameserver=10.72.36.200 nameserver=10.72.36.199

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.36.200:8080/pre/master.ign  
ip=10.72.36.153::10.72.37.254:255.255.254.0:master03.ocp4.example.com:ens3:none
nameserver=10.72.36.200 nameserver=10.72.36.199
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
$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.36.200:8080/pre/worker.ign  
ip=10.72.36.154::10.72.37.254:255.255.254.0:worker01.ocp4.example.com:ens3:none
nameserver=10.72.36.200 nameserver=10.72.36.199

$ coreos.inst.install_dev=sda coreos.inst.ignition_url=http://10.72.36.200:8080/pre/worker.ign  
ip=10.72.36.155::10.72.37.254:255.255.254.0:worker02.ocp4.example.com:ens3:none
nameserver=10.72.36.200 nameserver=10.72.36.199

- Wait for the reboot to complete:
~~~

**2.6 login ocp:**
~~~
- add variable:
$ vim .bash_profile
export KUBECONFIG=/var/www/html/materials/pre/auth/kubeconfig

$ oc whoami
system:admin
~~~

**2.7 approval csr，Allow adding worker nodes:**
~~~
$ oc get csr
$ oc get csr -o go-template='{{range .items}}{{if not .status}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}' | xargs --no-run-if-empty oc adm certificate approve
~~~

**2.8 Check OCP Cluster:**
~~~
$ oc get node
$ oc get mcp
$ oc get co | grep -v '.True.*False.*False'

- completion command:
$ oc completion bash >> /etc/bash_completion.d/oc_completion
~~~

**2.9 Modify image-registry storage:**

a.Setup NFS:
~~~
$ mkdir /nfs
$ useradd nfsnobody
$ chown -R nfsnobody.nfsnobody /nfs
$ chmod -R 777 /nfs
$ vim /etc/exports
/nfs    **(rw,sync,no_wdelay,no_root_squash,insecure,fsid=0)
$ systemctl enable nfs-server --now
~~~

b.Create PV:
~~~
$ cat << EOF > ./nfs-pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: image-registry
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteMany
  nfs:
    path: /nfs/image-registry
    server: 10.72.36.200
  persistentVolumeReclaimPolicy: Retain
EOF

$ oc create -f nfs-pv.yaml
~~~

c.Modify image-registry operator:
~~~
$ oc patch configs.imageregistry.operator.openshift.io cluster -p '{"spec":{"managementState": "Managed","storage":{"pvc":{"claim":""}}}}' --type=merge
~~~

**2.10 Trust the docker repository:**

a.Create configmap:
~~~
$ oc create configmap registry-config \
     --from-file=docker.registry.example.com..5000=/etc/pki/ca-trust/source/anchors/docker.registry.example.com.ca.crt \
     -n openshift-config
~~~
b.Trust repository
~~~
$ oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-config"}}}' --type=merge
~~~

**2.11 Set “samples operator” to specify the docker registry:**
~~~
$ oc patch configs.samples.operator.openshift.io cluster --patch '[{"op": "replace", "path": "/spec/managementState", "value":"Removed"}]' --type=json

$ oc patch configs.samples.operator.openshift.io cluster --patch '{"spec":{"samplesRegistry":null,"skippedImagestreams":null}}' --type=merge

$ oc patch configs.samples.operator.openshift.io cluster --patch '[{"op": "replace", "path": "/spec/managementState", "value":"Managed"}]' --type=json

$ oc patch configs.samples.operator.openshift.io cluster --patch '{"spec":{"samplesRegistry":"docker.registry.example.com","skippedImagestreams":["jenkins","jenkins-agent-nodejs","jenkins-agent-maven"]}}' --type=merge
~~~
