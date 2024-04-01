#!/bin/bash

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}
# ====================================================



# === Task: Install infrastructure rpm ===
PRINT_TASK "[TASK: Install infrastructure rpm]"

# List of RPM packages to install
packages=("wget" "net-tools" "vim" "podman" "bind-utils" "bind" "haproxy" "git" "bash-completion" "jq" "nfs-utils" "httpd" "httpd-tools" "skopeo" "conmon" "httpd-manual")

# Install the RPM package and return the execution result
for package in "${packages[@]}"; do
    yum install -y "$package" &>/dev/null
    if [ $? -eq 0 ]; then
        echo "ok: [install $package package]"
    else
        echo "failed: [install $package package]"
    fi
done

# Add an empty line after the task
echo
# ====================================================



# === Task: Install openshift tool ===
PRINT_TASK "[TASK: Install openshift tool]"

# Step 1: Delete openshift tool
# ----------------------------------------------------
# Delete openshift tool
files=(
    "/usr/local/bin/butane"
    "/usr/local/bin/kubectl"
    "/usr/local/bin/oc"
    "/usr/local/bin/oc-mirror"
    "/usr/local/bin/openshift-install"
    "/usr/local/bin/openshift-install-linux.tar.gz"
    "/usr/local/bin/openshift-client-linux.tar.gz"
    "/usr/local/bin/oc-mirror.tar.gz"
)
for file in "${files[@]}"; do
    rm -rf $file 2>/dev/null
done


# Step 2: Function to download and install tool
# ----------------------------------------------------
# Function to download and install .tar.gz tools
install_tar_gz() {
    local tool_name="$1"
    local tool_url="$2"  
    # Download the tool
    wget -P "/usr/local/bin" "$tool_url" &> /dev/null    
    if [ $? -eq 0 ]; then
        echo "ok: [download $tool_name tool]"        
        # Extract the downloaded tool
        tar xvf "/usr/local/bin/$(basename $tool_url)" -C "/usr/local/bin/" &> /dev/null
        # Remove the downloaded .tar.gz file
        rm -f "/usr/local/bin/$(basename $tool_url)"
    else
        echo "failed: [download $tool_name tool]"
    fi
}

# Install .tar.gz tools
install_tar_gz "openshift-install" "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_RELEASE_VERSION}/openshift-install-linux.tar.gz"
install_tar_gz "openshift-client" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz"
install_tar_gz "oc-mirror" "https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz"

# Function to check command success and display appropriate message
run_command() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}


# Function to download and install binary files
install_binary() {
    local tool_name="$1"
    local tool_url="$2"    
    # Download the binary tool
    wget -P "/usr/local/bin" "$tool_url" &> /dev/null    
    if [ $? -eq 0 ]; then
        echo "ok: [download $tool_name tool]"        
    else
        echo "failed: [download $tool_name tool]"
    fi
}

# Install binary files
install_binary "butane" "https://mirror.openshift.com/pub/openshift-v4/clients/butane/latest/butane"

# Modify /usr/local/bin/oc-mirror and butane toolpermissions
run_command() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}
chmod a+x /usr/local/bin/oc-mirror &> /dev/null
run_command "[modify /usr/local/bin/oc-mirror permissions]"

chmod a+x /usr/local/bin/butane &> /dev/null
run_command "[modify /usr/local/bin/butane permissions]"

# Step 3: Checking
# ----------------------------------------------------
# Define the list of commands to check
commands=("openshift-install" "oc" "kubectl" "oc-mirror" "butane")

# Iterate through the list of commands for checking
for cmd in "${commands[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
        echo "ok: [install $cmd tool]"
    else
        echo "failed: [install $cmd tool]"
    fi
done

# Add an empty line after the task
echo


# Write LANG=en_US.UTF-8 to the ./bash_profile file]
echo 'export LANG=en_US.UTF-8' >> ~/.bash_profile
run_command "[Write LANG=en_US.UTF-8 to the ./bash_profile file]"

