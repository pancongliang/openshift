#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export QUAY_DOMAIN='quay-server.example.com'
export QUAY_HOST_IP="10.184.134.128"
export REGISTRY_REDHAT_IO_ID="rhn-support-xxx"
export REGISTRY_REDHAT_IO_PW="xxxx"

export QUAY_SUPER_USERS="quayadmin"
export QUAY_INST_DIR="/opt/quay-inst"

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

# Function to check command success and display appropriate message
run_command() {
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
        exit 1
    fi
}

# Step 1: 
PRINT_TASK "TASK [Install infrastructure rpm]"

# List of RPM packages to install
packages=("podman")

# Convert the array to a space-separated string
package_list="${packages[*]}"

# Install all packages at once
sudo dnf install -y $package_list >/dev/null 2>&1

# Check if each package was installed successfully
for package in "${packages[@]}"; do
    rpm -q $package >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "ok: [Installed $package package]"
    else
        echo "failed: [Installed $package package]"
    fi
done

# Add an empty line after the task
echo


# Step 2:
PRINT_TASK "TASK [Delete existing duplicate data]"

# Function to remove a container with formatted output
remove_container() {
    local container_name="$1"
    if sudo podman container exists "$container_name"; then
        if sudo podman rm -f "$container_name" >/dev/null 2>&1; then
            echo "ok: [Container $container_name removed]"
        else
            echo "failed: [Container $container_name removed]"
        fi
    else
        echo "skipping: [Container $container_name removed]"
    fi
}

# Function to remove a directory with formatted output
remove_directory() {
    local dir_path="$1"
    if [ -d "$dir_path" ]; then
        if sudo rm -rf "$dir_path" >/dev/null 2>&1; then
            echo "ok: [Quay install directory $dir_path removed]"
        else
            echo "failed: [Quay install directory $dir_path removed]"
        fi
    else
        echo "skipping: [Quay install directory $dir_path removed]"
    fi
}

# Begin cleanup
remove_container "postgresql-quay"
remove_container "quay"
remove_container "redis"
remove_directory "$QUAY_INST_DIR"

# Add an empty line after the task
echo

# Step 3: 
# Task: Generate a self-signed certificate
PRINT_TASK "[TASK: Generate a self-signed certificate]"

# Create a local directory to store the Quay config.yaml and certificates
rm -rf ${QUAY_INST_DIR} > /dev/null 2>&1
mkdir -p $QUAY_INST_DIR/config >/dev/null 2>&1
run_command "[Create a local directory to store the Quay config.yaml and certificates]"

# Generate the root Certificate Authority (CA) key
openssl genrsa -out "${QUAY_INST_DIR}/config/rootCA.key" 2048 >/dev/null 2>&1
run_command "[Generate root CA private key]"

# Generate the root CA certificate
openssl req -x509 -new -nodes \
  -key "${QUAY_INST_DIR}/config/rootCA.key" \
  -sha256 -days 36500 \
  -out "${QUAY_INST_DIR}/config/rootCA.pem" \
  -subj "/C=IE/ST=GALWAY/L=GALWAY/O=QUAY/OU=DOCS/CN=${QUAY_DOMAIN}" >/dev/null 2>&1
run_command "[Generate root CA certificate]"

# Generate the domain key
openssl genrsa -out "${QUAY_INST_DIR}/config/ssl.key" 2048 >/dev/null 2>&1
run_command "[Generate private key for domain]"

# Generate a certificate signing request (CSR) for the domain
openssl req -new \
  -key "${QUAY_INST_DIR}/config/ssl.key" \
  -out "${QUAY_INST_DIR}/config/ssl.csr" \
  -subj "/C=IE/ST=GALWAY/L=GALWAY/O=QUAY/OU=DOCS/CN=${QUAY_DOMAIN}" >/dev/null 2>&1
run_command "[Generate domain certificate signing request]"

# Create an OpenSSL configuration file with Subject Alternative Names (SANs)
cat > "${QUAY_INST_DIR}/config/openssl.cnf" <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[v3_req]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${QUAY_DOMAIN}
IP.1 = ${QUAY_HOST_IP}
EOF
run_command "[Create an OpenSSL configuration file with Subject Alternative Names]"

# Generate the domain certificate (CRT)
openssl x509 -req \
  -in "${QUAY_INST_DIR}/config/ssl.csr" \
  -CA "${QUAY_INST_DIR}/config/rootCA.pem" \
  -CAkey "${QUAY_INST_DIR}/config/rootCA.key" \
  -CAcreateserial \
  -out "${QUAY_INST_DIR}/config/ssl.cert" \
  -days 36500 \
  -extensions v3_req \
  -extfile "${QUAY_INST_DIR}/config/openssl.cnf" >/dev/null 2>&1
run_command "[Generate domain certificate]"

