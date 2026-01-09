#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAIL\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Set environment variables
export QUAY_VERSION='v3.15.2'               # Quay version: v3.12.12  v3.13.8   v3.14.5   v3.15.2
export MIRRORING_WORKER='v3.15.1'           # Mirroring-Worker version: v3.12.8  v3.13.7  v3.14.4  v3.15.1
export QUAY_HOST_NAME='quay-server.example.com'
export QUAY_HOST_IP="10.184.134.30"
export PULL_SECRET_FILE="$HOME/ocp-inst/pull-secret"
export QUAY_INST_DIR="/opt/quay-inst"
export QUAY_PORT="9443"
export REGISTRY_ID="quayadmin"
export REGISTRY_PW="password"
export OCP_TRUSTED_CA="true"                # OCP trust Quay: true, otherwise false


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
        echo -e "\e[96mINFO\e[0m $1"
    else
        echo -e "\e[31mFAIL\e[0m $1"
        exit 1
    fi
}

# Define color output variables
INFO_MSG="\e[96mINFO\e[0m"
FAIL_MSG="\e[31mFAIL\e[0m"
ACTION_MSG="\e[33mACTION\e[0m"

# Step 1:
PRINT_TASK "TASK [Delete existing duplicate data]"

# Function to remove a container with formatted output
remove_container() {
    local container_name="$1"
    if podman container exists "$container_name"; then
        if podman rm -f "$container_name" >/dev/null 2>&1; then
            echo -e "$INFO_MSG Container $container_name removed"
        else
            echo -e "$FAIL_MSG Container $container_name removed"
        fi
    else
        echo -e "$INFO_MSG No such container: $container_name"
    fi
}

# Function to remove a directory with formatted output
remove_directory() {
    local dir_path="$1"
    if [ -d "$dir_path" ]; then
        if sudo rm -rf "$dir_path" >/dev/null 2>&1; then
            echo -e "$INFO_MSG Quay install directory $dir_path removed"
        else
            echo -e "$FAIL_MSG Quay install directory $dir_path removed"
        fi
    else
        echo -e "$INFO_MSG No such install directory: $dir_path"
    fi
}

# Begin cleanup
remove_container "postgresql-quay"
remove_container "quay"
remove_container "redis"
remove_container "mirroring-worker"
remove_directory "$QUAY_INST_DIR"

# Remove CA certificate if it exists
CA_CERT="/etc/pki/ca-trust/source/anchors/${QUAY_HOST_NAME}.ca.pem"
if [ -f "$CA_CERT" ]; then
    if sudo rm -rf "$CA_CERT"; then
        echo -e "$INFO_MSG CA cert $CA_CERT removed"
    else
        echo -e "$FAIL_MSG CA cert $CA_CERT removed"
    fi
else
    echo -e "$INFO_MSG No such file: $CA_CERT"
fi

# Remove systemd service files if they exist
for service in postgresql-quay redis quay mirroring-worker; do
    SERVICE_FILE="/etc/systemd/system/container-${service}.service"

    if [ -f "$SERVICE_FILE" ]; then
        if sudo rm -rf "$SERVICE_FILE"; then
            echo -e "$INFO_MSG Systemd service $SERVICE_FILE removed"
        else
            echo -e "$FAIL_MSG Systemd service $SERVICE_FILE removed"
        fi
    else
        echo -e "$INFO_MSG No such file: $SERVICE_FILE"
    fi
done

# Add an empty line after the task
echo

# Step 2: 
PRINT_TASK "TASK [Install infrastructure RPM]"

# List of RPM packages to install
packages=("podman")

# Convert the array to a space-separated string
package_list="${packages[*]}"

# Install all packages at once
echo -e "$INFO_MSG Installing RPM package..."
dnf install -y $package_list >/dev/null 2>&1

# Check if each package was installed successfully
for package in "${packages[@]}"; do
    rpm -q $package >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "$INFO_MSG Install $package package"
    else
        echo -e "$FAIL_MSG Install $package package"
    fi
done

# Add an empty line after the task
echo

# Step 3: 
# Task: Generate a self-signed certificate
PRINT_TASK "[TASK: Generate a self-signed certificate]"

