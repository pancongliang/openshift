### Edge
~~~
oc new-project todo-https
oc new-app --name todo-https --image quay.io/redhattraining/todo-angular:v1.1
oc create route edge todo-https --service=todo-https --hostname=todo-https.apps.ocp4.example.com

- Use the default router ca
$ oc create route edge todo-https --service=todo-https --hostname=todo-https.apps.ocp4.example.com


- Using a custom certificate
$ oc create route edge --service=minio-tenant-1-console \
     --cert=/crts/minio-tenant-1-console-minio-tenant-1.apps.ocp4.example.com.crt \
     --key=/crts/minio-tenant-1-console-minio-tenant-1.apps.ocp4.example.com.key \
     --ca-cert=/crts/minio-tenant-1-console-minio-tenant-1.apps.ocp4.example.com.ca.crt \
     --hostname=minio-tenant-1-console-minio-tenant-1.apps.ocp4.example.com

$ curl -I -vv --cacert test.ssl.apps.ocp4.example.net.ca.crt https://test.ssl.apps.ocp4.example.net
···
*  SSL certificate verify ok.
···
~~~

### Re-encryption
~~~
$ oc new-app --name todo-http --image quay.io/redhattraining/todo-angular:v1.1

$ oc create route reencrypt --service=todo-http \
     --cert=/crts/test.ssl.apps.ocp4.example.net.crt \
     --key=/crts/test.ssl.apps.ocp4.example.net.key \
     --ca-cert=/crts/test.ssl.apps.ocp4.example.net.ca.crt \
     --hostname=test.ssl.apps.ocp4.example.net

$ curl -I -vv --cacert test.ssl.apps.ocp4.example.net.ca.crt https://test.ssl.apps.ocp4.example.net
···
*  SSL certificate verify ok.
···
~~~

**Passthrough**
~~~
$ oc create secret tls todo-certs \
    --cert /crts/test.ssl.apps.ocp4.example.net.crt \
    --key /crts/test.ssl.apps.ocp4.example.net.key

$ oc create -f todo-app-v2.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: todo-https
  labels:
    app: todo-https
    name: todo-https
spec:
  replicas: 1
  selector:
    matchLabels:
      app: todo-https
      name: todo-https
  template:
    metadata:
      labels:
        app: todo-https
        name: todo-https
    spec:
      containers:
      - resources:
          limits:
            cpu: '0.5'
        image: quay.io/redhattraining/todo-angular:v1.2
        name: todo-https
        ports:
        - containerPort: 8080
          name: todo-http
        - containerPort: 8443
          name: todo-https
        volumeMounts:
        - name: tls-certs
          readOnly: true
          mountPath: /usr/local/etc/ssl/certs
      resources:
        limits:
          memory: 64Mi
      volumes:
      - name: tls-certs
        secret:
          secretName: todo-certs
---
apiVersion: v1
kind: Service
metadata:
  labels:
    app: todo-https
    name: todo-https
  name: todo-https
spec:
  ports:
  - name: https
    port: 8443
    protocol: TCP
    targetPort: 8443
  - name: http
    port: 80
    protocol: TCP
    targetPort: 8080
  selector:
    name: todo-https

$ oc create route passthrough todo-https \
     --service todo-https --port 8443 \
     --hostname nginx-termination.apps.ocp4.example.net

$ curl -vv -I \
     --cacert /crts/test.ssl.apps.ocp4.example.net.ca.crt \
     https://test.ssl.apps.ocp4.example.net
     
...output omitted...
** Server certificate:
*  subject: O=Local Cert; CN=test.ssl.apps.ocp4.example.net
*  start date: Aug  3 07:18:15 2022 GMT
*  expire date: Jul 31 07:18:15 2032 GMT
*  subjectAltName: host "test.ssl.apps.ocp4.example.net" matched cert's "test.ssl.apps.ocp4.example.net"
*  issuer: CN=Local Red Hat CodeReady Workspaces Signer
*  SSL certificate verify ok.
...output omitted...
~~~
