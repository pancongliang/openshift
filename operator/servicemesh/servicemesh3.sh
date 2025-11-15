#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Applying environment variables
export STORAGE_CLASS="managed-nfs-storage"
export STORAGE_SIZE="50Gi"

cat << EOF | oc create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  labels:
    operators.coreos.com/servicemeshoperator3.openshift-operators: ""
  name: servicemeshoperator3
  namespace: openshift-operators
spec:
  channel: candidates
  installPlanApproval: Automatic
  name: servicemeshoperator3
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  startingCSV: servicemeshoperator3.v3.0.0-tp.2
EOF

oc create -f - << EOF
apiVersion: project.openshift.io/v1
kind: Project
metadata:
  labels:
    kubernetes.io/metadata.name: openshift-tempo-operator
    openshift.io/cluster-monitoring: "true"
  name: openshift-tempo-operator
EOF

oc create -f - << EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-tempo-operator
  namespace: openshift-tempo-operator
spec:
  upgradeStrategy: Default
EOF

oc create -f - << EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: tempo-product
  namespace: openshift-tempo-operator
spec:
  channel: stable
  installPlanApproval: Automatic
  name: tempo-product
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

oc create -f - << EOF
apiVersion: project.openshift.io/v1
kind: Project
metadata:
  labels:
    kubernetes.io/metadata.name: openshift-opentelemetry-operator
    openshift.io/cluster-monitoring: "true"
  name: openshift-opentelemetry-operator
EOF

oc create -f - << EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-opentelemetry-operator
  namespace: openshift-opentelemetry-operator
spec:
  upgradeStrategy: Default
EOF

oc create -f - << EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: opentelemetry-product
  namespace: openshift-opentelemetry-operator
spec:
  channel: stable
  installPlanApproval: Automatic
  name: opentelemetry-product
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

cat << EOF | oc create -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  labels:
    operators.coreos.com/kiali-ossm.openshift-operators: ""
  name: kiali-ossm
  namespace: openshift-operators
spec:
  channel: candidate
  installPlanApproval: Automatic
  name: kiali-ossm
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  startingCSV: kiali-operator.v2.1.2
EOF

cat << EOF | oc create -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kiali-monitoring-rbac
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-monitoring-view
subjects:
- kind: ServiceAccount
  name: kiali-service-account
  namespace: istio-system
EOF

# Wait for Service Mesh Operator deployment
servicemesh_deployment=$(oc get deployment -n openshift-operators -o name 2>/dev/null | grep servicemesh-operator3)
while [ -z "${servicemesh_deployment}" ]; do
    sleep 2
    servicemesh_deployment=$(oc get deployment -n openshift-operators -o name 2>/dev/null | grep servicemesh-operator3)
done

# Wait for openshift-tempo-operator Operator deployment
tempo_deployment=$(oc get deployment -n openshift-tempo-operator -o name 2>/dev/null | grep tempo)
while [ -z "${tempo_deployment}" ]; do
    sleep 2
    tempo_deployment=$(oc get deployment -n openshift-tempo-operator -o name 2>/dev/null | grep tempo)
done

# Wait for opentelemetry Operator deployment
opentelemetry_deployment=$(oc get deployment -n openshift-opentelemetry-operator -o name 2>/dev/null | grep opentelemetry)
while [ -z "${opentelemetry_deployment}" ]; do
    sleep 2
    opentelemetry_deployment=$(oc get deployment -n openshift-opentelemetry-operator -o name 2>/dev/null | grep opentelemetry)
done

# Wait for Kiali Operator deployment
kiali_deployment=$(oc get deployment -n openshift-operators -o name 2>/dev/null | grep kiali)
while [ -z "${kiali_deployment}" ]; do
    sleep 2
    kiali_deployment=$(oc get deployment -n openshift-operators -o name 2>/dev/null | grep kiali)
done