sudo chmod 777 -R $QUAY_INST_DIR/config
run_command "[Change the permissions of $QUAY_INST_DIR/config]"

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Install quay registry]"

# Add registry entry to /etc/hosts
if ! grep -q "$QUAY_DOMAIN" /etc/hosts; then
  echo "# Add registry entry to /etc/hosts" | sudo tee -a /etc/hosts > /dev/null
  echo "$QUAY_HOST_IP $QUAY_DOMAIN" | sudo tee -a /etc/hosts > /dev/null
  echo "ok: [Add registry entry to /etc/hosts]"
else
  echo "skipping: [Registry entry already exists in /etc/hosts]"
fi

# Login registry.redhat.io
sudo podman login -u $REGISTRY_REDHAT_IO_ID -p "$REGISTRY_REDHAT_IO_PW" registry.redhat.io >/dev/null 2>&1
run_command "[Login registry.redhat.io]"

# Create a database data directory
mkdir -p $QUAY_INST_DIR/postgres-quay >/dev/null 2>&1
run_command "[Create a database data directory]"

sleep 5

# Set the appropriate permissions
setfacl -mu:26:-wx $QUAY_INST_DIR/postgres-quay >/dev/null 2>&1
run_command "[Set the appropriate permissions]"

sleep 5

if [ "$PWD" = "$QUAY_INST_DIR" ]; then
    echo "skipping: [Working directory conflicts with volume mount, switching to $HOME]"
    cd $HOME
fi

# Start the Postgres container
sudo podman run -d --rm --name postgresql-quay \
  -e POSTGRESQL_USER=quayuser \
  -e POSTGRESQL_PASSWORD=quaypass \
  -e POSTGRESQL_DATABASE=quay \
  -e POSTGRESQL_ADMIN_PASSWORD=adminpass \
  -p 5432:5432 \
  -v $QUAY_INST_DIR/postgres-quay:/var/lib/pgsql/data:Z \
  registry.redhat.io/rhel8/postgresql-13 >/dev/null 2>&1
run_command "[Start the Postgres container]"

sleep 10

# Ensure that the Postgres pg_trgm module is installed
sudo podman exec -it postgresql-quay /bin/bash -c 'echo "CREATE EXTENSION IF NOT EXISTS pg_trgm" | psql -d quay -U postgres' >/dev/null 2>&1
run_command "[Ensure that the Postgres pg_trgm module is installed]"

# Start the Redis container
sudo podman run -d --rm --name redis -p 6379:6379 -e REDIS_PASSWORD=strongpassword registry.redhat.io/rhel8/redis-6:1-110 >/dev/null 2>&1
run_command "[Start the Redis container]"

# Create a minimal config.yaml file that is used to deploy the Red Hat Quay container
cat > $QUAY_INST_DIR/config/config.yaml << EOF
BUILDLOGS_REDIS:
    host: $QUAY_DOMAIN
    password: strongpassword
    port: 6379
CREATE_NAMESPACE_ON_PUSH: true
DATABASE_SECRET_KEY: a8c2744b-7004-4af2-bcee-e417e7bdd235
DB_URI: postgresql://quayuser:quaypass@$QUAY_DOMAIN:5432/quay
DISTRIBUTED_STORAGE_CONFIG:
    default:
        - LocalStorage
        - storage_path: /datastorage/registry
DISTRIBUTED_STORAGE_DEFAULT_LOCATIONS: []
DISTRIBUTED_STORAGE_PREFERENCE:
    - default
FEATURE_MAILING: false
SECRET_KEY: e9bd34f4-900c-436a-979e-7530e5d74ac8
SERVER_HOSTNAME: $QUAY_DOMAIN
PREFERRED_URL_SCHEME: https
SETUP_COMPLETE: true
SUPER_USERS:
  - $QUAY_SUPER_USERS
USER_EVENTS_REDIS:
    host: $QUAY_DOMAIN
    password: strongpassword
    port: 6379
EOF
run_command "[Create a minimal config.yaml file that is used to deploy the Red Hat Quay container]"

# Create a local directory that will store registry images
mkdir $QUAY_INST_DIR/storage >/dev/null 2>&1
run_command "[Create a local directory that will store registry images]"

sleep 5

# Set the directory to store registry images
setfacl -m u:1001:-wx $QUAY_INST_DIR/storage >/dev/null 2>&1
run_command "[Set the directory to store registry images]"

sleep 5

# Deploy the Red Hat Quay registry 
sudo podman run -d --rm -p 8090:8080 -p 8443:8443 --name=quay \
   -v $QUAY_INST_DIR/config:/conf/stack:Z \
   -v $QUAY_INST_DIR/storage:/datastorage:Z \
   registry.redhat.io/quay/quay-rhel8:v3.15.0 >/dev/null 2>&1
run_command "[Deploy the Red Hat Quay registry ]"

# Checking container status
containers=("postgresql-quay" "redis" "quay")

