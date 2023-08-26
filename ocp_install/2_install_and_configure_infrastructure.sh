
# Install required packages
yum install -y wget net-tools podman bind-utils bind haproxy git bash-completion vim jq nfs-utils httpd httpd-tools skopeo httpd-manual

# openshift-install:
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OCP_RELEASE/openshift-install-linux.tar.gz
tar xvf openshift-install-linux.tar.gz -C /usr/local/bin/ && rm -rf openshift-install-linux.tar.gz

# oc CLI tools:
wget https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz
tar xvf openshift-client-linux.tar.gz -C /usr/local/bin/ && rm -rf /usr/local/bin/README.md && rm -rf openshift-client-linux.tar.gz

# oc-mirror tools:
curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz
tar -xvf oc-mirror.tar.gz -C /usr/local/bin/ && chmod a+x /usr/local/bin/oc-mirror && rm -rf oc-mirror.tar.gz

# butane tools:
wegt https://mirror.openshift.com/pub/openshift-v4/clients/butane/latest/butane
chmod a+x butane && mv butane /usr/local/bin/

# Disable firewalld
systemctl disable firewalld
systemctl stop firewalld

# SELinux
SELINUX=$(getenforce)
echo $SELINUX

if [ $SELINUX = 'Enforcing' ]; then
  sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
  reboot
fi

sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config
setenforce 0

### Set httpd configuration ### 
sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf

# Create base.conf for VirtualHost
cat << EOF > /etc/httpd/conf.d/base.conf
<VirtualHost *:8080>
   ServerName bastion
   DocumentRoot $HTTPD_PATH
</VirtualHost>
EOF

# Enable and start httpd
systemctl enable httpd --now

### Set nfs ###
mkdir /nfs
mkdir /nfs/image-registry
useradd nfsnobody
chown -R nfsnobody.nfsnobody /nfs
chmod -R 777 /nfs
echo '/nfs    **(rw,sync,no_wdelay,no_root_squash,insecure,fsid=0)' >> /etc/exports

systemctl enable nfs-server --now

###  Apply named.conf configuration ### 
cat << EOF > /etc/named.conf
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
        forwarders      { $DNS_FORWARDER_IP; };

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

zone "$BASE_DOMAIN" IN {
        type master;
        file "$BASE_DOMAIN.zone";
        allow-query { any; };
};

