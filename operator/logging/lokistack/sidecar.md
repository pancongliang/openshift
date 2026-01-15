### Configure and install the Sidecar log agent.


* Configure Fluent Bit to read log files and output them to stdout. The Deployment runs two containers: one application container that generates log files, and a sidecar container that collects these logs and outputs them to standard output, allowing OpenShift Logging to automatically capture them.
~~~
cat << 'EOF' | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentbit-config
data:
  fluentbit.conf: |
    [SERVICE]
        Flush        1
        Daemon       Off
        Log_Level    info

    [INPUT]
        Name        tail
        Path        /var/log/app/*.log
        DB          /var/log/app/fluentbit.db

    [OUTPUT]
        Name        stdout
        Match       *
        Format      json_lines
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: samplelog
spec:
  replicas: 1
  selector:
    matchLabels:
      app: samplelog
  template:
    metadata:
      labels:
        app: samplelog
    spec:
      containers:
        - name: samplelog
          image: registry.access.redhat.com/ubi9/ubi
          command: ["/bin/bash", "-c"]
          args:
            - |
              while true; do
                echo "$(date '+%Y-%m-%d %H:%M:%S') | Hello OpenShift" >> /var/log/app/samplelog.log
                sleep 5
              done
          volumeMounts:
            - name: app-storage
              mountPath: /var/log/app
        - name: samplelog-sidecar
          image: fluent/fluent-bit:latest
          volumeMounts:
            - name: config-volume
              mountPath: /fluent-bit/etc/fluent-bit.conf
              subPath: fluentbit.conf
            - name: app-storage
              mountPath: /var/log/app
      volumes:
        - name: app-storage
          emptyDir: {}
        - name: config-volume
          configMap:
            name: fluentbit-config
EOF
~~~
* Check the logs: the application container is not expected to produce logs directly, and the business logs should be visible on the sidecar container's standard output.
~~~
$ oc exec -it deployment/samplelog  -c samplelog -- tail -f /var/log/app/samplelog.log
2026-01-15 15:31:04 | Hello OpenShift
2026-01-15 15:31:09 | Hello OpenShift

$ oc logs -f deployment/samplelog -c samplelog
^C

$ oc logs -f deployment/samplelog -c samplelog-sidecar
{"date":1768491069.972471,"log":"2026-01-15 15:31:09 | Hello OpenShift"}
{"date":1768491074.977123,"log":"2026-01-15 15:31:14 | Hello OpenShift"}
{"date":1768491079.983688,"log":"2026-01-15 15:31:19 | Hello OpenShift"}
{"date":1768491084.988166,"log":"2026-01-15 15:31:24 | Hello OpenShift"}
{"date":1768491089.992746,"log":"2026-01-15 15:31:29 | Hello OpenShift"}
~~~
