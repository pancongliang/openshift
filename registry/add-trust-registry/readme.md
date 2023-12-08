### Configuring additional trust stores for image registry access
* Create the registry's configmap using the image registry CA certificate

  If the registry has the port, such as registry-with-port.example.com:5000, `:` should be replaced with `..`
  ```
  export REGISTRY_DOMAIN_NAME='mirror.registry.examplpe.com'
  export REGISTRY_PORT=8443
  export REGISTRY_CERT='/etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN_NAME}.ca.crt'

  oc create configmap registry-cas \
      --from-file=${REGISTRY_DOMAIN_NAME}..${REGISTRY_PORT}=${REGISTRY_CERT} -n openshift-config
  ``` 

* Configuring additional trust
  ```
  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}' --type=merge

  oc get co |grep openshift-apiserver
  ```
  
* Check whether the certificate is updated
  ```
  #!/bin/bash
  for Hostname in $(oc get nodes  -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
  do
     echo "---  $Hostname ---"
     ssh -o StrictHostKeyChecking=no core@$Hostname sudo ls /etc/docker/certs.d/
     echo
  done
  ```

* Update registry account information to openshift
  ```
  podman login --authfile /root/offline-secret ${REGISTRY_DOMAIN_NAME}:${REGISTRY_PORT}

  oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=/root/offline-secret
  ```

* Check whether the egistry account information is updated
  ```
  #!/bin/bash
  for Hostname in $(oc get nodes  -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
  do
     echo "---  $Hostname ---"
     ssh -o StrictHostKeyChecking=no core@$Hostname sudo cat /var/lib/kubelet/config.json
     echo
  done
  ```
    > [!NOTE]  
    > 
    > If the registry used during offline installation is damaged or needs to be replaced, you need to add the following steps, otherwise the new node will prompt `x509 error`,Please note that this step will reboot all nodes.
    > 
    > ```
    >   oc edit configmap user-ca-bundle -n openshift-config
    >   apiVersion: v1
    >   data:
    >     ca-bundle.crt: |
    >       -----BEGIN CERTIFICATE-----
    >       ···                               # Replace with new regitry ca certificate
    >       -----END CERTIFICATE-----
    > 
    >   oc patch proxy/cluster --type=merge --patch='{"spec":{"trustedCA":{"name":"user-ca-bundle"}}}'
    > 
    >   ssh core@<node-name> sudo cat /etc/pki/ca-trust/source/anchors/openshift-config-user-ca-bundle.crt 
    >   ```