# Reload ~/.bash_profile
source ~/.bash_profile
run_command "[Reload ~/.bash_profile]"

# Change time zone to UTC
timedatectl set-timezone UTC
run_command "[Change time zone to UTC]"

# Change hostname
hostnamectl set-hostname ${BASTION_HOSTNAME}
run_command "[Change hostname to ${BASTION_HOSTNAME}]"
# Add an empty line after the task
echo


# === Task: Setup and check httpd services ===
PRINT_TASK "[TASK: Setup and check httpd services]"
# Step 1: Update httpd listen port
# ----------------------------------------------------
# Update httpd listen port
update_httpd_listen_port() {
    # Get the current listen port from httpd.conf
    listen_port=$(grep -v "#" /etc/httpd/conf/httpd.conf | grep -i 'Listen' | awk '{print $2}')
    
    # Check if listen port is not 8080
    if [ "$listen_port" != "8080" ]; then
        # Change listen port to 8080
        sed -i 's/^Listen .*/Listen 8080/' /etc/httpd/conf/httpd.conf
        echo "ok: [change http listening port to 8080]"
    else
        echo "skipping: [http listen port is already 8080]"
    fi
}

# Call the function to update listen port
update_httpd_listen_port


# Step 2: Create virtual host configuration and http dir
# ----------------------------------------------------
# Create virtual host configuration
create_virtual_host_config() {
    # Create a virtual host configuration file
    cat << EOF > /etc/httpd/conf.d/base.conf
<VirtualHost *:8080>
   ServerName ${BASTION_HOSTNAME}
   DocumentRoot ${HTTPD_PATH}
</VirtualHost>
EOF
}

# Create virtual host configuration
create_virtual_host_config

# Check if virtual host configuration is valid
check_virtual_host_configuration() {
    # Define expected values for server name and document root
    expected_server_name="${BASTION_HOSTNAME}"
    expected_document_root="${HTTPD_PATH}"
    
    # Path to virtual host configuration file
    virtual_host_config="/etc/httpd/conf.d/base.conf"
    
    # Check if expected values are present in the config
    if grep -q "ServerName $expected_server_name" "$virtual_host_config" && \
       grep -q "DocumentRoot $expected_document_root" "$virtual_host_config"; then
        echo "ok: [create virtual host configuration]"
    else
        echo "failed: [create virtual host configuration]"
    fi
}

# Check virtual host configuration
check_virtual_host_configuration

# Create http dir
mkdir -p ${HTTPD_PATH}
if [ $? -eq 0 ]; then
    echo "ok: [create http: ${HTTPD_PATH} director]"
else
    echo "failed: [create http: ${HTTPD_PATH} director]"
fi


# Step 3: Enable and Restart httpd service
# ----------------------------------------------------
# List of services to handle
services=("httpd")

# Loop through each service in the list
for service in "${services[@]}"; do
    # Restart the service
    systemctl restart "$service" &>/dev/null
    restart_status=$?

    # Enable the service
    systemctl enable "$service" &>/dev/null
    enable_status=$?

    if [ $restart_status -eq 0 ] && [ $enable_status -eq 0 ]; then
        echo "ok: [restart and enable $service service]"
    else
        echo "failed: [restart and enable $service service]"
    fi
done

# Wait for the service to restart
sleep 10


# Step 4: Test
# ----------------------------------------------------
# Function to execute a command and check its status
run_command() {
    $1
    if [ $? -eq 0 ]; then
        echo "ok: [$2]"
        return 0
    else
        echo "failed: [$2]"
        return 1
    fi
}

# Test httpd configuration
run_command "touch ${HTTPD_PATH}/httpd-test" "create httpd test file"
run_command "wget -q http://${BASTION_IP}:8080/httpd-test" "test httpd download function"
run_command "rm -rf httpd-test ${HTTPD_PATH}/httpd-test" "delete the httpd test file"

# Add an empty line after the task
echo
# ====================================================



# === Task: Setup nfs services ===
PRINT_TASK "[TASK: Setup nfs services]"

