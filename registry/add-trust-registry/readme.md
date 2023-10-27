### Configuring additional trust stores for image registry access
* Create the registry's configmap using the image registry CA certificate

  If the registry has the port, such as registry-with-port.example.com:5000, `:` should be replaced with `..`
  ```
  oc create configmap registry-cas \
      --from-file=${REGISTRY_DOMAIN_NAME}..5000=/etc/pki/ca-trust/source/anchors/${REGISTRY_DOMAIN_NAME}.ca.crt -n openshift-config
  ``` 

* Configuring additional trust
  ```
  oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}' --type=merge
  ```
  
* Check whether the certificate is updated
  ```
  ssh core@<node-name> sudo ls -ltr /etc/docker/certs.d/
  ```

    > [!NOTE]  
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
