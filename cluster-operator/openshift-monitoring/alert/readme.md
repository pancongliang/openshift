### How to test prometheus alerts for user applications

* Enable the user-workload-monitoring
  ```
  $ oc -n openshift-monitoring edit configmap cluster-monitoring-config
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: cluster-monitoring-config
    namespace: openshift-monitoring
  data:
    config.yaml: |
      techPreviewUserWorkload:
        enabled: true
  ```
* Create a test application and ServiceMonitor, PrometheusRule
  ```
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/cluster-operator/openshift-monitoring/alert/example-alert.yaml
  ```

* Test whether the service exposing custom metrics or not, it must display metrics
  ```
  $ curl -vk service_IP:8080/metrics
  promhttp_metric_handler_requests_total{code="200"} 75
  promhttp_metric_handler_requests_total{code="500"} 0
  promhttp_metric_handler_requests_total{code="503"} 0
  # HELP total_reversed_words Total number of reversed words
  # TYPE total_reversed_words counter
  total_reversed_words N
  ```

* To increase the counter, one can use the following command
  ```
  $ curl http://service_IP:8080/ -X POST -d '{"word":"abc"}'   <--- This will reverse the word and increase the counter
  $ curl -vk service_IP:8080/metrics  <-- Verify the counter
  ```
