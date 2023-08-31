!/bin/bash
# === Function to print a task with uniform length ===
# Function to print a task with uniform length
PRINT_TASK() {
    max_length=90  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}
# ====================================================


# === Task: Generate a self-signed certificate ===
PRINT_TASK "[TASK: Generate a self-signed certificate]"


# Step 1: Delete existing file
# ----------------------------------------
# Check if there is an existing file
# Define the file paths
file_paths=(
    "/etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.crt"
    "/etc/pki/ca-trust/source/anchors/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.crt"
    "${REGISTRY_INSTALL_PATH}"
    "${REGISTRY_CERT_PATH}"
)

# Check if any file already exists
existing_file=false
for path in "${file_paths[@]}"; do
    if [ -f "$path" ]; then
        existing_file=true
        break
    fi
done

if [ "$existing_file" = true ]; then
    # Delete existing files
    for path in "${file_paths[@]}"; do
        if [ -f "$path" ]; then
            rm -f "$path"
            echo "ok: [deleted: $path]"
        fi
    done
fi



# Function to check command success and display appropriate message
check_command_result() {
    if [ $? -eq 0 ]; then
        echo "$1 ok"
    else
        echo "$1 failed"
    fi
}

echo ====== Create certificate ======
# Generate a directory for creating certificates
mkdir -p ${REGISTRY_CERT_PATH}
check_command_result "[generated certificate directory]"

# Generate the root Certificate Authority (CA) key
openssl genrsa -out ${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.key 4096
check_command_result "[generated root certificate authority (CA) key]"

# Generate the root CA certificate
openssl req -x509 \
  -new -nodes \
  -key ${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.key \
  -sha256 -days 36500 \
  -out ${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.crt \
  -subj /CN="Local Red Hat Signer" \
  -reqexts SAN \
  -extensions SAN \
  -config <(cat /etc/pki/tls/openssl.cnf \
      <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature'))
check_command_result "[generate the root CA certificate]"

# Generate the domain key
openssl genrsa -out ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.key 2048
check_command_result "[generate the domain key]"

# Generate the certificate signing request for the domain(CSR)
openssl req -new -sha256 \
    -key ${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.key \
    -subj "/O=Local Red Hat CodeReady Workspaces/CN=${REGISTRY_HOSTNAME}.${BASE_DOMAIN}" \
    -reqexts SAN \
    -config <(cat /etc/pki/tls/openssl.cnf \
        <(printf "\n[SAN]\nsubjectAltName=DNS:${REGISTRY_HOSTNAME}.${BASE_DOMAIN}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
    -out ${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.csr
check_command_result "[generate the certificate signing request for the domain(CSR)]"

# Generate the domain certificate(CRT)
openssl x509 -req -sha256 \
    -extfile <(printf "subjectAltName=DNS:${REGISTRY_HOSTNAME}.${BASE_DOMAIN}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth") \
    -days 36500 \
    -in ${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.csr \
    -CA ${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.crt \
    -CAkey ${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.key \
    -CAcreateserial -out ${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.crt
check_command_result "[generate the domain certificate(CRT)]"





# === Task: Install docker-registry ===
PRINT_TASK "[TASK: Install mirror-registry]"

# Created directories for registry installation
mkdir -p ${REGISTRY_INSTALL_PATH}/{auth,certs,data}
check_command_result "[create directories for registry installation]"

# Copying root and domain certificates to trust source
cp ${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.crt ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.crt /etc/pki/ca-trust/source/anchors/
check_command_result "[copying root and domain certificates to trust source]"

# Copy certificate and key to the specified path
cp ${REGISTRY_CERT_PATH}/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.key ${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.crt ${REGISTRY_INSTALL_PATH}/certs/
check_command_result "[copy certificate and key to ${REGISTRY_INSTALL_PATH}/certs/]"

# Update trust settings with new certificates
update-ca-trust
check_command_result "[updating trust settings with new certificates]"

# Create user using htpasswd identity provider
htpasswd -bBc ${REGISTRY_INSTALL_PATH}/auth/htpasswd "$REGISTRY_ID" "$REGISTRY_PW"
check_command_result "[create $REGISTRY_ID user using htpasswd identity provider]"


# Check if there is a "mirror-registry" container with the same name
CONTAINER_NAME="registry"

# Check if the container exists
if podman inspect $CONTAINER_NAME > /dev/null 2>&1; then
    # Stop and remove the container
    podman stop $CONTAINER_NAME
    podman rm $CONTAINER_NAME
    echo "Container '$CONTAINER_NAME' stopped and removed successfully"
else
    echo "Container '$CONTAINER_NAME' does not exist"
fi


podman run \
    --name ${CONTAINER_NAME} \
    -p 5000:5000 \
    -e REGISTRY_AUTH="htpasswd" \
    -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.crt \
    -e REGISTRY_HTTP_TLS_KEY=/certs/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.key \
    -e REGISTRY_STORAGE_DELETE_ENABLED=true \
    -v ${REGISTRY_INSTALL_PATH}/data:/var/lib/registry:z \
    -v ${REGISTRY_INSTALL_PATH}/auth:/auth:z \
    -v ${REGISTRY_INSTALL_PATH}/certs:/certs:z \
    -d docker.io/library/registry:2
check_command_result "[starting $CONTAINER_NAME container...]"
sudo sleep 60

# Check if container is running
podman ps | grep -q "${CONTAINER_NAME}"; then
check_command_result "[start the ${CONTAINER_NAME} container]"


# Generating a systemd unit file for the registry service
cat << EOF > /etc/systemd/system/${CONTAINER_NAME}.service
[Unit]
Description= ${CONTAINER_NAME} service
After=network.target
After=network-online.target
[Service]
Restart=always
ExecStart=/usr/bin/podman start -a ${CONTAINER_NAME}
ExecStop=/usr/bin/podman stop -t 10 ${CONTAINER_NAME}
[Install]
WantedBy=multi-user.target
EOF
check_command_result "[generating a systemd unit file for the ${CONTAINER_NAME} service]"

# Enable and start registry service
systemctl enable ${CONTAINER_NAME}.service
check_command_result "[change the systemd ${CONTAINER_NAME} service to enabled]"
systemctl start ${CONTAINER_NAME}.service
check_command_result "[restart the systemd ${CONTAINER_NAME} service]"