echo "waiting for operator deployments to start..."
for op in ${servicemesh_deployment} ${kiali_deployment}; do
    echo -n "waiting for ${op} to be ready..."
    
    readyReplicas=""
    
    while [ -z "$readyReplicas" ] || [ "$readyReplicas" = "0" ]; do
        sleep 1
        echo -n '.'
        readyReplicas="$(oc get ${op} -n openshift-operators -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
    done
    
    echo "done"
done

echo "waiting for operator deployments to start..."
for op in ${tempo_deployment}; do
    echo -n "waiting for ${op} to be ready..."
    
    readyReplicas=""
    
    while [ -z "$readyReplicas" ] || [ "$readyReplicas" = "0" ]; do
        sleep 1
        echo -n '.'
        readyReplicas="$(oc get ${op} -n openshift-tempo-operator -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
    done
    
    echo "done"
done

echo "waiting for operator deployments to start..."
for op in ${opentelemetry_deployment}; do
    echo -n "waiting for ${op} to be ready..."
    
    readyReplicas=""
    
    while [ -z "$readyReplicas" ] || [ "$readyReplicas" = "0" ]; do
        sleep 1
        echo -n '.'
        readyReplicas="$(oc get ${op} -n openshift-opentelemetry-operator -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
    done
    
    echo "done"
done

cat << EOF | oc create -f -
apiVersion: v1
kind: Namespace
metadata:
  name: istio-system
spec:
EOF

cat << EOF | oc create -f -
apiVersion: sailoperator.io/v1alpha1
kind: Istio
metadata:
  name: default
spec:
  namespace: istio-system
  updateStrategy:
    inactiveRevisionDeletionGracePeriodSeconds: 30
    type: InPlace
  version: v1.24.1
EOF

cat << EOF | oc create -f -
apiVersion: v1
kind: Namespace
metadata:
  name: istio-cni
spec:
EOF

cat << EOF | oc create -f -
apiVersion: sailoperator.io/v1alpha1
kind: IstioCNI
metadata:
  name: default
spec:
  namespace: istio-cni
  version: v1.24.1
EOF

oc label namespace istio-system istio-discovery=enabled

cat << EOF | oc replace -f -
apiVersion: sailoperator.io/v1alpha1
kind: Istio
metadata:
  name: default
spec:
  namespace: istio-system
  updateStrategy:
    inactiveRevisionDeletionGracePeriodSeconds: 30
    type: InPlace
  version: v1.24.1
  values:
    meshConfig:
      discoverySelectors:
        - matchLabels:
            istio-discovery: enabled
EOF

echo -n "waiting for istio_instance to fully install ..."
istio_instance=$(oc get istio default -n istio-system 2>/dev/null | grep Healthy)

while [ -z "${istio_instance}" ]; do
    echo -n '.'
    sleep 5
    istio_instance=$(oc get istio default -n istio-system 2>/dev/null | grep Healthy)
done

echo "done."

echo -n "waiting for istio_instance to fully install ..."
istiocni_instance=$(oc get istiocni default -n istio-cni 2>/dev/null | grep Healthy)

while [ -z "${istiocni_instance}" ]; do
    echo -n '.'
    sleep 5
    istiocni_instance=$(oc get istiocni default -n istio-cni 2>/dev/null | grep Healthy)
done

echo "done."

cat << EOF | oc create -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: istiod-monitor
  namespace: istio-system
spec:
  targetLabels:
  - app
  selector:
    matchLabels:
      istio: pilot
  endpoints:
  - port: http-monitoring
    interval: 30s
EOF

cat << EOF | oc create -f -
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: istio-proxies-monitor
  namespace: istio-system 
