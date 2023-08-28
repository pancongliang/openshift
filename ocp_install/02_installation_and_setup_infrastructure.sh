
#!/bin/bash

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=45  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

######

# Task: Install infrastructure rpm
PRINT_TASK "[Install infrastructure rpm]"

# Install infrastructure rpm
packages=("wget" "net-tools" "podman" "bind-utils" "bind" "haproxy" "git" "bash-completion" "jq" "nfs-utils" "httpd" "httpd-tools" "skopeo" "httpd-manual")
yum install -y vim &>/dev/null
yum install -y "${packages[@]}" &>/dev/null

# Check if a package is installed
check_package_installed() {
    package_name=$1
    if rpm -q "$package_name" &>/dev/null; then
        echo "ok: ["install $package_name rpm"]"
    else
        echo "failed: ["install $package_name rpm"]"
    fi
}

# Check and display package installation status
all_packages_installed=true
for package in "${packages[@]}"; do
    check_package_installed "$package" || all_packages_installed=false
done

if $all_packages_installed; then

fi

# Add an empty line after the task
echo

######


# Task: Install openshift tool
PRINT_TASK "[Install openshift tool]"

# Delete openshift tool
files=(
    "/usr/local/bin/butane1"
    "/usr/local/bin/kubectl"
    "/usr/local/bin/oc"
    "/usr/local/bin/oc-mirror"
    "/usr/local/bin/openshift-install*"
    "/usr/local/bin/openshift-install-linux.tar.gz"
    "/usr/local/bin/openshift-client-linux.tar.gz"
    "/usr/local/bin/oc-mirror.tar.gz"
)

for file in "${files[@]}"; do
    rm -rf $file 2>/dev/null
done

# Define variables
DOWNLOAD_DIR="/usr/local/bin"

# Function to download and install .tar.gz tools
install_tar_gz() {
    local tool_name="$1"
    local tool_url="$2"
    
    wget -P "$DOWNLOAD_DIR" "$tool_url" &> /dev/null
    
    if [ $? -eq 0 ]; then
        echo "ok: ["download $tool_name tool"]"
        tar xvf "$DOWNLOAD_DIR/$(basename $tool_url)" &> /dev/null
        rm -f "$DOWNLOAD_DIR/$(basename $tool_url)"
    else
        echo "failed: ["download $tool_name tool"]"
    fi
}

# Function to download and install binary files
install_binary() {
    local tool_name="$1"
    local tool_url="$2"
    
    wget -P "$DOWNLOAD_DIR" "$tool_url" &> /dev/null
    
    if [ $? -eq 0 ]; then
        echo "ok: ["download $tool_name tool"]"
        chmod a+x "$DOWNLOAD_DIR/$(basename $tool_url)" &> /dev/null
    else
        echo "failed: ["download $tool_name tool"]"
    fi
}

# Install .tar.gz tools
install_tar_gz "openshift-install" "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_RELEASE}/openshift-install-linux.tar.gz"
install_tar_gz "openshift-client" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz"
install_tar_gz "oc-mirror" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz"

# Install binary files
install_binary "butane" "https://mirror.openshift.com/pub/openshift-v4/clients/butane/latest/butane"

# Define the list of commands to check
commands=("openshift-install" "oc" "kubectl" "oc-mirror" "butane")

# Iterate through the list of commands for checking
for cmd in "${commands[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "ok: ["install $cmd tool"]"
    else
        echo "failed: ["install $cmd tool"]"
    fi
done

# Add an empty line after the task
echo

######

# Task: Setup and check httpd services
PRINT_TASK "[Setup and check httpd services]"

# Update httpd listen port
update_httpd_listen_port() {
    listen_port=$(grep -v "#" /etc/httpd/conf/httpd.conf | grep -i 'Listen' | awk '{print $2}')
    if [ "$listen_port" != "8080" ]; then
        sed -i 's/^Listen .*/Listen 8080/' /etc/httpd/conf/httpd.conf
        systemctl restart httpd
        echo "ok: [Apache HTTP Server's listen port has been changed to 8080.]"
    fi
}

# Create virtual host configuration
create_virtual_host_config() {
    cat << EOF > /etc/httpd/conf.d/base.conf
<VirtualHost *:8080>
   ServerName ${BASTION_HOSTNAME}
   DocumentRoot ${HTTPD_PATH}
</VirtualHost>
EOF
}

