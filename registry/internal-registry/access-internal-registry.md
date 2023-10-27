### Accessing OpenShift 4 internal registry from bastion host


* Expose internal registry route (disabled by default)
  ```
  oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
  ```

* Skip tls-verify login ocp internal registry
  ```
  HOST=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
  podman login -u admin -p $(oc whoami -t) --tls-verify=false $HOST 
  podman pull quay.io/redhattraining/hello-world-nginx:v1.0
  podman tag quay.io/redhattraining/hello-world-nginx:v1.0 default-route-openshift-image-registry.apps.ocp4.example.com/test-nginx/nginx:v1.0
  podman push default-route-openshift-image-registry.apps.ocp4.example.com/test-nginx/nginx:v1.0 --tls-verify=false
  ```

* Use the ingress ca certificate to access the ocp internal registry
  ```
  HOST=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
  oc get secret -n openshift-ingress  router-certs-default -o go-template='{{index .data "tls.crt"}}' | base64 -d | sudo tee /etc/pki/ca-trust/source/anchors/${HOST}.crt  > /dev/null
  sudo update-ca-trust enable   
  sudo podman login -u admin -p $(oc whoami -t) $HOST  
  podman push default-route-openshift-image-registry.apps.ocp4.example.com/test-nginx/nginx:v1.0
  ```


* View ocp internal registry images
  ```
  TOKEN=$(oc whoami -t)
  curl -k -H "Authorization: Bearer ${TOKEN}" "https://default-route-openshift-image-registry.apps.<cluster-name>.<domain-name>/v2/_catalog" | jq .
  curl -k -H "Authorization: Bearer ${TOKEN}" "https://default-route-openshift-image-registry.apps.<cluster-name>.<domain-name>/v2/<repository>/<image>/tags/list" | jq .
  ```