spec:
  selector:
    matchExpressions:
    - key: istio-prometheus-ignore
      operator: DoesNotExist
  podMetricsEndpoints:
  - path: /stats/prometheus
    interval: 30s
    relabelings:
    - action: keep
      sourceLabels: ["__meta_kubernetes_pod_container_name"]
      regex: "istio-proxy"
    - action: keep
      sourceLabels: ["__meta_kubernetes_pod_annotationpresent_prometheus_io_scrape"]
    - action: replace
      regex: (\d+);(([A-Fa-f0-9]{1,4}::?){1,7}[A-Fa-f0-9]{1,4})
      replacement: '[$2]:$1'
      sourceLabels: ["__meta_kubernetes_pod_annotation_prometheus_io_port","__meta_kubernetes_pod_ip"]
      targetLabel: "__address__"
    - action: replace
      regex: (\d+);((([0-9]+?)(\.|$)){4})
      replacement: '$2:$1'
      sourceLabels: ["__meta_kubernetes_pod_annotation_prometheus_io_port","__meta_kubernetes_pod_ip"]
      targetLabel: "__address__"
    - action: labeldrop
      regex: "__meta_kubernetes_pod_label_(.+)"
    - sourceLabels: ["__meta_kubernetes_namespace"]
      action: replace
      targetLabel: namespace
    - sourceLabels: ["__meta_kubernetes_pod_name"]
      action: replace
      targetLabel: pod_name
EOF

cat << EOF | oc create -f -
apiVersion: v1
kind: Namespace
metadata:
  name: minio
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: minio
spec:
  selector:
    matchLabels:
      app: minio
  replicas: 1
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: quay.io/minio/minio:latest
        command:
        - /bin/bash
        - -c
        args: 
        - minio server /data --console-address :9090
        volumeMounts:
        - mountPath: /data
          name: minio-pvc # Corresponds to the `spec.volumes` Persistent Volume
      volumes:
      - name: minio-pvc
        persistentVolumeClaim:
          claimName: minio-pvc
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-pvc
  namespace: minio
spec:
  storageClassName: ${STORAGE_CLASS}
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${STORAGE_SIZE}
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: minio
spec:
  selector:
    app: minio
  ports:
    - name: 9090-tcp
      protocol: TCP
      port: 9090
      targetPort: 9090
    - name: 9000-tcp
      protocol: TCP
      port: 9000
      targetPort: 9000
---
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: minio-console
  namespace: minio
  labels:
    app: minio
spec:
  to:
    kind: Service
    name: minio
  port:
    targetPort: 9090
---
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: minio
  namespace: minio
  labels:
    app: minio
spec:
  to:
    kind: Service
    name: minio
  port:
    targetPort: 9000
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio-client
  namespace: minio
spec:
  replicas: 1
  selector:
    matchLabels:
      deployment: minio-client
  template:
    metadata:
      labels:
        deployment: minio-client
    spec:
      containers:
      - name: minio-client
        image: docker.io/minio/mc:latest
        command: ["tail", "-f", "/dev/null"]
        env:
        - name: MC_CONFIG_DIR
          value: "/tmp/.mc"
        volumeMounts:
        - mountPath: /tmp/.mc
          name: mc-config
      volumes:
      - name: mc-config
        emptyDir: {}
EOF

# Wait for Minio pods to be in 'Running' state
MAX_RETRIES=60
SLEEP_INTERVAL=2
progress_started=false
retry_count=0
pod_name=minio

while true; do
    # Get the status of all pods
    output=$(oc get po -n minio --no-headers 2>/dev/null | awk '{print $2, $3}' || true)
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for $pod_name pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep "$SLEEP_INTERVAL"
        retry_count=$((retry_count + 1))

        # Exit the loop when the maximum number of retries is exceeded
        if [[ $retry_count -ge $MAX_RETRIES ]]; then
            echo "]"
            echo "failed: [reached max retries, $pod_name pods may still be initializing]"
            exit 1 
        fi
    else
        # Close the progress indicator and print the success message
        if $progress_started; then
            echo "]"
        fi
        echo "ok: [all $pod_name pods are in 'running' state]"
        break
    fi