# Check if virtual host configuration is valid
check_virtual_host_configuration() {
    expected_server_name="${BASTION_HOSTNAME}"
    expected_document_root="${HTTPD_PATH}"
    virtual_host_config="/etc/httpd/conf.d/base.conf"
    if grep -q "ServerName $expected_server_name" "$virtual_host_config" && \
       grep -q "DocumentRoot $expected_document_root" "$virtual_host_config"; then
        echo "ok: ["create virtual host configuration"]"
    else
        echo "failed: ["create virtual host configuration"]"
    fi
}

# Call the function to update listen port
update_httpd_listen_port

# Create virtual host configuration
create_virtual_host_config

# Check virtual host configuration
check_virtual_host_configuration

# Enable and start httpd service
systemctl enable httpd
systemctl start httpd
echo "in progress: Restarting httpd service....]"
sleep 10

# Check if a service is enabled and running
check_service() {
    service_name=$1

    if systemctl is-enabled "$service_name" &>/dev/null; then
        echo "ok: [$service_name service is enabled.]"
    else
        echo "failed: $service_name service is not enabled.]"
    fi

    if systemctl is-active "$service_name" &>/dev/null; then
        echo "ok: [$service_name service is running.]"
    else
        echo "failed: [$service_name service is not running.]"
    fi
}

# List of services to check
services=("httpd")

# Check status of all services
for service in "${services[@]}"; do
    check_service "$service"
done

# Add an empty line after the task
echo

######

# Task: Setup nfs services
PRINT_TASK "[Setup nfs services]"

# Create directories
rm -rf ${NFS_DIR}
mkdir -p ${NFS_DIR}/${IMAGE_REGISTRY_PV}
echo "ok: [Create nfs directories.]"

# Add nfsnobody user if not exists
if id "nfsnobody" &>/dev/null; then
    echo "warning: [nfsnobody user exists.]"
else
    useradd nfsnobody
    echo "ok: [nfsnobody user added.]"
fi

# Change ownership and permissions
chown -R nfsnobody.nfsnobody ${NFS_DIR}
chmod -R 777 ${NFS_DIR}
echo "Changed: [Changed ownership and permissions.]"

# Add NFS export configuration
export_config_line="${NFS_DIR}    (rw,sync,no_wdelay,no_root_squash,insecure,fsid=0)"
if grep -q "$export_config_line" "/etc/exports"; then
    echo "warning: [NFS export configuration already exists.]"
else
    echo "$export_config_line" >> "/etc/exports"
    echo "ok: [NFS export configuration added.]"
fi

# Enable and start nfs-server service
systemctl enable nfs-server
systemctl restart nfs-server
echo "In progress: Restarting nfs-server service....]"
sleep 10

# Check if a service is enabled and running
check_service() {
    service_name=$1

    if systemctl is-enabled "$service_name" &>/dev/null; then
        echo "ok: [$service_name service is enabled.]"
    else
        echo "failed: [$service_name service is not enabled.]"
    fi

    if systemctl is-active "$service_name" &>/dev/null; then
        echo "ok: [$service_name service is running.]"
    else
        echo "faild: [$service_name service is not running.]"
    fi
}

# List of services to check
services=("nfs-server")

# Check status of all services
for service in "${services[@]}"; do
    check_service "$service"
done

# Add an empty line after the task
echo
######


# Task: Setup named services
PRINT_TASK "[Setup named services]"

# Setup named services configuration
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
        forwarders      { ${DNS_FORWARDER_IP}; };

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

zone "${BASE_DOMAIN}" IN {
        type master;
        file "${BASE_DOMAIN}.zone";
        allow-query { any; };
};

