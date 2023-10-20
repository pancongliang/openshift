# Generating self-signed TLS certificates

* Set necessary variables
  ```
  export DOMAIN_NAME="test.apps.ocp4.example.com"
  export CERTS_PATH="/root/certs"
  ```
  
* Download and execute the script to generate the certificate
  ```
  wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/certificate/self-signed-cert.sh
  source self-signed-cert.sh
  ```
