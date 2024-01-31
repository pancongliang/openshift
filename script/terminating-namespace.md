#### Delete the namespace in Terminating state


* Terminal-1
  ```
  oc proxy
  ```

* Terminal-2
  ```
  export NAMESPACE=openshift-gitops
  oc get namespace $NAMESPACE -o json > tmp1.json
  jq '.spec.finalizers = []' tmp1.json > tmp.json
  curl -k -H "Content-Type: application/json" -X PUT --data-binary @tmp.json http://127.0.0.1:8001/api/v1/namespaces/$NAMESPACE/finalize
  rm -rf tmp1.json tmp.json
  oc get ns | grep $NAMESPACE
  ```