# Step 1: Create directory /user and change permissions and add NFS export
# ----------------------------------------------------
# Create NFS directories
rm -rf ${NFS_PATH}
mkdir -p ${NFS_PATH}/${IMAGE_REGISTRY_PV}
if [ $? -eq 0 ]; then
    echo "ok: [create nfs director: ${NFS_PATH}]"
else
    echo "failed: [create nfs director: ${NFS_PATH}]"
fi

# Add nfsnobody user if not exists
if id "nfsnobody" &>/dev/null; then
    echo "skipping: [nfsnobody user exists]"
else
    useradd nfsnobody
    echo "ok: [add nfsnobody user]"
fi

# Change ownership and permissions
chown -R nfsnobody.nfsnobody ${NFS_PATH}
if [ $? -eq 0 ]; then
    echo "ok: [changing ownership of an NFS directory]"
else
    echo "failed: [changing ownership of an NFS directory]"
fi

chmod -R 777 ${NFS_PATH}
if [ $? -eq 0 ]; then
    echo "ok: [change NFS directory permissions]"
else
    echo "failed: [change NFS directory permissions]"
fi

# Add NFS export configuration
export_config_line="${NFS_PATH}    (rw,sync,no_wdelay,no_root_squash,insecure,fsid=0)"
if grep -q "$export_config_line" "/etc/exports"; then
    echo "skipping: [nfs export configuration already exists]"
else
    echo "$export_config_line" >> "/etc/exports"
    echo "ok: [add nfs export configuration]"
fi


# Step 2: Enable and Restart nfs-server service
# ----------------------------------------------------
# List of services to handle
services=("nfs-server")

# Loop through each service in the list
for service in "${services[@]}"; do
    # Restart the service
    systemctl restart "$service" &>/dev/null
    restart_status=$?

    # Enable the service
    systemctl enable "$service" &>/dev/null
    enable_status=$?

    if [ $restart_status -eq 0 ] && [ $enable_status -eq 0 ]; then
        echo "ok: [restart and enable $service service]"
    else
        echo "failed: [restart and enable $service service]"
    fi
done

# Wait for the service to restart
sleep 10


# Step 3: Test
# ----------------------------------------------------
# Function to check if NFS share is accessible
check_nfs_access() {
    mount_point="/mnt/nfs_test"
    
    # Create the mount point if it doesn't exist
    mkdir -p $mount_point
    
    # Attempt to mount the NFS share
    mount -t nfs ${NFS_SERVER_IP}:${NFS_PATH} $mount_point

    if [ $? -eq 0 ]; then
        echo "ok: [test mounts the nfs shared directory]"
        # Unmount the NFS share
        umount $mount_point
        rmdir $mount_point
        return 0
    else
        echo "failed: [test mount nfs shared directory]"
        rmdir $mount_point
        return 1
    fi
}

# Call the function to check NFS access
check_nfs_access

# Add an empty line after the task
echo
# ====================================================



# === Task: Setup named services ===
PRINT_TASK "[TASK: Setup named services]"
# Step 1: Generate DNS zone name/zone file name
# ----------------------------------------------------
# Generate reverse DNS zone name and reverse zone file name
# Construct forward DNS zone name and zone file name
FORWARD_ZONE_NAME="${BASE_DOMAIN}"
FORWARD_ZONE_FILE="${BASE_DOMAIN}.zone"

# Check if the forward DNS zone name and zone file name are generated successfully
if [ -n "$FORWARD_ZONE_NAME" ] && [ -n "$FORWARD_ZONE_FILE" ]; then
    echo "ok: [generate forward DNS zone name $FORWARD_ZONE_NAME]"
    echo "ok: [generate forward zone file name $FORWARD_ZONE_FILE]"
else
    echo "failed: [generate forward DNS zone name or forward zone file name]"
fi

# Generate reverse DNS zone name and reverse zone file name 
# Extract the last two octets from the IP address
IFS='.' read -ra octets <<< "$DNS_SERVER_IP"
OCTET0="${octets[0]}"
OCTET1="${octets[1]}"