for c in "${containers[@]}"; do
  if podman ps --format "{{.Names}}" | grep -qw "$c"; then
    echo "ok: [Container '$c' is running]"
  else
    echo "failed: [Container '$c' is running]"
  fi
done

# Add an empty line after the task
echo

# Step 3:
PRINT_TASK "TASK [Configuring additional trust stores for image registry access]"

# Copy the rootCA certificate to the trusted source
sudo rm -rf /etc/pki/ca-trust/source/anchors/$QUAY_DOMAIN.ca.pem
sudo cp ${QUAY_INST_DIR}/config/rootCA.pem /etc/pki/ca-trust/source/anchors/$QUAY_DOMAIN.ca.pem
run_command "[copy the rootca certificate to the trusted source: /etc/pki/ca-trust/source/anchors/$QUAY_DOMAIN.ca.pem]"

# Trust the rootCA certificate
sudo update-ca-trust
run_command "[trust the rootCA certificate]"

sleep 5

# Check if the registry-cas field exists
REGISTRY_CAS=$(oc get image.config.openshift.io/cluster -o yaml | grep -o 'registry-cas') >/dev/null 2>&1 || true

if [[ -n "$REGISTRY_CAS" ]]; then
  # If it exists, execute the following commands
  oc delete configmap registry-config -n openshift-config >/dev/null 2>&1 || true
  oc create configmap registry-config --from-file=${QUAY_DOMAIN}..8443=/etc/pki/ca-trust/source/anchors/${QUAY_DOMAIN}.ca.pem -n openshift-config >/dev/null 2>&1
  run_command  "[create a configmap containing the registry CA certificate: registry-config]"
  
  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-config"}}}' --type=merge >/dev/null 2>&1
  run_command  "[trust the registry-config configmap]"
else
  # If it doesn't exist, execute the following commands
  oc delete configmap registry-cas -n openshift-config >/dev/null 2>&1 || true
  oc create configmap registry-cas --from-file=${QUAY_DOMAIN}..8443=/etc/pki/ca-trust/source/anchors/${QUAY_DOMAIN}.ca.pem -n openshift-config >/dev/null 2>&1
  run_command  "[create a configmap containing the registry CA certificate: registry-cas]"

  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}' --type=merge >/dev/null 2>&1
  run_command  "[trust the registry-cas configmap]"
fi

# Add an empty line after the task
echo


# Step 4:
PRINT_TASK "TASK [Update pull-secret]"

# Export pull-secret
rm -rf pull-secret
oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 -d > pull-secret
run_command "[export pull-secret]"

sleep 5

# Update pull-secret file
export AUTHFILE="pull-secret"

# Base64 encode the username:password
AUTH=cXVheWFkbWluOnBhc3N3b3Jk
export REGISTRY=${QUAY_DOMAIN}:8443

if [ -f "$AUTHFILE" ]; then
  jq --arg registry "$REGISTRY" \
     --arg auth "$AUTH" \
     '.auths[$registry] = {auth: $auth}' \
     "$AUTHFILE" > tmp-authfile && mv -f tmp-authfile "$AUTHFILE"
else
cat <<EOF > $AUTHFILE
{
    "auths": {
        "$REGISTRY": {
            "auth": "$AUTH"
        }
    }
}
EOF
fi
echo "ok: [authentication information for quay registry added to $AUTHFILE]"

# Update pull-secret 
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret >/dev/null 2>&1
run_command "[update pull-secret for the cluster]"

rm -rf tmp-authfile >/dev/null 2>&1
rm -rf pull-secret >/dev/null 2>&1

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Checking the cluster status]"

# Check cluster operator status
MAX_RETRIES=20
SLEEP_INTERVAL=15
progress_started=false
retry_count=0

while true; do
    # Get the status of all cluster operators
    output=$(oc get co --no-headers | awk '{print $3, $4, $5}')
    
    # Check cluster operators status
    if echo "$output" | grep -q -v "True False False"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for all cluster operators to reach the expected state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [reached max retries, cluster operator may still be initializing]"
            break
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all cluster operators have reached the expected state]"
        break
    fi
done

# Check MCP status
MAX_RETRIES=20
SLEEP_INTERVAL=15
progress_started=false
retry_count=0

while true; do
    # Get the status of all mcp
    output=$(oc get mcp --no-headers | awk '{print $3, $4, $5}')
    
    # Check mcp status
    if echo "$output" | grep -q -v "True False False"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for all mcps to reach the expected state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [reached max retries, mcp may still be initializing]"
            break
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all mcp have reached the expected state]"
        break
    fi
done

# Add an empty line after the task
echo


# Step 4:
PRINT_TASK "TASK [Manually create a user]"

echo "note: [***  quay console: https://$QUAY_DOMAIN:8443  ***]"
echo "note: [***  you need to create a user in the quay console with an id of <$QUAY_SUPER_USERS> and a pw of <password>  ***]"
