### How to check pods resource consumption by namespace using Prometheus query?

* Specify the namespace to be queried
  ```
  export NAMESPACE='minio'
  ```
* Specify querying metrics
  ```
  export QUERY="container_memory_working_set_bytes{namespace='${NAMESPACE}'}"
  export QUERY="container_cpu_usage_seconds_total{namespace='${NAMESPACE}'}"
  export QUERY="kubelet_volume_stats_available_bytes{namespace='${NAMESPACE}'}"
  export QUERY="sum(irate(container_network_receive_bytes_total{namespace='${NAMESPACE}'}[5m])) by (pod,namespace)"
  ```

* Run query metrics
  ```
  export TOKEN=$(oc sa get-token prometheus-k8s -n openshift-monitoring)
  export URL=$(oc get route prometheus-k8s -o jsonpath='https://{.spec.host}' -n openshift-monitoring)
  curl -s -g -k -X GET \
       -H "Authorization: Bearer ${TOKEN}" \
       -H 'Accept: application/json' \
       "${URL}/api/v1/query?query=${QUERY}" | jq

  or
  
  oc exec -n openshift-monitoring prometheus-k8s-0 -c prometheus -it \
    -- curl -s -XPOST "http://localhost:9090/api/v1/query" -H 'Content-Type: application/x-www-form-urlencoded' \
    -d "query=${QUERY}" | jq .
    ```