# Construct reverse DNS zone name and zone file name
REVERSE_ZONE_NAME="${OCTET1}.${OCTET0}.in-addr.arpa"
REVERSE_ZONE_FILE="${OCTET1}.${OCTET0}.zone"

# Check if the reverse DNS zone name and zone file name are generated successfully
if [ -n "$REVERSE_ZONE_NAME" ] && [ -n "$REVERSE_ZONE_FILE" ]; then
    echo "ok: [generate reverse DNS zone name $REVERSE_ZONE_NAME]"
    echo "ok: [generate reverse zone file name $REVERSE_ZONE_FILE]"
else
    echo "failed: [generate reverse DNS zone name or reverse zone file name]"
fi


# Step 2: Generate named service configuration file
# ----------------------------------------------------
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

    recursion yes;
    dnssec-enable yes;
    dnssec-validation yes;
    managed-keys-directory "/var/named/dynamic";
    pid-file "/run/named/named.pid";
    session-keyfile "/run/named/session.key";
};

zone "${FORWARD_ZONE_NAME}" IN {
    type master;
    file "${FORWARD_ZONE_FILE}";
    allow-query { any; };
};

zone "${REVERSE_ZONE_NAME}" IN {
    type master;
    file "${REVERSE_ZONE_FILE}";
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
EOF

# Check if the named configuration file was generated successfully
if [ -f "/etc/named.conf" ]; then
    echo "ok: [generate named configuration file]"
else
    echo "failed: [generate named configuration file]"
fi


# Step 3: Generate forward zone file
# ----------------------------------------------------
# Clean up: Delete duplicate file
rm -f /var/named/${FORWARD_ZONE_FILE}

# Create forward zone file
# Function to format and align DNS entries
format_dns_entry() {
    domain="$1"
    ip="$2"
    printf "%-40s IN  A      %s\n" "$domain" "$ip"
}

cat << EOF > "/var/named/${FORWARD_ZONE_FILE}"
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
ns1     IN      A       ${DNS_SERVER_IP}
;
helper  IN      A       ${DNS_SERVER_IP}
helper.ocp4     IN      A       ${DNS_SERVER_IP}
;
; The api identifies the IP of load balancer.
$(format_dns_entry "api.${CLUSTER_NAME}.${BASE_DOMAIN}." "${API_IP}")
$(format_dns_entry "api-int.${CLUSTER_NAME}.${BASE_DOMAIN}." "${API_INT_IP}")
;
; The wildcard also identifies the load balancer.
$(format_dns_entry "*.apps.${CLUSTER_NAME}.${BASE_DOMAIN}." "${APPS_IP}")
;
; Create entries for the master hosts.
$(format_dns_entry "${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${MASTER01_IP}")
$(format_dns_entry "${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${MASTER02_IP}")
$(format_dns_entry "${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${MASTER03_IP}")
;
; Create entries for the worker hosts.
$(format_dns_entry "${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${WORKER01_IP}")
$(format_dns_entry "${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${WORKER02_IP}")
;
; Create an entry for the bootstrap host.
$(format_dns_entry "${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}." "${BOOTSTRAP_IP}")
;
; Create entries for the mirror registry hosts.
$(format_dns_entry "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}." "${REGISTRY_IP}")
EOF

# Verify if the output file was generated successfully
if [ -f "/var/named/${FORWARD_ZONE_FILE}" ]; then
    echo "ok: [generate forward DNS zone file: /var/named/${FORWARD_ZONE_FILE}"
else
    echo "failed: [generate forward DNS zone file]"
fi


# Step 4: Create reverse zone file
# ----------------------------------------------------
#!/bin/bash
# Clean up: Delete duplicate file
rm -f /var/named/${REVERSE_ZONE_FILE}

# Input file containing the original reverse DNS zone configuration
reverse_zone_input_file="/var/named/reverse_zone_input_file"

# Output file for the formatted reverse DNS zone configuration
reverse_zone_output_file="/var/named/${REVERSE_ZONE_FILE}"

# Create the input file with initial content
cat << EOF > "$reverse_zone_input_file"
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
; The api identifies the IP of load balancer.
${API_IP}                IN      PTR     api.${CLUSTER_NAME}.${BASE_DOMAIN}.
${API_INT_IP}            IN      PTR     api-int.${CLUSTER_NAME}.${BASE_DOMAIN}.
;
; Create entries for the master hosts.
${MASTER01_IP}           IN      PTR     ${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
${MASTER02_IP}           IN      PTR     ${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
${MASTER03_IP}           IN      PTR     ${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
;
; Create entries for the worker hosts.
${WORKER01_IP}           IN      PTR     ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
${WORKER02_IP}           IN      PTR     ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
;
; Create an entry for the bootstrap host.
${BOOTSTRAP_IP}          IN      PTR     ${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN}.
EOF

# Function to generate IP address conversion to reverse format
convert_to_reverse_ip() {
    local ip="$1"
    IFS='.' read -ra octets <<< "$ip"
    reverse_ip="${octets[3]}.${octets[2]}"
    echo "$reverse_ip"
}

# Clear output file
> "$reverse_zone_output_file" 

# Use the function "convert_to_reverse_ip" to convert IP addresses, and format the output
while IFS= read -r line; do
    if [[ $line == *PTR* ]]; then
        # Extract IP and PTR from the line
        ip=$(echo "$line" | awk '{print $1}')
        ptr=$(echo "$line" | awk '{print $4}')

        # Convert IP to reverse format
        reversed_ip=$(convert_to_reverse_ip "$ip")

        # Format the output with appropriate spacing
        formatted_line=$(printf "%-19s IN  PTR      %-40s\n" "$reversed_ip" "$ptr")
        echo "$formatted_line" >> "$reverse_zone_output_file"
    else
        # If not a PTR line, keep the line unchanged
        echo "$line" >> "$reverse_zone_output_file"
    fi
done < "$reverse_zone_input_file"

# Clean up: Delete input file
rm -f "$reverse_zone_input_file"

# Verify if the reverse DNS zone file was generated successfully
if [ -f "$reverse_zone_output_file" ]; then
    echo "ok: [generate reverse DNS zone file: $reverse_zone_output_file]"
else
    echo "failed: [generate reverse DNS zone file]"
fi


# Step 5: Check named configuration/Dns file 
# ----------------------------------------------------
# Check named configuration file
if named-checkconf &>/dev/null; then
    echo "ok: [named configuration is valid]"
else
    echo "failed: [Named configuration is invalid]"
fi

# Check forward zone file
if named-checkzone ${FORWARD_ZONE_FILE} /var/named/${FORWARD_ZONE_FILE} &>/dev/null; then
    echo "ok: [forward zone file is valid]"
else
    echo "failed: [forward zone file is invalid]"
fi

# Check reverse zone file
if named-checkzone ${REVERSE_ZONE_FILE} /var/named/${REVERSE_ZONE_FILE} &>/dev/null; then
    echo "ok: [reverse zone file is valid]"
else
    echo "failed: [reverse zone file is invalid]"
fi


# Step 6: Add dns ip to resolv.conf and change zone permissions
# ----------------------------------------------------
# Add dns ip to resolv.conf
sed -i "/${DNS_SERVER_IP}/d" /etc/resolv.conf
sed -i "1s/^/nameserver ${DNS_SERVER_IP}\n/" /etc/resolv.conf
if [ $? -eq 0 ]; then
    echo "ok: [add DNS_SERVER_IP to /etc/resolv.conf"
else
    echo "failed: [add DNS_SERVER_IP to /etc/resolv.conf]"
fi

# Change ownership
chown named. /var/named/*.zone
if [ $? -eq 0 ]; then
    echo "ok: [change ownership /var/named/*.zone]"
else
    echo "failed: [change ownership /var/named/*.zone]"
fi


# Step 7: Enable and Restart named service
# ----------------------------------------------------
# List of services to handle
services=("named")

# Loop through each service in the list
for service in "${services[@]}"; do
    # Restart the service
    systemctl restart "$service" &>/dev/null
    restart_status=$?

    # Enable the service
    systemctl enable "$service" &>/dev/null
    enable_status=$?

    if [ $restart_status -eq 0 ] && [ $enable_status -eq 0 ]; then
        echo "ok: [restart and enable $service service]"
    else
        echo "failed: [restart and enable $service service]"
    fi
done

# Wait for the service to restart
sleep 10


# Step 8: Test nslookup
# ----------------------------------------------------
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
    "${NSLOOKUP_PUBLIC}"
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
    echo "ok: [nslookup all domain names/IP addresses]"
else
    echo "failed: [dns resolve failed for the following domain/IP:]"
    for failed_hostname in "${failed_hostnames[@]}"; do
        echo "$failed_hostname"
    done
fi

# Add an empty line after the task
echo
# ====================================================



# === Task: Setup HAproxy services ===
PRINT_TASK "[TASK: Setup HAproxy services]"
# Step 1: Generate haproxy service configuration file
# ----------------------------------------------------
# Specify the path and filename for the haproxy configuration file
haproxy_config_file="/etc/haproxy/haproxy.cfg"

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
  bind ${LB_IP}:6443
  mode tcp
  server     ${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${BOOTSTRAP_IP}:6443 check inter 1s backup
  server     ${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER01_IP}:6443 check inter 1s
  server     ${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER02_IP}:6443 check inter 1s
  server     ${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER03_IP}:6443 check inter 1s

listen machine-config-server-22623 
  bind ${LB_IP}:22623
  mode tcp
  server     ${BOOTSTRAP_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${BOOTSTRAP_IP}:22623 check inter 1s backup
  server     ${MASTER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER01_IP}:22623 check inter 1s
  server     ${MASTER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER02_IP}:22623 check inter 1s
  server     ${MASTER03_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${MASTER03_IP}:22623 check inter 1s

listen default-ingress-router-80
  bind ${LB_IP}:80
  mode tcp
  balance source
  server     ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:80 check inter 1s
  server     ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:80 check inter 1s

listen default-ingress-router-443
  bind ${LB_IP}:443
  mode tcp
  balance source
  server     ${WORKER01_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER01_IP}:443 check inter 1s
  server     ${WORKER02_HOSTNAME}.${CLUSTER_NAME}.${BASE_DOMAIN} ${WORKER02_IP}:443 check inter 1s
EOF

# Verify if the haproxy configuration file was generated successfully
if [ -f "$haproxy_config_file" ]; then
    echo "ok: [generate haproxy configuration file"
else
    echo "failed: [generate haproxy configuration file"
fi


# Step 2: Check haproxy configuration
# ----------------------------------------------------
# Path to HAProxy configuration file
CONFIG_FILE="/etc/haproxy/haproxy.cfg"

# Check HAProxy configuration syntax
check_haproxy_config() {
    haproxy -c -f "$CONFIG_FILE" &>/dev/null
    if [ $? -eq 0 ]; then
        echo "ok: [haproxy configuration is valid]"
    else
        echo "failed: [haproxy configuration is invalid]"
    fi
}

# Call the function to check HAProxy configuration
check_haproxy_config


# Step 3: Enable and Restart haproxy service
# ----------------------------------------------------
# List of services to handle
services=("haproxy")

# Loop through each service in the list
for service in "${services[@]}"; do
    # Restart the service
    systemctl restart "$service" &>/dev/null
    restart_status=$?

    # Enable the service
    systemctl enable "$service" &>/dev/null
    enable_status=$?

    if [ $restart_status -eq 0 ] && [ $enable_status -eq 0 ]; then
        echo "ok: [restart and enable $service service]"
    else
        echo "failed: [restart and enable $service service]"
    fi
done

# Add an empty line after the task
echo
# ====================================================
