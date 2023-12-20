### How to check pods resource consumption by namespace using Prometheus query?

* Specify the namespace to be queried
  ```
  export NAMESPACE='minio'
  ```
  
* Specify querying metrics
  ```
  export QUERY="container_memory_working_set_bytes{namespace='${NAMESPACE}'}"
  export QUERY="container_cpu_usage_seconds_total{namespace='${NAMESPACE}'}"
  export QUERY="container_network_transmit_bytes_total{namespace='${NAMESPACE}'}"
  ```
* Customize the most recent time range  
  ```
  export RECENT_TIME_RANGE='10m' 
  export QUERY="kubelet_volume_stats_available_bytes{namespace='${NAMESPACE}'}[${RECENT_TIME_RANGE}]"
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

* Custom time range and interval
  ```
  export START="2023-12-20T00:00:00Z"
  export END="2023-12-20T03:00:00Z"
  export INTERVAL="15m"

  curl -s -g -k -X GET \
       -H "Authorization: Bearer ${TOKEN}" \
       -H 'Accept: application/json' \
       "${URL}/api/v1/query_range?query=${QUERY}&start=${START}&end=${END}&step=${INTERVAL}" | jq
    ```

* Change the timestamp to something human-readable
  ```
  curl -s -g -k -X GET \
       -H "Authorization: Bearer ${TOKEN}" \
       -H 'Accept: application/json' \
       "${URL}/api/v1/query_range?query=${QUERY}&start=${START}&end=${END}&step=${INTERVAL}" | jq '{
         "status": "success",
         "data": {
           "resultType": "matrix",
           "result": [.data.result[] | {metric, values: [.values[] | [(.[0] | strftime("%Y-%m-%d %H:%M:%S")), .[1]]]}]
         }
       }'
  ```

* Convert timestamp to human readable and change memory byte units to MB
  ```
  export QUERY="container_memory_working_set_bytes{namespace='${NAMESPACE}'}"
  
  curl -s -g -k -X GET \
       -H "Authorization: Bearer ${TOKEN}" \
       -H 'Accept: application/json' \
       "${URL}/api/v1/query_range?query=${QUERY}&start=${START}&end=${END}&step=${INTERVAL}" | jq '{
         "status": "success",
         "data": {
           "resultType": "matrix",
           "result": [.data.result[] | {metric, values: [.values[] | [(.[0] | strftime("%Y-%m-%d %H:%M:%S")), ((.[1] | tonumber) / 1048576 | tostring + " MB")]]}]
         }
  ```
