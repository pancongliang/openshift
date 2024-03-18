### Create a test pod
* Create a test pod
  ```
  oc new-project example-ex-ip
  oc new-app --name example-ex-ip --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
  ```

### Change the existing svc type to externalip
* Use node ip as externalIP  
  ```
  export POD_NAME=$(oc get po -o=jsonpath='{.items[*].metadata.name}')
  export HOST_IP=$(oc get pod $POD_NAME -o=jsonpath='{.status.hostIP}')
  oc patch svc example-ex-ip -p '{"spec":{"externalIPs":["${HOST_IP}"]}}'
  oc get svc
  ```

* 
  ```
  # ExternalIP address block configuration
  oc patch networks.config cluster --type=merge -p '{"spec":{"externalIP":{"autoAssignCIDRs":["10.74.251.180/30"]}}}'

  # Configure externalIP for the node
  ssh core@worker01.ocp4.example.com
  sudo -i
  sudo nmcli con mod <interface> +ipv4.addresses "10.74.251.180/21"

  cat << EOF | oc apply -f -
  apiVersion: v1
  kind: Service
  metadata:
    name: example-ex-ip
  spec:
    externalIPs:
    ports:
    - name: 8080-tcp
      port: 8080
      protocol: TCP
      targetPort: 8080
    selector:
      deployment: example-ex-ip
  EOF
  ```

### Test external-IP service
~~~
curl $HOST_IP:8080 |grep Hello
    <h1>Hello, world from nginx!</h1>
~~~
