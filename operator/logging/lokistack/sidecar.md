### Configure and install the Sidecar log agent.


* Configure Fluent Bit to read log files and output them to stdout. The Deployment runs two containers: one application container that generates log files, and a sidecar container that collects these logs and outputs them to standard output, allowing OpenShift Logging to automatically capture them.
~~~
cat << EOF | oc apply -f -
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
        Mem_Buf_Limit     5MB
        Skip_Long_Lines   On

    [OUTPUT]
        Name        stdout
        Match       *
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: samplelog
  labels:
    purpose: sample
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
          image: jtarte/logsample:latest
          imagePullPolicy: Always
          command: ["/bin/sh", "-c"]
          args:
            - |
              while true; do
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Hello OpenShift" >> /var/log/app/samplelog.log
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
$ oc logs -f deployment/samplelog -c samplelog
^C

$ oc logs -f deployment/samplelog -c samplelog-sidecar
[2026/01/15 10:47:34.384559180] [ info] [engine] Shutdown Grace Period=5, Shutdown Input Grace Period=2
[2026/01/15 10:47:34.384749577] [ info] [input:tail:tail.0] inotify_fs_add(): inode=123763632 watch_fd=1 name=/var/log/app/samplelog.log
[2026/01/15 10:47:34.386765560] [ info] [output:stdout:stdout.0] worker #0 started
[0] tail.0: [[1768474055.239296791, {}], {"log"=>"2026-01-15 10:47:23 - Hello OpenShift"}]
[0] tail.0: [[1768474060.242979862, {}], {"log"=>"2026-01-15 10:47:23 - Hello OpenShift"}]
~~~
