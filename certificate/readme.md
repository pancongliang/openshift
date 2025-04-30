## Generating self-signed TLS certificates

* Set necessary variables
  ```
  wget -q https://raw.githubusercontent.com/pancongliang/openshift/main/certificate/self-signed-cert.sh
  
  vim self-signed-cert.sh
  export DOMAIN_NAME="test.apps.ocp4.example.com"
  ```
  
* Execute the script to generate the certificate
  ```
  source self-signed-cert.sh
  ```
