#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Default variable
export DOMAIN="quay-server.example.com"
export CERTS_DIR="certs"

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

export CA_CN="Test Workspace Signer"
export OPENSSL_CNF="/etc/pki/tls/openssl.cnf"

# Generate a directory for creating certificates
rm -rf ${CERTS_DIR} > /dev/null 2>&1
mkdir -p ${CERTS_DIR} > /dev/null 2>&1
run_command "[Generate certificate directory: ${CERTS_DIR}]"

# Generate the root Certificate Authority (CA) key
openssl genrsa -out ${CERTS_DIR}/rootCA.key 4096 > /dev/null 2>&1
run_command "[Generate root CA private key]"

# Generate the root CA certificate
openssl req -x509 \
  -new -nodes \
  -key ${CERTS_DIR}/rootCA.key \
  -sha256 \
  -days 36500 \
  -out ${CERTS_DIR}/rootCA.pem \
  -subj /CN="${CA_CN}" \
  -reqexts SAN \
  -extensions SAN \
  -config <(cat ${OPENSSL_CNF} \
      <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature')) > /dev/null 2>&1
run_command "[Generate root CA self-signed certificate]"

# Generate the SSL key
openssl genrsa -out ${CERTS_DIR}/ssl.key 2048 > /dev/null 2>&1
run_command "[Generate SSL private key]"

# Generate a certificate signing request (CSR) for the SSL
openssl req -new -sha256 \
    -key ${CERTS_DIR}/ssl.key \
    -subj "/O=Local Red Hat CodeReady Workspaces/CN=${DOMAIN}" \
    -reqexts SAN \
    -config <(cat ${OPENSSL_CNF} \
        <(printf "\n[SAN]\nsubjectAltName=DNS:${DOMAIN}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
    -out ${CERTS_DIR}/ssl.csr > /dev/null 2>&1
run_command "[Generate SSL certificate signing request]"

# Generate the SSL certificate (CRT)
openssl x509 \
    -req \
    -sha256 \
    -extfile <(printf "subjectAltName=DNS:${DOMAIN}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth") \
    -days 365 \
    -in ${CERTS_DIR}/ssl.csr \
    -CA ${CERTS_DIR}/rootCA.pem \
    -CAkey ${CERTS_DIR}/rootCA.key \
    -CAcreateserial -out ${CERTS_DIR}/ssl.crt  > /dev/null 2>&1
run_command "[Generate SSL certificate signed by root CA]"

# self-signed-certificates 
# https://access.redhat.com/documentation/en-us/red_hat_codeready_workspaces/2.1/html/installation_guide/installing-codeready-workspaces-in-tls-mode-with-self-signed-certificates_crw