zone "$REVERSE_ZONE" IN {
        type master;
        file "$REVERSE_ZONE_FILE_NAME";
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
EOF

# Add DNS A/AAAA record
cat << EOF >  /var/named/$BASE_DOMAIN.zone
\$TTL 1W
@       IN      SOA     ns1.$BASE_DOMAIN.        root (
                        201907070      ; serial
                        3H              ; refresh (3 hours)
                        30M             ; retry (30 minutes)
                        2W              ; expiry (2 weeks)
                        1W )            ; minimum (1 week)
        IN      NS      ns1.$BASE_DOMAIN.
;
;
ns1     IN      A       $BASTION_IP
;
helper  IN      A       $BASTION_IP
helper.ocp4     IN      A       $BASTION_IP
;
; The api identifies the IP of your load balancer.
$API_HOSTNAME.                  IN      A       $API_IP
$API_INT_HOSTNAME.              IN      A       $API_INT_IP
;
; The wildcard also identifies the load balancer.
$APPS_HOSTNAME.                 IN      A       $APPS_IP
;
; Create entries for the master hosts.
$MASTER01_HOSTNAME.             IN      A       $MASTER01_IP
$MASTER02_HOSTNAME.             IN      A       $MASTER02_IP
$MASTER03_HOSTNAME.             IN      A       $MASTER03_IP
;
; Create entries for the worker hosts.
$WORKER01_HOSTNAME.             IN      A       $WORKER01_IP
$WORKER02_HOSTNAME.             IN      A       $WORKER02_IP
;
; Create an entry for the bootstrap host.
$BOOTSTRAP_HOSTNAME.            IN      A       $BOOTSTRAP_IP
;
; Create entries for the mirror registry hosts.
$REGISTRY_HOSTNAME.             IN      A       $REGISTRY_IP
EOF

# Add DNS PTR record
cat << EOF >  /var/named/$REVERSE_ZONE_FILE_NAME
\$TTL 1W
@       IN      SOA     ns1.$BASE_DOMAIN.        root (
                        2019070700      ; serial
                        3H              ; refresh (3 hours)
                        30M             ; retry (30 minutes)
                        2W              ; expiry (2 weeks)
                        1W )            ; minimum (1 week)
        IN      NS      ns1.$BASE_DOMAIN.
;
; The syntax is "last octet" and the host must have an FQDN
; with a trailing dot.
;
; The api identifies the IP of your load balancer.
$API_REVERSE_DNS                IN      PTR     $API_HOSTNAME.
$API_INT_REVERSE_DNS            IN      PTR     $API_INT_HOSTNAME.
;
; Create entries for the master hosts.
$MASTER01_REVERSE_DNS           IN      PTR     $MASTER01_HOSTNAME.
$MASTER02_REVERSE_DNS           IN      PTR     $MASTER02_HOSTNAME.
$MASTER03_REVERSE_DNS           IN      PTR     $MASTER02_HOSTNAME.
;
; Create entries for the worker hosts.
$WORKER01_REVERSE_DNS           IN      PTR     $WORKER01_HOSTNAME.
$WORKER02_REVERSE_DNS           IN      PTR     $WORKER02_HOSTNAME.
EOF

# Restart DNS
chown named. /var/named/*.zone
echo "nameserver $BASTION_IP" >> /etc/resolv.conf
systemctl enable named --now

### Set haproxy_cfg ###
cat << EOF > /etc/haproxy/haproxy.cfg 
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
  bind $BASTION_IP:6443
  mode tcp
  server     $BOOTSTRAP_HOSTNAME $BOOTSTRAP_IP:6443 check inter 1s backup
  server     $MASTER01_HOSTNAME $MASTER01_IP:6443 check inter 1s
  server     $MASTER02_HOSTNAME $MASTER02_IP:6443 check inter 1s
  server     $MASTER03_HOSTNAME $MASTER03_IP:6443 check inter 1s

listen machine-config-server-22623 
  bind $BASTION_IP:22623
  mode tcp
  server     $BOOTSTRAP_HOSTNAME $BOOTSTRAP_IP:22623 check inter 1s backup
  server     $MASTER01_HOSTNAME $MASTER01_IP:22623 check inter 1s
  server     $MASTER02_HOSTNAME $MASTER02_IP:22623 check inter 1s
  server     $MASTER03_HOSTNAME $MASTER03_IP:22623 check inter 1s

listen default-ingress-router-80
  bind $BASTION_IP:80
  mode tcp
  balance source
  server     $WORKER01_HOSTNAME $WORKER01_IP:80 check inter 1s
  server     $WORKER02_HOSTNAME $WORKER02_IP:80 check inter 1s

listen default-ingress-router-443
  bind $BASTION_IP:443
  mode tcp
  balance source
  server     $WORKER01_HOSTNAME $WORKER01_IP:443 check inter 1s
  server     $WORKER02_HOSTNAME $WORKER02_IP:443 check inter 1s
EOF

# Start haproxy:
systemctl enable haproxy --now

### Self_signed_cert_and_create_registry ### 
# Create registry directory:
mkdir -p /opt/registry/{auth,certs,data}
mkdir -p /etc/crts/ && cd /etc/crts/

# Generate root ca.key
openssl genrsa -out /etc/crts/${REGISTRY_HOSTNAME}.ca.key 4096

# Generate root ca.crt
openssl req -x509 \
  -new -nodes \
  -key /etc/crts/${REGISTRY_HOSTNAME}.ca.key \
  -sha256 \
  -days 36500 \
  -out /etc/crts/${REGISTRY_HOSTNAME}.ca.crt \
  -subj /CN="Local Red Hat Signer" \
  -reqexts SAN \
  -extensions SAN \
  -config <(cat /etc/pki/tls/openssl.cnf \
      <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature'))

# Generate domain key
openssl genrsa -out ${REGISTRY_HOSTNAME}.key 2048

# Generate domain cert csr
openssl req -new -sha256 \
    -key /etc/crts/${REGISTRY_HOSTNAME}.key \
    -subj "/O=Local Red Hat CodeReady Workspaces/CN=${REGISTRY_HOSTNAME}" \
    -reqexts SAN \
    -config <(cat /etc/pki/tls/openssl.cnf \
        <(printf "\n[SAN]\nsubjectAltName=DNS:${REGISTRY_HOSTNAME}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
    -out /etc/crts/${REGISTRY_HOSTNAME}.csr

# Generate domain crt
openssl x509 \
    -req \
    -sha256 \
    -extfile <(printf "subjectAltName=DNS:${REGISTRY_HOSTNAME}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth") \
    -days 36500 \
    -in /etc/crts/${REGISTRY_HOSTNAME}.csr \
    -CA /etc/crts/${REGISTRY_HOSTNAME}.ca.crt \
    -CAkey /etc/crts/${REGISTRY_HOSTNAME}.ca.key \
    -CAcreateserial -out /etc/crts/${REGISTRY_HOSTNAME}.crt
    
openssl x509 -in /etc/crts/${REGISTRY_HOSTNAME}.ca.crt -text

# Copy and trust the cert
cp /etc/crts/${REGISTRY_HOSTNAME}.ca.crt ${REGISTRY_HOSTNAME}.crt /etc/pki/ca-trust/source/anchors/
update-ca-trust extract
cp /etc/crts/${REGISTRY_HOSTNAME}.key ${REGISTRY_HOSTNAME}.crt /opt/registry/certs/
update-ca-trust

# Create username and password for offline mirror repository:
htpasswd -bBc /opt/registry/auth/htpasswd $REGISTRY_ID $REGISTRY_PW

# Running docker registry
podman run \
    --name mirror-registry \
    -p 5000:5000 \
    -e "REGISTRY_AUTH=htpasswd" \
    -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/${REGISTRY_HOSTNAME}.crt \
    -e REGISTRY_HTTP_TLS_KEY=/certs/${REGISTRY_HOSTNAME}.key \
    -e REGISTRY_STORAGE_DELETE_ENABLED=true \
    -v /opt/registry/data:/var/lib/registry:z \
    -v /opt/registry/auth:/auth:z \
    -v /opt/registry/certs:/certs:z \
    -d docker.io/library/registry:2

sudo sleep 60

# Automatically start docker registry:
cat << EOF > /etc/systemd/system/mirror-registry.service
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

systemctl enable mirror-registry.service --now

# check service

openshift-install version
oc version
oc mirror version
butane -V
cat /etc/httpd/conf/httpd.conf | grep Listen
cat /etc/selinux/config | grep SELINUX
sestatus
cat /etc/exports
cat /etc/resolv.conf
ls -ltr /var/named/{'$BASE_DOMAIN.zone','$REVERSED_IP_PART.zone'}
systemctl status firewalld |grep Active -B2
systemctl status httpd |grep Active -B2
systemctl status nfs-server |grep Active -B2
systemctl status named |grep Active -B2
systemctl status haproxy |grep Active -B2
systemctl status mirror-registry.service |grep Active -B2
podman ps |grep mirror-registry
podman login -u $REGISTRY_ID -p $REGISTRY_PW --authfile /root/pull-secret ${REGISTRY_HOSTNAME}:5000