done

# Get Minio route URL
export BUCKET_HOST=$(oc get route minio -n minio -o jsonpath='http://{.spec.host}')
run_command "[minio route host: $BUCKET_HOST]"

sleep 20

# Set Minio client alias
oc rsh -n minio deployments/minio mc alias set my-minio ${BUCKET_HOST} minioadmin minioadmin >/dev/null 2>&1
run_command "[configured minio client alias]"

# Create buckets for Loki, Quay, OADP, and MTC
oc rsh -n minio deployments/minio mc --no-color rb --force my-minio/tempo >/dev/null 2>&1 || true
oc rsh -n minio deployments/minio mc --no-color mb my-minio/tempo >/dev/null 2>&1
run_command "[created bucket: quay-bucket]"

echo "ok: [minio default id/pw: minioadmin/minioadmin]"

cat << EOF | oc create -f -
apiVersion: v1
kind: Namespace
metadata:
  name: tempo
spec:
EOF

cat << EOF | oc create -f -
apiVersion: v1
kind: Secret
metadata:
  name: minio-test
  namespace: tempo
stringData:
  endpoint: $BUCKET_HOST
  bucket: tempo
  access_key_id: minioadmin
  access_key_secret: minioadmin
type: Opaque
EOF

cat << EOF | oc apply -f -
apiVersion: tempo.grafana.com/v1alpha1
kind: TempoStack
metadata:
  name: sample
  namespace: tempo
spec:
  storageSize: 10Gi
  storage:
    secret: 
      name: minio-test
      type: s3
  template:
    queryFrontend:
      jaegerQuery:
        enabled: true
        ingress:
          route:
            termination: edge
          type: route
EOF

# Wait for Minio pods to be in 'Running' state
progress_started=false
while true; do
    # Get the status of all pods
    output=$(oc get po -n tempo --no-headers | grep -v query-frontend | awk '{print $2, $3}')
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 2
    else
        # Close the progress indicator and print the success message
        echo "]"
        echo "ok: [tempo-sample pods are in 'running' state]"
        break
    fi
done

# Wait for Minio pods to be in 'Running' state
progress_started=false
while true; do
    # Get the status of all pods
    output=$(oc get po -n tempo --no-headers | grep query-frontend | awk '{print $2, $3}')
    
    # Check if any pod is not in the "4/4 Running" state
    if echo "$output" | grep -vq "4/4 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 2
    else
        # Close the progress indicator and print the success message
        echo "]"
        echo "ok: [query-frontend pods are in 'running' state]"
        break
    fi
done

cat << EOF | oc create -f -
kind: OpenTelemetryCollector
apiVersion: opentelemetry.io/v1beta1
metadata:
  name: otel
  namespace: istio-system
spec:
  observability:
    metrics: {}
  deploymentUpdateStrategy: {}
  config:
    exporters:
      otlp:
        endpoint: 'tempo-sample-distributor.tempo.svc.cluster.local:4317'
        tls:
          insecure: true
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: '0.0.0.0:4317'
          http: {}
    service:
      pipelines:
        traces:
          exporters:
            - otlp
          receivers:
            - otlp
EOF

# Wait for Minio pods to be in 'Running' state
progress_started=false
while true; do
    # Get the status of all pods
    output=$(oc get po -n istio-system --no-headers | grep otel-collector | awk '{print $2, $3}')
    
    # Check if any pod is not in the "1/1 Running" state
    if echo "$output" | grep -vq "1/1 Running"; then
        # Print the info message only once
        if ! $progress_started; then
            echo -n "info: [waiting for pods to be in 'running' state"
            progress_started=true  # Set to true to prevent duplicate messages
        fi
        
        # Print progress indicator (dots)
        echo -n '.'
        sleep 2
    else
        # Close the progress indicator and print the success message
        echo "]"
        echo "ok: [otel-collector pods are in 'running' state]"
        break
    fi
