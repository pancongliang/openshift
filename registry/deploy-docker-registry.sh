#!/bin/bash
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

# Delete existing file
rm -rf /etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN_NAME}.ca.crt &>/dev/null
rm -rf /etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN_NAME}.crt &>/dev/null
rm -rf ${REGISTRY_INSTALL_PATH} &>/dev/null
rm -rf ${REGISTRY_CERT_PATH} &>/dev/null


# Function to check command success and display appropriate message
check_command_result() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}


# === Task: Generate a self-signed certificate ===
PRINT_TASK "[TASK: Generate a self-signed certificate]"

# Generate a directory for creating certificates
mkdir -p ${REGISTRY_CERT_PATH} &>/dev/null
check_command_result "[created directory for certificates: ${REGISTRY_CERT_PATH}]"

# Generate the root Certificate Authority (CA) key
openssl genrsa -out ${REGISTRY_CERT_PATH}/${REGISTRY_DOMAIN_NAME}.ca.key 4096 &>/dev/null
check_command_result "[generated root certificate authority key]"

# Generate the root CA certificate
openssl req -x509 \
  -new -nodes \
  -key ${REGISTRY_CERT_PATH}/${REGISTRY_DOMAIN_NAME}.ca.key \
  -sha256 -days 36500 \
  -out ${REGISTRY_CERT_PATH}/${REGISTRY_DOMAIN_NAME}.ca.crt \
  -subj /CN="Local Red Hat Signer" \
  -reqexts SAN \
  -extensions SAN \
  -config <(cat /etc/pki/tls/openssl.cnf \
      <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature')) &>/dev/null
check_command_result "[generate the root CA certificate]"

# Generate the domain key
openssl genrsa -out ${REGISTRY_CERT_PATH}/${REGISTRY_DOMAIN_NAME}.key 2048 &>/dev/null
check_command_result "[generate the domain key]"

# Generate a certificate signing request (CSR) for the domain
openssl req -new -sha256 \
    -key ${REGISTRY_CERT_PATH}/${REGISTRY_DOMAIN_NAME}.key \
    -subj "/O=Local Red Hat CodeReady Workspaces/CN=${REGISTRY_DOMAIN_NAME}" \
    -reqexts SAN \
    -config <(cat /etc/pki/tls/openssl.cnf \
        <(printf "\n[SAN]\nsubjectAltName=DNS:${REGISTRY_DOMAIN_NAME}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
    -out ${REGISTRY_CERT_PATH}/${REGISTRY_DOMAIN_NAME}.csr &>/dev/null
check_command_result "[generate the certificate signing request for the domain(CSR)]"

# Generate the domain certificate (CRT)
openssl x509 -req -sha256 \
    -extfile <(printf "subjectAltName=DNS:${REGISTRY_DOMAIN_NAME}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth") \
    -days 36500 \
    -in ${REGISTRY_CERT_PATH}/${REGISTRY_DOMAIN_NAME}.csr \
    -CA ${REGISTRY_CERT_PATH}/${REGISTRY_DOMAIN_NAME}.ca.crt \
    -CAkey ${REGISTRY_CERT_PATH}/${REGISTRY_DOMAIN_NAME}.ca.key \
    -CAcreateserial -out ${REGISTRY_CERT_PATH}/${REGISTRY_DOMAIN_NAME}.crt &>/dev/null
check_command_result "[generate the domain certificate(CRT)]"



# === Task: Install Registry ===
PRINT_TASK "[TASK: Install registry]"

# Created directories for registry installation
mkdir -p ${REGISTRY_INSTALL_PATH}/{auth,certs,data} &>/dev/null
check_command_result "[create directories for registry installation ${REGISTRY_INSTALL_PATH}]"

# Copying root and domain certificates to trust source
cp "${REGISTRY_CERT_PATH}/${REGISTRY_DOMAIN_NAME}.ca.crt" "${REGISTRY_CERT_PATH}/${REGISTRY_DOMAIN_NAME}.crt" /etc/pki/ca-trust/source/anchors/ &>/dev/null
check_command_result "[copying root and domain certificates to trust source]"

# Copy certificate and key to the specified path
cp "${REGISTRY_CERT_PATH}/${REGISTRY_DOMAIN_NAME}.key" "${REGISTRY_CERT_PATH}/${REGISTRY_DOMAIN_NAME}.crt" ${REGISTRY_INSTALL_PATH}/certs/ &>/dev/null
check_command_result "[copy certificate and key to ${REGISTRY_INSTALL_PATH}/certs/]"

# Update trust settings with new certificates
update-ca-trust &>/dev/null
check_command_result "[updating trust settings with new certificates]"

# Create user using htpasswd identity provider
htpasswd -bBc ${REGISTRY_INSTALL_PATH}/auth/htpasswd "${USER}" "${PASSWD}" &>/dev/null
check_command_result "[create ${USER} user using htpasswd identity provider]" 

# Delete the container with the same name
podman stop $CONTAINER_NAME &>/dev/null
podman rm $CONTAINER_NAME &>/dev/null

#  Generate registry container
podman run \
    --name ${CONTAINER_NAME} \
    -p 5000:5000 \
    -e REGISTRY_AUTH="htpasswd" \
    -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/${REGISTRY_DOMAIN_NAME}.crt \
    -e REGISTRY_HTTP_TLS_KEY=/certs/${REGISTRY_DOMAIN_NAME}.key \
    -e REGISTRY_STORAGE_DELETE_ENABLED=true \
    -v ${REGISTRY_INSTALL_PATH}/data:/var/lib/registry:z \
    -v ${REGISTRY_INSTALL_PATH}/auth:/auth:z \
    -v ${REGISTRY_INSTALL_PATH}/certs:/certs:z \
    -d docker.io/library/registry:2 &>/dev/null

sudo sleep 60

# Check if container is running
container_info=$(podman inspect -f '{{.State.Status}}' $CONTAINER_NAME 2>/dev/null)
if [ "$container_info" == "running" ]; then
    echo "ok: [container '$CONTAINER_NAME' is running]"
else
    echo "failed: [container '$CONTAINER_NAME' is not running]"
fi


# Generating a systemd unit file for the registry service
rm -rf /etc/systemd/system/${CONTAINER_NAME}.service

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
systemctl enable ${CONTAINER_NAME}.service &>/dev/null
check_command_result "[change the systemd ${CONTAINER_NAME} service to enable]"
systemctl start ${CONTAINER_NAME}.service
check_command_result "[restart the systemd ${CONTAINER_NAME} service]"

# loggin registry
podman login -u ${USER} -p ${PASSWD} https://${REGISTRY_DOMAIN_NAME}:5000 &>/dev/null
check_command_result "[login ${CONTAINER_NAME}: https://${REGISTRY_DOMAIN_NAME}:5000]"