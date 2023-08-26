echo ====== Create certificate ======
mkdir -p /opt/registry/{auth,certs,data}
mkdir -p /etc/crts/ && cd /etc/crts/

openssl genrsa -out /etc/crts/${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.ca.key 4096

openssl req -x509 \
  -new -nodes \
  -key /etc/crts/${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.ca.key \
  -sha256 \
  -days 36500 \
  -out /etc/crts/${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.ca.crt \
  -subj /CN="Local Red Hat Signer" \
  -reqexts SAN \
  -extensions SAN \
  -config <(cat /etc/pki/tls/openssl.cnf \
      <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature'))

openssl genrsa -out ${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.key 2048

openssl req -new -sha256 \
    -key /etc/crts/${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.key \
    -subj "/O=Local Red Hat CodeReady Workspaces/CN=${$REGISTRY_HOSTNAME.$BASE_DOMAIN}" \
    -reqexts SAN \
    -config <(cat /etc/pki/tls/openssl.cnf \
        <(printf "\n[SAN]\nsubjectAltName=DNS:${$REGISTRY_HOSTNAME.$BASE_DOMAIN}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth")) \
    -out /etc/crts/${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.csr

openssl x509 \
    -req \
    -sha256 \
    -extfile <(printf "subjectAltName=DNS:${$REGISTRY_HOSTNAME.$BASE_DOMAIN}\nbasicConstraints=critical, CA:FALSE\nkeyUsage=digitalSignature, keyEncipherment, keyAgreement, dataEncipherment\nextendedKeyUsage=serverAuth") \
    -days 36500 \
    -in /etc/crts/${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.csr \
    -CA /etc/crts/${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.ca.crt \
    -CAkey /etc/crts/${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.ca.key \
    -CAcreateserial -out /etc/crts/${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.crt
    
openssl x509 -in /etc/crts/${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.ca.crt -text

cp /etc/crts/${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.ca.crt ${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.crt /etc/pki/ca-trust/source/anchors/
update-ca-trust extract
cp /etc/crts/${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.key ${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.crt /opt/registry/certs/
update-ca-trust

# Check if certificate files exist
check_file() {
    if [ -f "$1" ]; then
        echo "$1 generated successfully."
    else
        echo "$1 not generated."
    fi
}

# Check if certificates and keys exist
check_file "/etc/crts/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.key"
check_file "/etc/crts/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.crt"
check_file "/etc/crts/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.key"
check_file "/etc/crts/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.csr"
check_file "/etc/crts/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.crt"
check_file "/opt/registry/certs/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.ca.crt"
check_file "/opt/registry/certs/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.crt"
check_file "/opt/registry/certs/${REGISTRY_HOSTNAME}.${BASE_DOMAIN}.key"

#######################################################

echo ====== Create htpasswd user ======
# Create user using htpasswd
htpasswd -bBc /opt/registry/auth/htpasswd "$REGISTRY_ID" "$REGISTRY_PW"

# Check the return code of the htpasswd command
if [ $? -eq 0 ]; then
    echo "User $REGISTRY_ID was successfully added."
else
    echo "Failed to add user $REGISTRY_ID."
fi

#######################################################


echo ====== Run registry container ======
podman run \
    --name mirror-registry \
    -p 5000:5000 \
    -e "REGISTRY_AUTH=htpasswd" \
    -e "REGISTRY_AUTH_HTPASSWD_REALM=Registry Realm" \
    -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
    -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.crt \
    -e REGISTRY_HTTP_TLS_KEY=/certs/${$REGISTRY_HOSTNAME.$BASE_DOMAIN}.key \
    -e REGISTRY_STORAGE_DELETE_ENABLED=true \
    -v /opt/registry/data:/var/lib/registry:z \
    -v /opt/registry/auth:/auth:z \
    -v /opt/registry/certs:/certs:z \
    -d docker.io/library/registry:2

sudo sleep 60

# Check if container is running
if podman ps | grep -q "mirror-registry"; then
    echo "Container is running."
else
    echo "Container is not running."
fi

#######################################################

echo ====== Create mirror-registry.service ======
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

# Enable and start HAProxy service
systemctl enable mirror-registry.service
systemctl start mirror-registry.service
sleep 5

# Check if a service is enabled and running
check_service() {
    service_name=$1

    if systemctl is-enabled "$service_name" &>/dev/null; then
        echo "$service_name service is enabled."
    else
        echo "Error: $service_name service is not enabled."
    fi

    if systemctl is-active "$service_name" &>/dev/null; then
        echo "$service_name service is running."
    else
        echo "Error: $service_name service is not running."
    fi
}

# List of services to check
services=("mirror-registry.service")

# Check status of all services
for service in "${services[@]}"; do
    check_service "$service"
done

#######################################################


echo ====== Registry login authentication file ======
# Login to the registry
podman login -u "$REGISTRY_ID" -p "$REGISTRY_PW" --authfile "$LOCAL_SECRET_JSON" "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000"

# Check the return code of the podman login command
if [ $? -eq 0 ]; then
    echo "Successfully logged in to the registry."
else
    echo "Failed to log in to the registry."
fi


podman login -u "$REGISTRY_ID" -p "$REGISTRY_PW"  "${REGISTRY_HOSTNAME}.${BASE_DOMAIN}:5000"

# Check the return code of the podman login command
if [ $? -eq 0 ]; then
    echo "Successfully logged in to the registry."
else
    echo "Failed to log in to the registry."
fi


#######################################################


echo ====== Download ocp images ======
# Execute oc adm release mirror command
oc adm -a ${LOCAL_SECRET_JSON} release mirror \
  --from=quay.io/${PRODUCT_REPO}/${RELEASE_NAME}:${OCP_RELEASE}-${ARCHITECTURE} \
  --to=${$REGISTRY_HOSTNAME.$BASE_DOMAIN}:5000/${LOCAL_REPOSITORY} \
  --to-release-image=${$REGISTRY_HOSTNAME.$BASE_DOMAIN}:5000/${LOCAL_REPOSITORY}:${OCP_RELEASE}-${ARCHITECTURE} 
  
# Check the return code of the oc adm release mirror command
if [ $? -eq 0 ]; then
    echo "Successfully mirrored release."
else
    echo "Failed to mirror release."
fi
sudo sleep 10

curl -u $REGISTRY_ID:$REGISTRY_PW -k https://${$REGISTRY_HOSTNAME.$BASE_DOMAIN}:5000/v2/_catalog
