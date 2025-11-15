
#### Install Cert Manager Operator
* Install the Operator using the default namespace
  ~~~
  export SUB_CHANNEL="stable-v1"
  export CATALOG_SOURCE="redhat-operators"
  export NAMESPACE="cert-manager-operator"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/cert-manager/01-operator.yaml | envsubst | oc create -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ~~~

#### Configure a Self-Signed CA Issuer
    
* Generate a Private CA Certificate
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

* Create a Secret for the CA in cert-manager Namespace
  ~~~
  export CA_SIGNER_SECRET=example-root-ca
  export CA_CRT=rootCA.pem
  export CA_KEY=rootCA.key

  oc create secret tls -n cert-manager $CA_SIGNER_SECRET --cert=$CA_CRT --key=$CA_KEY
  ~~~

* Create a ClusterIssuer Using the Private CA
  ~~~
  export CLUSTER_ISSUER=example-ca-issuer

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

#### Create Certificate Resources

* Create a Certificate resource for the Ingress Controller
  ~~~
  export INGRESS_DOMAIN=apps.ocp.example.com
  export INGRESS_CERT_SECRET=example-router-certs
  export CERT_DURATION="2h"
  export CERT_RENEW_BEFORE="1h"

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
    renewBefore: $CERT_RENEW_BEFORE
  EOF  
  ~~~

* Verify Certificate Status and Generated TLS Secret
  ~~~
  $ oc get certificate -n openshift-ingress
    ··· Output ···
    NAME           READY   SECRET                 AGE
    ingress-cert   True    example-router-certs   21s

  $ oc get secret -n openshift-ingress $INGRESS_CERT_SECRET
    ··· Output ···
    NAME                  TYPE                 DATA   AGE
    example-router-certs   kubernetes.io/tls   3      34s
  ~~~

  
#### Replace the Default Ingress Certificate

* Create a config map that includes only the root CA certificate that is used to sign the wildcard certificate
  ~~~
  oc create configmap custom-ca --from-file=ca-bundle.crt=rootCA.pem -n openshift-config
  ~~~
  
* Update the cluster-wide proxy configuration with the newly created config map:
  ~~~
  oc patch proxy/cluster --type=merge --patch='{"spec":{"trustedCA":{"name":"custom-ca"}}}'
  ~~~

* Update the Ingress Controller configuration with the newly created secret  
  ~~~
  oc patch ingresscontroller.operator default \
  --type=json -n openshift-ingress-operator \
  -p "[{\"op\":\"replace\",\"path\":\"/spec/defaultCertificate\",\"value\":{\"name\":\"$INGRESS_CERT_SECRET\"}}]"
  ~~~

* Confirm that the cluster status has returned to normal
  ~~~
  oc get co
  oc get mcp
  oc get node
  ~~~
  
#### Verify Automatic Certificate Renewal

* Check that the Ingress Certificate Has Been Updated
  ~~~
  $ oc get certificaterequests.cert-manager.io -n openshift-ingress
  ··· Output ···
  NAME             APPROVED   DENIED   READY   ISSUER                  REQUESTER                                         AGE
  ingress-cert-1   True                True    example-clusterissuer   system:serviceaccount:cert-manager:cert-manager   5m18s    

  $ oc get po -n openshift-ingress
  ··· Output ···
  NAME                              READY   STATUS    RESTARTS   AGE
  router-default-85b58cfff6-hb5qd   1/1     Running   0          3m51s
  router-default-85b58cfff6-xl7gt   1/1     Running   0          3m19s

  $ date
  Fri Nov 14 04:32:47 PM UTC 2025
  
  $ oc get secret -n openshift-ingress $INGRESS_CERT_SECRET -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates -issuer -subject
  ··· Output ···  
  notBefore=Nov 14 16:26:28 2025 GMT
  notAfter=Nov 14 18:26:28 2025 GMT
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
  notBefore=Nov 14 16:26:28 2025 GMT
  notAfter=Nov 14 18:26:28 2025 GMT
  subject=CN = apps.ocp.example.com
  X509v3 Subject Alternative Name: 
      DNS:apps.ocp.example.com, DNS:*.apps.ocp.example.com
  ~~~

