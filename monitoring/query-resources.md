### How to check pods resource consumption by namespace using Prometheus query?

* Get tonken and Prometheus route addresses
  ```
  export TOKEN=$(oc whoami -t)

  or

  export TOKEN=$(oc sa get-token prometheus-k8s -n openshift-monitoring)
  
  export URL=$(oc get route prometheus-k8s -o jsonpath='https://{.spec.host}' -n openshift-monitoring)    
  ```
  
* Specify querying metrics
  ```
  export NAMESPACE='minio'
  export QUERY="container_memory_working_set_bytes{namespace='${NAMESPACE}'}"
  export QUERY="pod:container_cpu_usage:sum{namespace='${NAMESPACE}'}"
  export QUERY="container_cpu_usage_seconds_total{namespace='${NAMESPACE}'}"
  export QUERY="container_network_receive_bytes_total{namespace='${NAMESPACE}'}"
  export QUERY="container_network_transmit_bytes_total{namespace='${NAMESPACE}'}"
  export QUERY="pod:container_fs_usage_bytes:sum{namespace='${NAMESPACE}'}"

  export PVC='minio-pvc'
  export QUERY="kubelet_volume_stats_used_bytes{persistentvolumeclaim='${PVC}'}"
  export QUERY="kubelet_volume_stats_available_bytes{persistentvolumeclaim='${PVC}'}"
  export QUERY="kubelet_volume_stats_capacity_bytes{persistentvolumeclaim='${PVC}'}"

  export NODE='worker01.ocp4.example.com'
  export QUERY="instance:node_cpu:rate:sum{instance='${NODE}'}"
  export QUERY="node_memory_MemTotal_bytes%7Binstance%3D'${NODE}'%7D%20-%20node_memory_MemAvailable_bytes%7Binstance%3D'${NODE}'%7D"
  export QUERY="sum(max%20by%20(device)%20(node_filesystem_size_bytes%7Binstance%3D'${NODE}'%2C%20device%3D~'%2F.*'%7D))%20-%20sum(max%20by%20(device)%20(node_filesystem_avail_bytes%7Binstance%3D'${NODE}'%2C%20device%3D~'%2F.*'%7D))"

  export NODD_IP='10.74.251.58'
  export QUERY="kubelet_running_pods{instance=~'${NODD_IP}:.*'}"
  ```
* Customize the most recent time range  
  ```
  export RECENT_TIME_RANGE='10m' 
  export QUERY="kubelet_volume_stats_available_bytes{namespace='${NAMESPACE}'}[${RECENT_TIME_RANGE}]"
  export QUERY="(sum(irate(container_network_receive_bytes_total%7Bpod%3D~'.*'%2C%20namespace%3D~'${NAMESPACE}'%7D%5B${RECENT_TIME_RANGE}%5D))%20by%20(pod%2C%20namespace%2C%20interface))%20%2B%20on(namespace%2Cpod%2Cinterface)%20group_left(network_name)%20(pod_network_name_info)"
  ```
  
* Run query metrics
  ```
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

  or

  curl -G -s "${URL}/api/v1/query_range" \
     -d "${QUERY}" \
     -d "start=${START}" \
     -d "end=${END}" \
     -d "step=${INTERVAL}" \
     -H "Authorization: Bearer ${TOKEN}"
     -H 'Accept: application/json' | jq
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
