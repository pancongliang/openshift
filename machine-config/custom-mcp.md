
~~~
cat << EOF | oc apply -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfigPool
metadata:
  name: custom
spec:
  machineConfigSelector:
    matchExpressions:
      - {key: machineconfiguration.openshift.io/role, operator: In, values: [worker,custom]}
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/custom: ""
EOF
~~~
