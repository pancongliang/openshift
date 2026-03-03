### How to test prometheus alerts for user applications

#### Enable the user-workload-monitoring
```bash
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

#### Create a test application and ServiceMonitor, PrometheusRule
```bash
$ cat << EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: example-alert
  annotations:
    openshift.io/node-selector: ""
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reverse-words
  namespace: example-alert
  labels:
    app: reverse-words
spec:
  replicas: 1
  selector:
    matchLabels:
      app: reverse-words
  template:
    metadata:
      labels:
        app: reverse-words
    spec:
      containers:
      - name: reverse-words
        image: quay.io/mavazque/reversewords:uidtest
        ports:
        - containerPort: 8080
          name: http
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          timeoutSeconds: 2
          periodSeconds: 15
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          timeoutSeconds: 2
          periodSeconds: 15
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: reverse-words
  name: reverse-words
  namespace: example-alert
spec:
  ports:
  - port: 8080
    protocol: TCP
    targetPort: http
    name: http
  selector:
    app: reverse-words
  type: ClusterIP
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  labels:
    k8s-app: reverse-words
  name: reverse-words
  namespace: example-alert
spec:
  endpoints:
  - interval: 30s
    scrapeTimeout: 30s
    port: http
    path: /metrics
    scheme: http
  selector:
    matchLabels:
      app: "reverse-words"
---
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: example-alert
  namespace: example-alert
spec:
  groups:
  - name: example
    rules:
    - alert: WordAlert
      expr: total_reversed_words{job="reverse-words"} == 2
      labels:
        cluster:
EOF
```

#### Test whether the service exposing custom metrics or not, it must display metrics
```bash
$ curl -vk service_IP:8080/metrics
promhttp_metric_handler_requests_total{code="200"} 75
promhttp_metric_handler_requests_total{code="500"} 0
promhttp_metric_handler_requests_total{code="503"} 0
# HELP total_reversed_words Total number of reversed words
# TYPE total_reversed_words counter
total_reversed_words N
```

#### To increase the counter, one can use the following command
```bash
# This will reverse the word and increase the counter
$ curl http://service_IP:8080/ -X POST -d '{"word":"abc"}'

# Verify the counter
$ curl -vk service_IP:8080/metrics
```
