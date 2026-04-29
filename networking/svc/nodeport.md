### Create a test pod
~~~
oc new-project example-nodeport
oc new-app --name example-nodeport --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
~~~

### Create a node-port service
~~~
cat << EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: example-ex-nodeport
  namespace: example-nodeport
spec:
  ports:
  - name: 8080-tcp
    nodePort: 30768
    port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    deployment: example-nodeport
  type: NodePort
EOF

oc -n example-nodeport get svc example-ex-nodeport
~~~

### Test node-port service
~~~
export POD_NAME=$(oc get po -n example-nodeport -o=jsonpath='{.items[*].metadata.name}')
export HOST_IP=$(oc -n example-nodeport get po $POD_NAME -o=jsonpath='{.status.hostIP}')
curl -s $HOST_IP:30768 |grep Hello
    <h1>Hello, world from nginx!</h1>

curl -I $HOST_IP:30768 
HTTP/1.1 200 OK
···
~~~
