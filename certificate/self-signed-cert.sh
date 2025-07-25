#!/bin/bash

# Default variable
export DOMAIN_NAME="test.apps.ocp4.example.com"

export CERTS_PATH="./certs"
export CA_CN="Test Workspace Signer"
export OPENSSL_CNF="/etc/pki/tls/openssl.cnf"

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=90  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

# Task: Generate a self-signed certificate
PRINT_TASK "[TASK: Generate a self-signed certificate]"

# Function to check command success and display appropriate message
check_command_result() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}

# Generate a directory for creating certificates
mkdir -p ${CERTS_PATH} > /dev/null 2>&1
check_command_result "[create cert directory: ${CERTS_PATH}]"

# Generate the root Certificate Authority (CA) key
openssl genrsa -out ${CERTS_PATH}/${DOMAIN_NAME}.ca.key 4096 > /dev/null 2>&1
check_command_result "[generate root CA key]"

# Generate the root CA certificate
openssl req -x509 \
    -new -nodes \
    -key ${CERTS_PATH}/${DOMAIN_NAME}.ca.key \
    -sha256 \
    -days 36500 \
    -out ${CERTS_PATH}/${DOMAIN_NAME}.ca.crt \
    -subj /CN="${CA_CN}" \
    -reqexts SAN \
    -extensions SAN \
    -config <(cat ${OPENSSL_CNF} \
        <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature')) > /dev/null 2>&1
check_command_result "[generate root CA certificate]"

# Generate the domain key
openssl genrsa -out ${CERTS_PATH}/${DOMAIN_NAME}.key 2048 > /dev/null 2>&1
check_command_result "[generate domain private key]"

# Generate a certificate signing request (CSR) for the domain
openssl req -new -sha256 \
    -key ${CERTS_PATH}/${DOMAIN_NAME}.key \
    -subj "/O=Local Cert/CN=${DOMAIN_NAME}" \
    -reqexts SAN \
    -config <(cat ${OPENSSL_CNF} \
        <(printf "\n[SAN]\nsubjectAltName=DNS:${DOMAIN_NAME}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
    -out ${CERTS_PATH}/${DOMAIN_NAME}.csr > /dev/null 2>&1
check_command_result "[generate domain certificate signing request]"

# Generate the domain certificate (CRT)
openssl x509 \
    -req \
    -sha256 \
    -extfile <(printf "subjectAltName=DNS:${DOMAIN_NAME}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth") \
    -days 36500 \
    -in ${CERTS_PATH}/${DOMAIN_NAME}.csr \
    -CA ${CERTS_PATH}/${DOMAIN_NAME}.ca.crt \
    -CAkey ${CERTS_PATH}/${DOMAIN_NAME}.ca.key \
    -CAcreateserial -out ${CERTS_PATH}/${DOMAIN_NAME}.crt > /dev/null 2>&1
check_command_result "[generate domain certificate]"

# self-signed-certificates 
# https://access.redhat.com/documentation/en-us/red_hat_codeready_workspaces/2.1/html/installation_guide/installing-codeready-workspaces-in-tls-mode-with-self-signed-certificates_crw
