### Create a test pod
~~~
oc new-project example-ex-ip
oc new-app --name example-ex-ip --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
~~~

### Change the existing svc type to externalip
~~~
export POD_NAME=$(oc get po -o=jsonpath='{.items[*].metadata.name}')
export HOST_IP=$(oc get pod $POD_NAME -o=jsonpath='{.status.hostIP}')
oc patch svc example-ex-ip -p '{"spec":{"externalIPs":["${HOST_IP}"]}}'
oc get svc
~~~

### Test external-IP service
~~~
curl $HOST_IP:8080 |grep Hello
    <h1>Hello, world from nginx!</h1>
~~~
