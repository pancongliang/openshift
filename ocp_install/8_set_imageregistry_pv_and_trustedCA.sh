# kubeconfig login:
echo export KUBECONFIG=$INSTALL_DIR/auth/kubeconfig >> /root/.bash_profile
echo export LANG=“en_US.UTF-8” >> ~/.bash_profile

# completion command:
oc completion bash >> /etc/bash_completion.d/oc_completion
source ~/.bash_profile

## Create PV:
#!/bin/bash
### Create pv and modify image-registry operator
cat << EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: image-registry
spec:
  capacity:
    storage: 100Gi
  accessModes:
  - ReadWriteMany
  nfs:
    path: /nfs/image-registry
    server: $BASTION_IP
  persistentVolumeReclaimPolicy: Retain
EOF

oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed"}}'
oc patch configs.imageregistry.operator.openshift.io/cluster --type merge --patch '{"spec":{"storage":{"pvc":{"claim":""}}}}'

### Trust the docker repository ###
oc create configmap registry-cas \
     --from-file=docker.registry.example.com..5000=/etc/pki/ca-trust/source/anchors/docker.registry.example.com.ca.crt \
     -n openshift-config

oc patch image.config.openshift.io/cluster --patch '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}' --type=merge
