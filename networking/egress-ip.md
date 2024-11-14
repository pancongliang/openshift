## Egress IP (OVN-Kubernetes)


### Install httpd
```
$ yum install -y httpd

$ sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf 

$ cat > /var/www/html/index.html << EOF
<html>
  <body>
    <h1>Hello World!</h1>
  </body>
</html>
EOF

$ systemctl restart httpd
```

### Assigning an egress IP address to a namespace
```
$ cat << EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: test-egress
  labels:
    env: prod
EOF

$ oc project test-egress
$ oc new-app --name loadtest --docker-image quay.io/redhattraining/loadtest:v1.0

$ cat << EOF | oc apply -f -
apiVersion: k8s.ovn.org/v1
kind: EgressIP
metadata:
  name: egressips-prod
spec:
  egressIPs:
  - 10.184.134.135
  - 10.184.134.136
  namespaceSelector:
    matchLabels:
      env: prod
EOF

$ oc label nodes worker01.ocp4.example.com k8s.ovn.org/egress-assignable="" 
$ oc label nodes worker02.ocp4.example.com k8s.ovn.org/egress-assignable="" 

$ oc get egressip -o yaml
···
  status:
    items:
    - egressIP: 10.184.134.135
      node: worker02.ocp4.example.com
    - egressIP: 10.184.134.136
      node: worker01.ocp4.example.com
```

### Test egress ip availability
```
$ POD_NAME=$(oc get po -n test-egress -o jsonpath='{.items[0].metadata.name}')
$ oc -n test-egress rsh $POD_NAME curl http://10.184.134.128:8080/index.html | grep Hello
    <h1>Hello World!</h1>

$ tail -10 /var/log/httpd/access_log
10.184.134.135 - - [14/Nov/2024:06:24:05 +0000] "GET /index.html HTTP/1.1" 200 60 "-" "curl/7.29.0"
10.184.134.135 - - [14/Nov/2024:06:24:23 +0000] "GET /index.html HTTP/1.1" 200 60 "-" "curl/7.29.0"
10.184.134.135 - - [14/Nov/2024:06:24:28 +0000] "GET /index.html HTTP/1.1" 200 60 "-" "curl/7.29.0"
10.184.134.136 - - [14/Nov/2024:06:24:29 +0000] "GET /index.html HTTP/1.1" 200 60 "-" "curl/7.29.0"
10.184.134.136 - - [14/Nov/2024:06:24:30 +0000] "GET /index.html HTTP/1.1" 200 60 "-" "curl/7.29.0"
10.184.134.135 - - [14/Nov/2024:06:24:31 +0000] "GET /index.html HTTP/1.1" 200 60 "-" "curl/7.29.0"
```
