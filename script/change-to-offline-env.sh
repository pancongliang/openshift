oc patch OperatorHub cluster --type json \
    -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'


oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=/root/offline-secret

sleep 10

#!/bin/bash
for Hostname in $(oc get nodes  -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
do
   echo "---  [$Hostname] ---"
   ssh -o StrictHostKeyChecking=no core@$Hostname sudo cat /var/lib/kubelet/config.json
   echo
done