# Default variable
export DOMAIN="$QUAY_HOST_NAME"
export CERTS_DIR="$QUAY_INST_DIR/config"
export CA_CN="Test Workspace Signer"
export OPENSSL_CNF="/etc/pki/tls/openssl.cnf"

# Create a local directory to store the quay config.yaml and certificates
rm -rf $QUAY_INST_DIR > /dev/null 2>&1
mkdir -p $QUAY_INST_DIR/config >/dev/null 2>&1
run_command "Create a local directory to store the quay config.yaml and certificates"

# Generate the root Certificate Authority (CA) key
openssl genrsa -out ${CERTS_DIR}/rootCA.key 4096 > /dev/null 2>&1
run_command "Generate root CA private key"

# Generate the root CA certificate
openssl req -x509 \
  -new -nodes \
  -key ${CERTS_DIR}/rootCA.key \
  -sha256 \
  -days 1024 \
  -out ${CERTS_DIR}/rootCA.pem \
  -subj /CN="${CA_CN}" \
  -reqexts SAN \
  -extensions SAN \
  -config <(cat ${OPENSSL_CNF} \
      <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature')) > /dev/null 2>&1
run_command "Generate root CA self-signed certificate"

# Generate the SSL key
openssl genrsa -out ${CERTS_DIR}/ssl.key 2048 > /dev/null 2>&1
run_command "Generate SSL private key"

# Generate a certificate signing request (CSR) for the SSL
openssl req -new -sha256 \
    -key ${CERTS_DIR}/ssl.key \
    -subj "/O=Local Red Hat CodeReady Workspaces/CN=${DOMAIN}" \
    -reqexts SAN \
    -config <(cat ${OPENSSL_CNF} \
        <(printf "\n[SAN]\nsubjectAltName=DNS:${DOMAIN}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
    -out ${CERTS_DIR}/ssl.csr > /dev/null 2>&1
run_command "Generate SSL certificate signing request"

# Generate the SSL certificate (CRT)
openssl x509 \
    -req \
    -sha256 \
    -extfile <(printf "subjectAltName=DNS:${DOMAIN}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth") \
    -days 365 \
    -in ${CERTS_DIR}/ssl.csr \
    -CA ${CERTS_DIR}/rootCA.pem \
    -CAkey ${CERTS_DIR}/rootCA.key \
    -CAcreateserial -out ${CERTS_DIR}/ssl.cert  > /dev/null 2>&1
run_command "Generate SSL certificate signed by root CA"

sudo chmod 777 -R $QUAY_INST_DIR/config
run_command "Change the permissions of $QUAY_INST_DIR/config"

# Add an empty line after the task
echo

# Step 4:
PRINT_TASK "TASK [Install Quay Registry]"

cat $PULL_SECRET_FILE >/dev/null 2>&1
run_command "Verify existence of $PULL_SECRET_FILE file"

# Add registry entry to /etc/hosts
if ! grep -q "$QUAY_HOST_NAME" /etc/hosts; then
  echo "# Add registry entry to /etc/hosts" | sudo tee -a /etc/hosts > /dev/null
  echo "$QUAY_HOST_IP $QUAY_HOST_NAME" | sudo tee -a /etc/hosts > /dev/null
  echo -e "$INFO_MSG Add registry entry to /etc/hosts"
else
  echo -e "$INFO_MSG Registry entry already exists in /etc/hosts"
fi

# Create a database data directory
mkdir -p $QUAY_INST_DIR/postgres-quay >/dev/null 2>&1
run_command "Create a database data directory"

sleep 5

# Set the appropriate permissions
setfacl -mu:26:-wx $QUAY_INST_DIR/postgres-quay >/dev/null 2>&1
run_command "Set the appropriate permissions"

sleep 5

# Start the Postgres container
podman run -d --name postgresql-quay \
  --restart=always \
  -e POSTGRESQL_USER=quayuser \
  -e POSTGRESQL_PASSWORD=quaypass \
  -e POSTGRESQL_DATABASE=quay \
  -e POSTGRESQL_ADMIN_PASSWORD=adminpass \
  -p 5432:5432 \
  --authfile $PULL_SECRET_FILE \
  -v $QUAY_INST_DIR/postgres-quay:/var/lib/pgsql/data:Z \
  registry.redhat.io/rhel8/postgresql-13 >/dev/null 2>&1
run_command "Start the Postgres Container"

# Wait for container to be in Running state
containers=("postgresql-quay")   # container name
MAX_RETRIES=100               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started

while true; do
    all_running=true
    for c in "${containers[@]}"; do
        if ! podman ps --format "{{.Names}}" | grep -qw "$c"; then
            all_running=false
            break
        fi
    done

    CHAR=${SPINNER[$((retry_count % 4))]}

    if $all_running; then
        # Overwrite spinner line and print final message
        printf "\r"
        tput el
        echo -e "$INFO_MSG All containers are running"
        break
    else
        # Spinner display
        if ! $progress_started; then
            progress_started=true
        fi
        printf "\r$INFO_MSG Waiting for all containers to be running %s" "$CHAR"
        tput el

        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r"
            tput el
            echo -e "$FAIL_MSG Some containers are not running"
            exit 1
        fi
    fi
done

sleep 10

# Ensure that the Postgres pg_trgm module is installed
podman exec -it postgresql-quay /bin/bash -c 'echo "CREATE EXTENSION IF NOT EXISTS pg_trgm" | psql -d quay -U postgres' >/dev/null 2>&1
run_command "Enable pg_trgm module in quay postgres"

# Start the Redis container
podman run -d --name redis --restart=always \
  -p 6379:6379 \
  -e REDIS_PASSWORD=strongpassword \
  --authfile $PULL_SECRET_FILE \
  registry.redhat.io/rhel8/redis-6:1-110 >/dev/null 2>&1
run_command "Start the Redis container"

# Create a minimal config.yaml file for deploying Quay
cat > $QUAY_INST_DIR/config/config.yaml << EOF
BUILDLOGS_REDIS:
    host: $QUAY_HOST_NAME
    password: strongpassword
    port: 6379
CREATE_NAMESPACE_ON_PUSH: true
DATABASE_SECRET_KEY: a8c2744b-7004-4af2-bcee-e417e7bdd235
DB_URI: postgresql://quayuser:quaypass@$QUAY_HOST_NAME:5432/quay
DISTRIBUTED_STORAGE_CONFIG:
    default:
        - LocalStorage
        - storage_path: /datastorage/registry
DISTRIBUTED_STORAGE_DEFAULT_LOCATIONS: []
DISTRIBUTED_STORAGE_PREFERENCE:
    - default
FEATURE_REPO_MIRROR: true
FEATURE_MAILING: false
SECRET_KEY: e9bd34f4-900c-436a-979e-7530e5d74ac8
DEFAULT_TAG_EXPIRATION: 1s
TAG_EXPIRATION_OPTIONS:
    - 1s
TESTING: false
SERVER_HOSTNAME: $QUAY_HOST_NAME:$QUAY_PORT
PREFERRED_URL_SCHEME: https
SETUP_COMPLETE: true
FEATURE_USER_INITIALIZE: true
SUPER_USERS:
  - $REGISTRY_ID
USER_EVENTS_REDIS:
    host: $QUAY_HOST_NAME
    password: strongpassword
    port: 6379
EOF
run_command "Create a minimal config.yaml file for deploying Quay"

# Create a local directory that will store registry images
mkdir $QUAY_INST_DIR/storage >/dev/null 2>&1
run_command "Create a local directory that will store registry images"

sleep 5

# Set the directory to store registry images
setfacl -m u:1001:-wx $QUAY_INST_DIR/storage >/dev/null 2>&1
run_command "Set the directory to store registry images"

sleep 5

# Deploy the quay registry 
RUN_CONTAINER=$(podman run -d -p 8090:8080 -p $QUAY_PORT:8443 --name=quay \
   --restart=always \
   -v $QUAY_INST_DIR/config:/conf/stack:Z \
   -v $QUAY_INST_DIR/storage:/datastorage:Z \
   --authfile $PULL_SECRET_FILE \
   registry.redhat.io/quay/quay-rhel8:$QUAY_VERSION) >/dev/null 2>&1
run_command "Deploy the Quay registry container"

sleep 5

# Deploy the mirroring-worker
podman run -d --name mirroring-worker \
  -v $QUAY_INST_DIR/config:/conf/stack:Z \
  -v ${QUAY_INST_DIR}/config/rootCA.pem:/etc/pki/ca-trust/source/anchors/ca.crt:Z \
  --authfile $PULL_SECRET_FILE \
  registry.redhat.io/quay/quay-rhel8:$MIRRORING_WORKER repomirror >/dev/null 2>&1
run_command "Deploy the Mirroring Worker container"


# Wait for container to be in Running state
containers=("postgresql-quay" "redis" "quay" "mirroring-worker")   # container name
MAX_RETRIES=100               # Maximum number of retries
SLEEP_INTERVAL=2              # Sleep interval in seconds
SPINNER=('/' '-' '\' '|')     # Spinner animation characters
retry_count=0                 # Number of status check attempts
progress_started=false        # Tracks whether the spinner/progress line has been started

while true; do
    all_running=true
    for c in "${containers[@]}"; do
        if ! podman ps --format "{{.Names}}" | grep -qw "$c"; then
            all_running=false
            break
        fi
    done

    CHAR=${SPINNER[$((retry_count % 4))]}

    if $all_running; then
        # Overwrite spinner line and print final message
        printf "\r"
        tput el
        echo -e "$INFO_MSG All containers are running"
        break
    else
        # Spinner display
        if ! $progress_started; then
            progress_started=true
        fi
        printf "\r$INFO_MSG Waiting for all containers to be running %s" "$CHAR"
        tput el

        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r"
            tput el
            echo -e "$FAIL_MSG Some containers are not running"
            exit 1
        fi
    fi
done

# Generate systemd service file for PostgreSQL
sudo rm -rf container-*.service
CREATE_SYSTEMD_FILES=$(podman generate systemd --name postgresql-quay --files --restart-policy=always >/dev/null 2>&1)
run_command "Generate systemd service file for PostgreSQL"

# Generate systemd service file for Redis
CREATE_SYSTEMD_FILES=$(podman generate systemd --name redis --files --restart-policy=always >/dev/null 2>&1)
run_command "Generate systemd service file for Redis"

# Generate systemd service file for Quay
CREATE_SYSTEMD_FILES=$(podman generate systemd --name quay --files --restart-policy=always >/dev/null 2>&1)
run_command "Generate systemd service file for Quay"

# Generate systemd service file for Mirroring-Worker
CREATE_SYSTEMD_FILES=$(podman generate systemd --name mirroring-worker --files --restart-policy=always >/dev/null 2>&1)
run_command "Generate systemd service file for Mirroring-Worker"

# Move generated files to systemd directory
sudo mv container-*.service /etc/systemd/system/ >/dev/null 2>&1
run_command "Move generated files to systemd directory"

# Reload systemd to pick up new services
sudo systemctl daemon-reload >/dev/null 2>&1
run_command "Reload systemd to pick up new services"

# Enable and start each service
sudo systemctl enable --now container-postgresql-quay.service >/dev/null 2>&1
run_command "Enable and start postgresql service"

sudo systemctl enable --now container-redis.service >/dev/null 2>&1
run_command "Enable and start redis service"

sudo systemctl enable --now container-quay.service >/dev/null 2>&1
run_command "Enable and start quay service"

sudo systemctl enable --now container-mirroring-worker.service >/dev/null 2>&1
run_command "Enable and start mirroring-worker service"

# Copy the rootCA certificate to the trusted source
sudo cp ${QUAY_INST_DIR}/config/rootCA.pem /etc/pki/ca-trust/source/anchors/$QUAY_HOST_NAME.ca.pem
run_command "Copy rootCA certificate to trusted anchors"

# Trust the rootCA certificate
sudo update-ca-trust
run_command "Trust the rootCA certificate"

# Maximum number of retries and sleep interval
MAX_RETRIES=60
SLEEP_INTERVAL=2
LINE_WIDTH=120                 # Width for progress line formatting
SPINNER=('/' '-' '\' '|')      # Spinner animation characters
retry_count=0
progress_started=false

while true; do
    # Attempt to access the Quay user initialize API
    HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" \
                "https://$QUAY_HOST_NAME:$QUAY_PORT/api/v1/user/initialize" || true)

    # If HTTP code is 2xx/3xx/4xx, the API is considered available
    if [[ "$HTTP_CODE" =~ ^2|3|4$ ]]; then
        if $progress_started; then
            printf "\r$INFO_MSG Quay API is available%*s\n" $((LINE_WIDTH - 22)) ""
        else
            echo -e "$INFO_MSG Quay API is available"
        fi
        break
    fi

    # Display progress spinner while waiting
    CHAR=${SPINNER[$((retry_count % 4))]}
    MSG="Waiting for Quay API to be available..."
    if ! $progress_started; then
        printf "$INFO_MSG %s %s" "$MSG" "$CHAR"
        progress_started=true
    else
        printf "\r$INFO_MSG %s %s" "$MSG" "$CHAR"
    fi

    # Sleep for the defined interval and increment retry count
    sleep "$SLEEP_INTERVAL"
    retry_count=$((retry_count + 1))

    # Timeout handling
    if [[ $retry_count -ge $MAX_RETRIES ]]; then
        printf "\r$FAIL_MSG Quay API did not become available%*s\n" $((LINE_WIDTH - 36)) ""
        exit 1
    fi
done

# Using the API to create the first user
curl -X POST -k "https://$QUAY_HOST_NAME:$QUAY_PORT/api/v1/user/initialize" \
  -H 'Content-Type: application/json' \
  --data '{"username":"'"$REGISTRY_ID"'","password":"'"$REGISTRY_PW"'","email":"test@example.com","access_token":true}' >/dev/null 2>&1
run_command "Using the API to create the first user"

echo -e "$INFO_MSG Installation complete"

# Check the environment variable OCP_TRUSTED_CA: continue if "true", exit if otherwise
if [[ "$OCP_TRUSTED_CA" != "true" ]]; then
    echo 
    PRINT_TASK "TASK [Quay login information]"
    echo -e "$INFO_MSG Quay Console: https://$QUAY_HOST_NAME:$QUAY_PORT"
    echo -e "$INFO_MSG Quay superuser credentials — ID: $REGISTRY_ID, PW: $REGISTRY_PW"
    echo -e "\e[33mACTION\e[0m Add DNS Records for Standalone Quay to Allow OCP Access"
    exit 0
fi

# Add an empty line after the task
echo

# Step 5:
PRINT_TASK "TASK [Configuring additional trust stores for image registry access]"

# Check if the registry-cas field exists
REGISTRY_CAS=$(oc get image.config.openshift.io/cluster -o yaml | grep -o 'registry-cas') >/dev/null 2>&1 || true

if [[ -n "$REGISTRY_CAS" ]]; then
  # If it exists, execute the following commands
  oc delete configmap registry-cas -n openshift-config >/dev/null 2>&1 || true
  oc delete configmap registry-config -n openshift-config >/dev/null 2>&1 || true
  oc create configmap registry-config --from-file=${QUAY_HOST_NAME}..8443=/etc/pki/ca-trust/source/anchors/${QUAY_HOST_NAME}.ca.pem -n openshift-config >/dev/null 2>&1
  run_command "Create a configmap containing the registry CA certificate: registry-config"
  
  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-config"}}}' --type=merge >/dev/null 2>&1
  run_command "Trust the registry-config configmap"
else
  # If it doesn't exist, execute the following commands
  oc delete configmap registry-config -n openshift-config >/dev/null 2>&1 || true
  oc delete configmap registry-cas -n openshift-config >/dev/null 2>&1 || true
  oc create configmap registry-cas --from-file=${QUAY_HOST_NAME}..8443=/etc/pki/ca-trust/source/anchors/${QUAY_HOST_NAME}.ca.pem -n openshift-config >/dev/null 2>&1
  run_command "Create a configmap containing the registry CA certificate: registry-cas"

  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}' --type=merge >/dev/null 2>&1
  run_command "Trust the registry-cas configmap"
fi

# Add an empty line after the task
echo

# Step 6:
PRINT_TASK "TASK [Update pull-secret]"

# Export pull-secret
rm -rf tmp-pull-secret
oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 -d > tmp-pull-secret
run_command "Export pull-secret"

sleep 5

# Update pull-secret file
export AUTHFILE="tmp-pull-secret"

# Base64 encode the username:password
AUTH=cXVheWFkbWluOnBhc3N3b3Jk
export REGISTRY=${QUAY_HOST_NAME}:$QUAY_PORT

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
echo -e "$INFO_MSG Authentication information for quay registry added to $AUTHFILE"

# Update pull-secret 
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=tmp-pull-secret >/dev/null 2>&1
run_command "Update pull-secret for the cluster"

rm -rf tmp-authfile >/dev/null 2>&1
rm -rf tmp-pull-secret >/dev/null 2>&1

# Add an empty line after the task
echo

# Step 7:
PRINT_TASK "TASK [Checking the cluster status]"

# Wait for all MachineConfigPools (MCPs) to be Ready
MAX_RETRIES=150              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started

while true; do
    # Get MCP statuses: Ready, Updated, Degraded
    output=$(/usr/local/bin/oc get mcp --no-headers 2>/dev/null | awk '{print $3, $4, $5}')
    # If any MCP is not Ready/Updated/Degraded as expected
    if echo "$output" | grep -q -v "True False False"; then
        CHAR=${SPINNER[$((retry_count % 4))]}
        if ! $progress_started; then
            printf "$INFO_MSG Waiting for all MachineConfigPools to be Ready... %s" "$CHAR"
            progress_started=true
        else
            printf "\r$INFO_MSG Waiting for all MachineConfigPools to be Ready... %s" "$CHAR"
        fi

        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))
        # Timeout handling
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r$FAIL_MSG MachineConfigPools not Ready%*s\n" $((LINE_WIDTH - 20)) ""
            exit 1
        fi
    else
        # All MCPs are Ready
        if $progress_started; then
            printf "\r$INFO_MSG All MachineConfigPools are Ready%*s\n" $((LINE_WIDTH - 18)) ""
        else
            printf "$INFO_MSG All MachineConfigPools are Ready%*s\n" $((LINE_WIDTH - 18)) ""
        fi
        break
    fi
done

# Wait for all Cluster Operators (COs) to be Ready
MAX_RETRIES=150              # Maximum number of retries
SLEEP_INTERVAL=2             # Sleep interval in seconds
LINE_WIDTH=120               # Control line width
SPINNER=('/' '-' '\' '|')    # Spinner animation characters
retry_count=0                # Number of status check attempts
progress_started=false       # Tracks whether the spinner/progress line has been started

while true; do
    # Get Cluster Operator statuses: Available, Progressing, Degraded
    output=$(/usr/local/bin/oc get co --no-headers 2>/dev/null | awk '{print $3, $4, $5}')
    # If any CO is not Available/Progressing/Degraded as expected
    if echo "$output" | grep -q -v "True False False"; then
        CHAR=${SPINNER[$((retry_count % 4))]}
        if ! $progress_started; then
            printf "$INFO_MSG Waiting for all Cluster Operators to be Ready... %s" "$CHAR"
            progress_started=true
        else
            printf "\r$INFO_MSG Waiting for all Cluster Operators to be Ready... %s" "$CHAR"
        fi

        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))
        # Timeout handling
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            printf "\r$FAIL_MSG Cluster Operators not Ready%*s\n" $((LINE_WIDTH - 31)) ""
            exit 1
        fi
    else
        # All Cluster Operators are Ready
        if $progress_started; then
            printf "\r$INFO_MSG All Cluster Operators are Ready%*s\n" $((LINE_WIDTH - 32)) ""
        else
            printf "$INFO_MSG All Cluster Operators are Ready%*s\n" $((LINE_WIDTH - 32)) ""
        fi
        break
    fi
done

# Add an empty line after the task
echo

# Step 8:
PRINT_TASK "TASK [Quay login information]"

echo -e "$INFO_MSG Quay Console: https://$QUAY_HOST_NAME:$QUAY_PORT"
echo -e "$INFO_MSG Quay superuser credentials — ID: $REGISTRY_ID, PW: $REGISTRY_PW"

# Add an empty line after the task
echo

# Step 9:
PRINT_TASK "TASK [Add DNS Record Entries for Mirror Registry]"
echo -e "\e[33mACTION\e[0m Add DNS Records for Mirror Registry to Allow OCP Access"

# Add an empty line after the task
echo
