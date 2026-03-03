### Create nginx pod using configmap and secret
```bash
cat << EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: samplelog
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  nginx.conf: |
    worker_processes  1;

    events {
        worker_connections  1024;
    }

    http {
        include       /etc/nginx/mime.types;
        default_type  application/octet-stream;

        error_log /dev/null crit;

        log_format log_stdout '$time_iso8601 Hello World';

        sendfile        on;
        keepalive_timeout  65;

        server {
            listen       8080;
            server_name  localhost;

            access_log /dev/stdout log_stdout;

            location / {
                root   /usr/share/nginx/html;
                index  index.html index.htm;
            }
        }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-log-app
spec:
  replicas: 1
  selector:
    matchLabels:
      deployment: sample-log-app
  template:
    metadata:
      labels:
        deployment: sample-log-app
    spec:
      containers:
      - image: quay.io/redhattraining/hello-world-nginx:v1.0
        imagePullPolicy: IfNotPresent
        name: sample-log-app
        ports:
        - containerPort: 8080
          protocol: TCP
        volumeMounts:
        - mountPath: /etc/nginx/nginx.conf
          name: nginx-config-volume
          subPath: nginx.conf
      volumes:
      - configMap:
          name: nginx-config
        name: nginx-config-volume
---
apiVersion: v1
kind: Service
metadata:
  name: sample-log-app
  labels:
    app: sample-log-app
spec:
  ports:
  - name: 8080-tcp
    port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    deployment: sample-log-app
  type: ClusterIP
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: sample-log-app
spec:
  port:
    targetPort: 8080-tcp
  to:
    kind: Service
    name: sample-log-app
    weight: 100
  wildcardPolicy: None
EOF

export ROUTE=$(oc get route sample-log-app -n samplelog -o jsonpath='{"http://"}{.spec.host}{"\n"}')

$ curl -s ${ROUTE} |grep Hello
    <h1>Hello, world from nginx!</h1>

$ oc logs sample-log-app-d857dd4bf-lqpfv
2024-03-15T09:45:31+00:00 Hello World

# Or generate multiple logs, such as 10 logs
yum install httpd-tools
ab -n 10 -c 1 ${ROUTE}/

$ oc logs sample-log-app-d857dd4bf-wkjkk
2024-03-15T09:45:31+00:00 Hello World
2024-03-15T09:46:24+00:00 Hello World
···
~~~