* Wait and Verify Automatic Renewal
  ~~~
  $ date
  Fri Nov 14 05:31:51 PM UTC 2025

  $ oc get certificaterequests.cert-manager.io -n openshift-ingress
  ··· Output ···
  NAME             APPROVED   DENIED   READY   ISSUER                  REQUESTER                                         AGE
  ingress-cert-1   True                True    example-clusterissuer   system:serviceaccount:cert-manager:cert-manager   65m
  ingress-cert-2   True                True    example-clusterissuer   system:serviceaccount:cert-manager:cert-manager   5m33s

  $ oc get co | grep -v "True\s*False\s*False"
  ··· Output ···  
  NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE  
  kube-apiserver                             4.16.29   True        True          False      46d     NodeInstallerProgressing: 3 nodes are at revision 35; 0 nodes have achieved new revision 36
  kube-controller-manager                    4.16.29   True        True          False      46d     NodeInstallerProgressing: 3 nodes are at revision 37; 0 nodes have achieved new revision 38
  kube-scheduler                             4.16.29   True        True          False      46d     NodeInstallerProgressing: 1 node is at revision 35; 2 nodes are at revision 36; 0 nodes have achieved new revision 37

  # The router pod will not restart during certificate renewal.
  $ oc get po -n openshift-ingress
  ··· Output ···
  NAME                              READY   STATUS    RESTARTS   AGE
  router-default-85b58cfff6-hb5qd   1/1     Running   0          64m
  router-default-85b58cfff6-xl7gt   1/1     Running   0          63m

  $ openssl s_client -connect console-openshift-console.$INGRESS_DOMAIN:443 -showcerts | openssl x509 -noout -issuer -dates -subject -ext subjectAltName
  ··· Output ···
  notBefore=Nov 14 17:26:28 2025 GMT
  notAfter=Nov 14 19:26:28 2025 GMT
  subject=CN = apps.ocp.example.com
  X509v3 Subject Alternative Name: 
    DNS:apps.ocp.example.com, DNS:*.apps.ocp.example.com

  $ oc get secret -n openshift-ingress $INGRESS_CERT_SECRET -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates -issuer -subject
  ··· Output ···
  notBefore=Nov 14 17:26:28 2025 GMT
  notAfter=Nov 14 19:26:28 2025 GMT
  issuer=CN = Test Workspace Signer
  subject=CN = apps.ocp.example.com


  $ date
  Fri Nov 14 06:34:16 PM UTC 2025

  $ oc get co | grep -v "True\s*False\s*False"
  ··· Output ···  
  NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
  kube-apiserver                             4.16.29   True        True          False      46d     NodeInstallerProgressing: 3 nodes are at revision 36; 0 nodes have achieved new revision 37
  kube-controller-manager                    4.16.29   True        True          False      46d     NodeInstallerProgressing: 2 nodes are at revision 39; 1 node is at revision 40
  kube-scheduler                             4.16.29   True        True          False      46d     NodeInstallerProgressing: 1 node is at revision 37; 2 nodes are at revision 38; 0 nodes have achieved new revision 39
  
  $ oc get certificaterequests.cert-manager.io -n openshift-ingress
  ··· Output ···  
  NAME             APPROVED   DENIED   READY   ISSUER                  REQUESTER                                         AGE
  ingress-cert-1   True                True    example-clusterissuer   system:serviceaccount:cert-manager:cert-manager   128m
  ingress-cert-2   True                True    example-clusterissuer   system:serviceaccount:cert-manager:cert-manager   68m
  ingress-cert-3   True                True    example-clusterissuer   system:serviceaccount:cert-manager:cert-manager   8m13s

  # The router pod will not restart during certificate renewal
  ··· Output ···  
  $ oc get po -n openshift-ingress
  NAME                              READY   STATUS    RESTARTS   AGE
  router-default-85b58cfff6-hb5qd   1/1     Running   0          127m
  router-default-85b58cfff6-xl7gt   1/1     Running   0          126m

  $ openssl s_client -connect console-openshift-console.$INGRESS_DOMAIN:443 -showcerts | openssl x509 -noout -issuer -dates -subject -ext subjectAltName
  ··· Output ···
  notBefore=Nov 14 18:26:28 2025 GMT
  notAfter=Nov 14 20:26:28 2025 GMT
  subject=CN = apps.ocp.example.com
  X509v3 Subject Alternative Name: 
      DNS:apps.ocp.example.com, DNS:*.apps.ocp.example.com

  $ oc get secret -n openshift-ingress $INGRESS_CERT_SECRET -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates -issuer -subject
  ··· Output ···
  notBefore=Nov 14 18:26:28 2025 GMT
  notAfter=Nov 14 20:26:28 2025 GMT
  issuer=CN = Test Workspace Signer
  subject=CN = apps.ocp.example.com


  $ date
  Sat Nov 15 10:08:34 AM UTC 2025
  
  $ oc get certificaterequests.cert-manager.io -n openshift-ingress
  ··· Output ···  
  ···
  ingress-cert-16   True                True    example-clusterissuer   system:serviceaccount:cert-manager:cert-manager   163m
  ingress-cert-17   True                True    example-clusterissuer   system:serviceaccount:cert-manager:cert-manager   103m
  ingress-cert-18   True                True    example-clusterissuer   system:serviceaccount:cert-manager:cert-manager   43m

  # The router pod will not restart during certificate renewal
  ··· Output ···  
  $ oc get po -n openshift-ingress
  NAME                              READY   STATUS    RESTARTS   AGE
  router-default-85b58cfff6-hb5qd   1/1     Running   0          17h
  router-default-85b58cfff6-xl7gt   1/1     Running   0          17h

  $ openssl s_client -connect console-openshift-console.$INGRESS_DOMAIN:443 -showcerts | openssl x509 -noout -issuer -dates -subject -ext subjectAltName
  ··· Output ···
  notBefore=Nov 15 09:26:28 2025 GMT
  notAfter=Nov 15 11:26:28 2025 GMT
  subject=CN = apps.ocp.example.com
  X509v3 Subject Alternative Name: 
      DNS:apps.ocp.example.com, DNS:*.apps.ocp.example.com

  $ oc get secret -n openshift-ingress $INGRESS_CERT_SECRET -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates -issuer -subject
  ··· Output ···
  notBefore=Nov 15 09:26:28 2025 GMT
  notAfter=Nov 15 11:26:28 2025 GMT
  issuer=CN = Test Workspace Signer
  subject=CN = apps.ocp.example.com
  ~~~
