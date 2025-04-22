### Monitor var-lib-containers-usage
~~~
oc apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: var-lib-containers-usage
  namespace: openshift-monitoring
  labels:
    prometheus: k8s
    role: alert-rules
spec:
  groups:
  - name: disk-usage.rules
    rules:
    - alert: VarLibContainersDiskUsageHigh
      expr: 100 * (node_filesystem_size_bytes{mountpoint="/var/lib/containers"} - node_filesystem_avail_bytes{mountpoint="/var/lib/containers"}) / node_filesystem_size_bytes{mountpoint="/var/lib/containers"} > 80 and node_filesystem_size_bytes{mountpoint="/var/lib/containers"} > 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Disk usage of /var/lib/containers is high on {{ $labels.instance }}"
        description: |
          The /var/lib/containers mount on node {{ $labels.instance }} 
          is using {{ printf "%.2f" $value }}% of its capacity (threshold: 80%).
EOF
~~~

### Monitor var-lib-containers-usage
~~~
oc apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: var-lib-containers-usage
  namespace: openshift-monitoring
  labels:
    prometheus: k8s
    role: alert-rules
spec:
  groups:
  - name: disk-usage.rules
    rules:
    - alert: VarLibContainersDiskUsageHigh
      expr: 100 * (node_filesystem_size_bytes{mountpoint="/var/lib/containers",fstype!="tmpfs"} - node_filesystem_avail_bytes{mountpoint="/var/lib/containers",fstype!="tmpfs"}) / node_filesystem_size_bytes{mountpoint="/var/lib/containers",fstype!="tmpfs"} > 80
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Disk usage of /var/lib/containers is high on {{ $labels.instance }}"
        description: |
          The /var/lib/containersmount on node {{ $labels.instance }}"
          is using {{ printf "%.2f" $value }}% of its capacity (threshold: 80%).
~~~

### Monitor sysroot-disk-usage
~~~
oc apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: sysroot-disk-usage
  namespace: openshift-monitoring
  labels:
    prometheus: k8s
    role: alert-rules
spec:
  groups:
  - name: disk-usage.rules
    rules:
    - alert: SysRootDiskUsageHigh
      expr: 100 * (node_filesystem_size_bytes{mountpoint="/sysroot"} - node_filesystem_avail_bytes{mountpoint="/sysroot"}) / node_filesystem_size_bytes{mountpoint="/sysroot"} > 80
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Disk usage of /sysroot is high on {{ $labels.instance }}"
        description: |
          The /sysroot mount on node {{ $labels.instance }} 
          is using {{ printf "%.2f" $value }}% of its capacity (threshold: 70%).
EOF
~~~
