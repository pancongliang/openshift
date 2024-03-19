### Install and configure MetalLB Operator
* Clusters installed in UPI mode need to [install MetalLB](https://github.com/pancongliang/openshift/blob/main/operator/metallb/readme.md) to provide load balancing IP for `svc`.

### Create a test pod
~~~
oc new-project example-lb
oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
~~~

### Create a node-port service
~~~
cat << EOF | oc apply -f -
apiVersion: v1
kind: Service
metadata:
  name: example-ex-lb
  namespace: example-lb
spec:
  loadBalancerIP:
  loadBalancerSourceRanges:
  ports:
  - name: 8080-tcp
    port: 8080
    protocol: TCP
    targetPort: 8080
  selector:
    deployment: example-lb
  type: LoadBalancer
EOF

oc get svc example-ex-lb -n example-lb
NAME            TYPE           CLUSTER-IP      EXTERNAL-IP    PORT(S)          AGE
example-ex-lb   LoadBalancer   172.30.63.187   10.72.94.138   8080:30062/TCP   23s

# Or change the existing svc type to LoadBalancer

oc patch svc example-lb --type=merge -p '{"spec": {"type": "LoadBalancer"}}'
~~~

### Test node-port service
~~~
export LB_IP=$(oc -n example-lb get svc example-ex-lb -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')

curl -s $LB_IP:8080 |grep Hello
    <h1>Hello, world from nginx!</h1>
~~~
