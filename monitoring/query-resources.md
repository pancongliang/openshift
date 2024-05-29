## How to check pods resource consumption by namespace using Prometheus query?


### Get tonken and Prometheus route addresses

* Get tonken and Prometheus route addresses
  ```
  export TOKEN=$(oc whoami -t)
  export URL=$(oc get route prometheus-k8s -o jsonpath='https://{.spec.host}' -n openshift-monitoring) 

  or

  export TOKEN=$(oc sa get-token prometheus-k8s -n openshift-monitoring)
  export URL=$(oc get route prometheus-k8s -o jsonpath='https://{.spec.host}' -n openshift-monitoring)    
  ```

### Querying metrics

* Specify querying metrics
  ```
  export NAMESPACE="minio"
  export QUERY="container_memory_working_set_bytes{namespace='${NAMESPACE}'}"
  export QUERY="pod:container_cpu_usage:sum{namespace='${NAMESPACE}'}"
  export QUERY="container_cpu_usage_seconds_total{namespace='${NAMESPACE}'}"
  export QUERY="container_network_receive_bytes_total{namespace='${NAMESPACE}'}"
  export QUERY="container_network_transmit_bytes_total{namespace='${NAMESPACE}'}"
  export QUERY="pod:container_fs_usage_bytes:sum{namespace='${NAMESPACE}'}"

  export QUERY="min_over_time(pod:container_cpu_usage:sum{namespace='${NAMESPACE}'}[24h])"
  export QUERY="max_over_time(pod:container_cpu_usage:sum{namespace='${NAMESPACE}'}[24h])"  
  export QUERY="avg_over_time(pod:container_cpu_usage:sum{namespace='${NAMESPACE}'}[24h])"
  
  export PVC="minio-pvc"
  export QUERY="kubelet_volume_stats_used_bytes{persistentvolumeclaim='${PVC}'}"
  export QUERY="kubelet_volume_stats_available_bytes{persistentvolumeclaim='${PVC}'}"
  export QUERY="kubelet_volume_stats_capacity_bytes{persistentvolumeclaim='${PVC}'}"

  export NODE="worker01.ocp4.example.com"
  export QUERY="instance:node_cpu:rate:sum{instance='${NODE}'}"
  export QUERY="node_memory_MemTotal_bytes{instance='${NODE}'} - node_memory_MemAvailable_bytes{instance='${NODE}'}"

  export NODD_IP="10.74.251.58"
  export QUERY="kubelet_running_pods{instance=~'${NODD_IP}:.*'}"
  ```
  
* If `QUERY` contains special characters, need to change it to `export QUERY='query'`, and then change the variables in query to `"'$variable'"`
  ```
  # For example, the initial QUERY:
  sum(max by (device) (node_filesystem_size_bytes{instance='${NODE}', device=~"/.*"})) - sum(max by (device) (node_filesystem_avail_bytes{instance='${NODE}', device=~"/.*"}))

  # Modified QUERY
  export QUERY='sum(max by (device) (node_filesystem_size_bytes{instance="'${NODE}'", device=~"/.*"})) - sum(max by (device) (node_filesystem_avail_bytes{instance="'${NODE}'", device=~"/.*"}))'
  ```
* Customize the most recent time range  
  ```
  export RECENT_TIME_RANGE='10m' 
  export QUERY="kubelet_volume_stats_available_bytes{namespace='${NAMESPACE}'}[${RECENT_TIME_RANGE}]"
  ```

### Query metrics via [HTTP API](https://prometheus.io/docs/prometheus/latest/querying/api/#http-api)
* If `QUERY does not contain special characters`, query through the following method.
  ```
  curl -s -g -k -X GET \
       -H "Authorization: Bearer ${TOKEN}" \
       -H 'Accept: application/json' \
       "${URL}/api/v1/query?query=${QUERY}" | jq
  ```
  
* If `QUERY contains special characters`, query through the following method.
  ```
  curl -s -k -XPOST "${URL}/api/v1/query" \
       -H "Authorization: Bearer ${TOKEN}" \
       --data-urlencode "query=${QUERY}" | jq

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
