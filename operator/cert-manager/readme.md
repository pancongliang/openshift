* Install the Operator using the default namespace
  ~~~
  export CHANNEL_NAME="stable-v1"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="cert-manager-operator"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/cert-manager/01-operator.yaml | envsubst | oc create -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ~~~
    
* Create a Private CA Certificate
  ~~~
  openssl genrsa -out rootCA.key
  
  openssl req -x509 \
    -new -nodes \
    -key rootCA.key \
    -sha256 \
    -days 36500 \
    -out rootCA.pem \
    -subj /CN="Test Workspace Signer" \
    -reqexts SAN \
    -extensions SAN \
    -config <(cat /etc/pki/tls/openssl.cnf \
            <(printf '[SAN]\nbasicConstraints=critical, CA:TRUE\nkeyUsage=keyCertSign, cRLSign, digitalSignature'))
  ~~~


* Create a Secret to Store the CA in cert-manager Namespace
  ~~~
  export CA_SIGNER_SECRET=example-ca-signer
  export CA_CRT=rootCA.pem
  export CA_KEY=rootCA.key

  oc create secret tls -n cert-manager $CA_SIGNER_SECRET --cert=$CA_CRT --key=$CA_KEY
  ~~~

* Create a ClusterIssuer Using the Private CA
  ~~~
  export CLUSTER_ISSUER=example-clusterissuer
  export CA_SIGNER_SECRET=example-ca-signer

  cat << EOF | oc apply -f -
  apiVersion: cert-manager.io/v1
  kind: ClusterIssuer
  metadata:
    name: $CLUSTER_ISSUER
  spec:
    ca:
      secretName: $CA_SIGNER_SECRET
  EOF
  ~~~

* Create a New Certificate Request (e.g., for the Ingress Controller)
  ~~~
  export INGRESS_DOMAIN=apps.ocp.example.com
  export INGRESS_CERT_SECRET=router-certs-custom
  export CERT_DURATION="2h"                       # Validity period of the certificate
  export CERT_RENEW_BEFORE_EXPIRY="1h"            # Time before expiry to renew the certificate

  cat << EOF | oc apply -f -
  apiVersion: cert-manager.io/v1
  kind: Certificate
  metadata:
    name: ingress-cert
    namespace: openshift-ingress
  spec:
    isCA: false
    commonName: "$INGRESS_DOMAIN" 
    secretName: $INGRESS_CERT_SECRET
    dnsNames:
    - "$INGRESS_DOMAIN" 
    - "*.$INGRESS_DOMAIN" 
    issuerRef:
      name: $CLUSTER_ISSUER
      kind: ClusterIssuer
    duration: $CERT_DURATION
    renewBefore: $CERT_RENEW_BEFORE_EXPIRY
  EOF
  ~~~

* Update the Ingress Controller configuration with the newly created secret  
  ~~~
  oc patch ingresscontroller.operator default \
  --type=json -n openshift-ingress-operator \
  -p "[{\"op\":\"replace\",\"path\":\"/spec/defaultCertificate\",\"value\":{\"name\":\"$INGRESS_CERT_SECRET\"}}]"
  ~~~

* Verify that the ingress certificate has been updated
  ~~~
  $ oc get po -n openshift-ingress
  ··· Output ···
  NAME                              READY   STATUS    RESTARTS   AGE
  router-default-768dbb9787-q8b9k   1/1     Running   0          2m48s
  router-default-768dbb9787-sxk4x   1/1     Running   0          2m16s

  $ oc get secret -n openshift-ingress $INGRESS_CERT_SECRET -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates -issuer -subject
  ··· Output ···  
  notBefore=Nov 14 11:21:05 2025 GMT
  notAfter=Nov 14 13:21:05 2025 GMT
  issuer=CN = Test Workspace Signer
  subject=CN = apps.ocp.example.com

  $ openssl s_client -connect console-openshift-console.$INGRESS_DOMAIN:443 -showcerts | openssl x509 -noout -issuer -dates -subject -ext subjectAltName
  ··· Output ···  
  depth=0 CN = apps.ocp.example.com
  verify error:num=20:unable to get local issuer certificate
  verify return:1
  depth=0 CN = apps.ocp.example.com
  verify error:num=21:unable to verify the first certificate
  verify return:1
  depth=0 CN = apps.ocp.example.com
  verify return:1
  issuer=CN = Test Workspace Signer
  notBefore=Nov 14 11:21:05 2025 GMT
  notAfter=Nov 14 13:21:05 2025 GMT
  subject=CN = apps.ocp.example.com
  X509v3 Subject Alternative Name: 
      DNS:apps.ocp.example.com, DNS:*.apps.ocp.example.com
  ~~~

* Wait one hour to verify the automatic renewal of the ingress certificate
  ~~~
  # The router pod will not restart during certificate renewal.
  $ oc get po -n openshift-ingress
  ··· Output ···
  NAME                              READY   STATUS    RESTARTS   AGE
  router-default-768dbb9787-q8b9k   1/1     Running   0          104m
  router-default-768dbb9787-sxk4x   1/1     Running   0          104m

  $ openssl s_client -connect console-openshift-console.$INGRESS_DOMAIN:443 -showcerts | openssl x509 -noout -issuer -dates -subject -ext subjectAltName
  ··· Output ···
  depth=0 CN = apps.ocp.example.com
  verify error:num=20:unable to get local issuer certificate
  verify return:1
  depth=0 CN = apps.ocp.example.com
  verify error:num=21:unable to verify the first certificate
  verify return:1
  depth=0 CN = apps.ocp.example.com
  verify return:1
  issuer=CN = Test Workspace Signer
  notBefore=Nov 14 12:21:05 2025 GMT
  notAfter=Nov 14 14:21:05 2025 GMT
  subject=CN = apps.ocp.example.com
  X509v3 Subject Alternative Name: 
      DNS:apps.ocp.example.com, DNS:*.apps.ocp.example.com

  $ oc get secret -n openshift-ingress $INGRESS_CERT_SECRET -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates -issuer -subject
  ··· Output ···
  notBefore=Nov 14 12:21:05 2025 GMT
  notAfter=Nov 14 14:21:05 2025 GMT
  issuer=CN = Test Workspace Signer
  subject=CN = apps.ocp.example.com


  $ openssl s_client -connect console-openshift-console.$INGRESS_DOMAIN:443 -showcerts | openssl x509 -noout -issuer -dates -subject -ext subjectAltName
  ··· Output ···
  ···
  issuer=CN = Test Workspace Signer
  notBefore=Nov 14 13:21:05 2025 GMT
  notAfter=Nov 14 15:21:05 2025 GMT
  subject=CN = apps.ocp.example.com
  X509v3 Subject Alternative Name: 
      DNS:apps.ocp.example.com, DNS:*.apps.ocp.example.com

  $ oc get secret -n openshift-ingress $INGRESS_CERT_SECRET -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates -issuer -subject
  ··· Output ···
  notBefore=Nov 14 13:21:05 2025 GMT
  notAfter=Nov 14 15:21:05 2025 GMT
  issuer=CN = Test Workspace Signer
  subject=CN = apps.ocp.example.com

  # The router pod will not restart during certificate renewal.
  $ oc get po -n openshift-ingress
  ··· Output ···
  NAME                              READY   STATUS    RESTARTS   AGE
  router-default-768dbb9787-q8b9k   1/1     Running   0          122m
  router-default-768dbb9787-sxk4x   1/1     Running   0          122m
  ~~~
