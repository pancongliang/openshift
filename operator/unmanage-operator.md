### Unmanage operators

* Unmanage all operators
  ```
  oc scale --replicas 0 -n openshift-cluster-version deployments/cluster-version-operator
  ```

* Unmanage specified operators
  ```
  oc edit clusterversion version
  ···
  spec:
  ···
    overrides:
    - group: apps
      kind: Deployment
      name: cluster-monitoring-operator
      namespace: openshift-monitoring
      unmanaged: true
    - group: apps
      kind: Deployment
      name: prometheus-operator
      namespace: openshift-monitoring
      unmanaged: true
  ```

* After setting unmanage, change the number of specific operator deployment replicas to 0
  ```  
  oc scale --replicas=0 -n openshift-monitoring deployment.apps/prometheus-operator
  oc scale --replicas=0 -n openshift-monitoring deployment.apps/cluster-monitoring-operator
  ```