done

cat << EOF | oc replace -f -
apiVersion: sailoperator.io/v1alpha1
kind: Istio
metadata:
  name: default
spec:
  namespace: istio-system
  updateStrategy:
    inactiveRevisionDeletionGracePeriodSeconds: 30
    type: InPlace
  version: v1.24.1
  values:
    meshConfig:
      discoverySelectors:
        - matchLabels:
            istio-discovery: enabled
      enableTracing: true
      extensionProviders:
      - name: otel
        opentelemetry:
          port: 4317
          service: otel-collector.istio-system.svc.cluster.local 
EOF

cat << EOF | oc apply -f -
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: otel-demo
  namespace: istio-system
spec:
  tracing:
    - providers:
        - name: otel
      randomSamplingPercentage: 100
EOF

cat << EOF | oc apply -f -
apiVersion: kiali.io/v1alpha1
kind: Kiali
metadata:
  name: kiali-user-workload-monitoring
  namespace: istio-system
spec:
  external_services:
    prometheus:
      auth:
        type: bearer
        use_kiali_token: true
      thanos_proxy:
        enabled: true
      url: https://thanos-querier.openshift-monitoring.svc.cluster.local:9091
EOF

export JAEGER_UI_HOST=$(oc get route tempo-sample-query-frontend -n tempo -o jsonpath='https://{.spec.host}')

cat << EOF > kiali_cr.yaml
spec:
  external_services:
    tracing:
      enabled: true 
      provider: tempo
      use_grpc: false
      in_cluster_url: http://tempo-sample-query-frontend.tempo:3200
      url: $JAEGER_UI_HOST
EOF

oc patch -n istio-system kiali kiali-user-workload-monitoring --type merge -p "$(cat kiali_cr.yaml)"
rm -rf  kiali_cr.yaml

# install bookinfo
echo "success, deploying bookinfo..."
cat << EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: bookinfo
spec:
EOF

oc label namespace bookinfo istio-discovery=enabled istio-injection=enabled
oc label namespace bookinfo istio.io/rev=default-v1-23-0
oc apply -f https://raw.githubusercontent.com/istio/istio/release-1.23/samples/bookinfo/platform/kube/bookinfo.yaml -n bookinfo
oc exec "$(oc get pod -l app=ratings -n bookinfo -o jsonpath='{.items[0].metadata.name}')" -c ratings -n bookinfo -- curl -sS productpage:9080/productpage | grep -o "<title>.*</title>"
oc exec -it -n bookinfo deployments/productpage-v1 -c istio-proxy -- curl localhost:9080/productpage
oc apply -f https://raw.githubusercontent.com/istio-ecosystem/sail-operator/main/chart/samples/ingress-gateway.yaml -n bookinfo
oc apply -f https://raw.githubusercontent.com/istio/istio/release-1.23/samples/bookinfo/networking/bookinfo-gateway.yaml -n bookinfo
oc expose service istio-ingressgateway -n bookinfo
oc get crd gateways.gateway.networking.k8s.io &> /dev/null ||  { oc kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.0.0" | oc apply -f -; }
oc apply -f https://raw.githubusercontent.com/istio/istio/release-1.23/samples/bookinfo/gateway-api/bookinfo-gateway.yaml -n bookinfo
oc wait --for=condition=programmed gtw bookinfo-gateway -n bookinfo
export INGRESS_HOST=$(oc get gtw bookinfo-gateway -n bookinfo -o jsonpath='{.status.addresses[0].value}')
export INGRESS_PORT=$(oc get gtw bookinfo-gateway -n bookinfo -o jsonpath='{.spec.listeners[?(@.name=="http")].port}')
export GATEWAY_URL=$INGRESS_HOST:$INGRESS_PORT

echo "service mesh and bookinfo has been deployed!"
echo "test the bookinfo application out at: http://${GATEWAY_URL}/productpage"
