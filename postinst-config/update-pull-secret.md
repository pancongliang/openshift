
### Download the pull-secret in the current environment
~~~
oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 -d > pull-secret 
~~~


### Add mirror registry credential to the cluster global pull-secret:
~~~
podman login --authfile pull-secret mirror.registry.example.com:8443

oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret
~~~

### Verify the node to update the pull-secret
~~~
#!/bin/bash
for Hostname in $(oc get nodes  -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
do
   echo "--- [$Hostname] ---"
   ssh -o StrictHostKeyChecking=no core@$Hostname sudo cat /var/lib/kubelet/config.json
   echo
done
~~~