zone "${REVERSE_ZONE}" IN {
        type master;
        file "${REVERSE_ZONE_FILE_NAME}";
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

# Create forward zone file
cat << EOF >  /var/named/${BASE_DOMAIN}.zone
\$TTL 1W
@       IN      SOA     ns1.${BASE_DOMAIN}.        root (
                        201907070      ; serial
                        3H              ; refresh (3 hours)
                        30M             ; retry (30 minutes)
                        2W              ; expiry (2 weeks)
                        1W )            ; minimum (1 week)
        IN      NS      ns1.${BASE_DOMAIN}.
;
;
ns1     IN      A       ${BASTION_IP}
;
helper  IN      A       ${BASTION_IP}
helper.ocp4     IN      A       ${BASTION_IP}
;
; The api identifies the IP of your load balancer.
api.${CLUSTER_NAME}.${BASE_DOMAIN}.                            IN      A       ${API_IP}
api-int.${CLUSTER_NAME}.${BASE_DOMAIN}.                        IN      A       ${API_INT_IP}
;
; The wildcard also identifies the load balancer.
*.apps.${CLUSTER_NAME}.${BASE_DOMAIN}.                         IN      A       ${APPS_IP}
;
; Create entries for the master hosts.
${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.           IN      A       ${MASTER01_IP}
${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.           IN      A       ${MASTER02_IP}
${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.           IN      A       ${MASTER03_IP}
;
; Create entries for the worker hosts.
${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.           IN      A       ${WORKER01_IP}
${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.           IN      A       ${WORKER02_IP}
;
; Create an entry for the bootstrap host.
${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.          IN      A       ${BOOTSTRAP_IP}
;
; Create entries for the mirror registry hosts.
${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.                           IN      A       ${REGISTRY_IP}
EOF

# Create reverse zone file
cat << EOF >  /var/named/${REVERSE_ZONE_FILE_NAME}
\$TTL 1W
@       IN      SOA     ns1.${BASE_DOMAIN}.        root (
                        2019070700      ; serial
                        3H              ; refresh (3 hours)
                        30M             ; retry (30 minutes)
                        2W              ; expiry (2 weeks)
                        1W )            ; minimum (1 week)
        IN      NS      ns1.${BASE_DOMAIN}.
;
; The syntax is "last octet" and the host must have an FQDN
; with a trailing dot.
;
; The api identifies the IP of your load balancer.
${API_REVERSE_IP}                IN      PTR     api.${CLUSTER_NAME}.${BASE_DOMAIN}.
${API_INT_REVERSE_IP}            IN      PTR     api-int.${CLUSTER_NAME}.${BASE_DOMAIN}.
;
; Create entries for the master hosts.
${MASTER01_REVERSE_IP}           IN      PTR     ${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
${MASTER02_REVERSE_IP}           IN      PTR     ${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
${MASTER03_REVERSE_IP}           IN      PTR     ${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
;
; Create entries for the worker hosts.
${WORKER01_REVERSE_IP}           IN      PTR     ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
${WORKER02_REVERSE_IP}           IN      PTR     ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
${WORKER02_REVERSE_IP}           IN      PTR     ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
;
; Create an entry for the bootstrap host.
${BOOTSTRAP_REVERSE_IP}          IN      PTR     ${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
EOF

# Change ownership
chown named. /var/named/*.zone
echo "ok: [Change ownership /var/named/*.zone."

# Check named configuration file
if named-checkconf &>/dev/null; then
    echo "ok: [Setup named service configuration, named configuration is valid."
else
    echo "failed: [Setup named service configuration, Named configuration is invalid.]"
fi

# Check forward zone file
if named-checkzone ${BASE_DOMAIN} /var/named/${BASE_DOMAIN}.zone &>/dev/null; then
    echo "ok: [Add DNS forwarder IP.]"
    echo "ok: [Create forward zone file, forward zone file is valid.]"
else
    echo "failed: [Create forward zone file, Forward zone file is invalid.]"
fi

# Check reverse zone file
if named-checkzone ${REVERSE_ZONE_FILE_NAME} /var/named/${REVERSE_ZONE_FILE_NAME} &>/dev/null; then
    echo "ok: [Create reverse zone file，reverse zone file is valid.]"
else
    echo "failed: [Create reverse zone file，reverse zone file is invalid.]"
fi

# Check if the same DNS IP exists in resolv.conf, if not, add it.
if ! grep -q "nameserver ${DNS_SERVER}" /etc/resolv.conf; then
    # Add the DNS server configuration
    echo "nameserver ${DNS_SERVER}" >> /etc/resolv.conf
    echo "ok: [Add DNS IP to /etc/resolv.conf.]"
else
    echo "warning: [DNS IP already exists in /etc/resolv.conf.]"
fi

# Enable and start named service
systemctl enable named
systemctl restart named
echo "In progress: Restarting named service....]"
sleep 10


# Check if a service is enabled and running
check_service() {
    service_name=$1

    if systemctl is-enabled "$service_name" &>/dev/null; then
        echo "ok: [$service_name service is enabled.]"
    else
        echo "failed: [$service_name service is not enabled.]"
    fi

    if systemctl is-active "$service_name" &>/dev/null; then
        echo "ok: [$service_name service is running.]"
    else
        echo "failed: $service_name service is not running."
    fi
}

# List of services to check
services=("named")

# Check status of all services
for service in "${services[@]}"; do
    check_service "$service"
done

# List of hostnames and IP addresses to check
hostnames=(
    "api.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "api-int.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}"
    "${BASTION_IP}"
    "${MASTER01_IP}"
    "${MASTER02_IP}"
    "${MASTER03_IP}"
    "${WORKER01_IP}"
    "${WORKER02_IP}"
    "${BOOTSTRAP_IP}"
    "www.baidu.com"
)

# Loop through hostnames and perform nslookup
all_successful=true
failed_hostnames=()

for hostname in "${hostnames[@]}"; do
    nslookup_result=$(nslookup "$hostname" 2>&1)
    if [ $? -ne 0 ]; then
        all_successful=false
        failed_hostnames+=("$hostname")
    fi
done

# Display results
if [ "$all_successful" = true ]; then
    echo "ok: [Resolve all Domain/IP addresses.]"
else
    echo "failed: [DNS resolution failed for the following hostnames:]"
    for failed_hostname in "${failed_hostnames[@]}"; do
        echo "$failed_hostname"
    done
fi

# Add an empty line after the task
echo

######


# Task: Setup HAproxy services
PRINT_TASK "[Setup HAproxy services]"

# Setup haproxy services configuration
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
  bind ${BASTION_IP}:6443
  mode tcp
  server     ${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${BOOTSTRAP_IP}:6443 check inter 1s backup
  server     ${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER01_IP}:6443 check inter 1s
  server     ${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER02_IP}:6443 check inter 1s
  server     ${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER03_IP}:6443 check inter 1s

listen machine-config-server-22623 
  bind ${BASTION_IP}:22623
  mode tcp
  server     ${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${BOOTSTRAP_IP}:22623 check inter 1s backup
  server     ${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER01_IP}:22623 check inter 1s
  server     ${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER02_IP}:22623 check inter 1s
  server     ${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER03_IP}:22623 check inter 1s

listen default-ingress-router-80
  bind ${BASTION_IP}:80
  mode tcp
  balance source
  server     ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:80 check inter 1s
  server     ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:80 check inter 1s

listen default-ingress-router-443
  bind ${BASTION_IP}:443
  mode tcp
  balance source
  server     ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:443 check inter 1s
  server     ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:443 check inter 1s
EOF

# Path to HAProxy configuration file
CONFIG_FILE="/etc/haproxy/haproxy.cfg"

# Check HAProxy configuration syntax
check_haproxy_config() {
    haproxy -c -f "$CONFIG_FILE"
    if [ $? -eq 0 ]; then
        echo "ok: [Setup Haproxy service configuration, HAProxy configuration is valid.]"
    else
        echo "failed: [Setup Haproxy service configuration,HAProxy configuration is invalid.]"
    fi
}

# Call the function to check HAProxy configuration
check_haproxy_config

# Enable and start HAProxy service
systemctl enable haproxy
systemctl start haproxy
echo "In progress: Restarting haproxy service....]"
sleep 5

# Check if a service is enabled and running
check_service() {
    service_name=$1

    if systemctl is-enabled "$service_name" &>/dev/null; then
        echo "ok: [$service_name service is enabled.]"
    else
        echo "failed: [$service_name service is not enabled.]"
    fi

    if systemctl is-active "$service_name" &>/dev/null; then
        echo "ok: [$service_name service is running.]"
    else
        echo "failed: [$service_name service is not running.]"
    fi
}

# List of services to check
services=("haproxy")

# Check status of all services
for service in "${services[@]}"; do
    check_service "$service"
done
