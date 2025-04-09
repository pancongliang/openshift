## Ingress and DNS configuration
* Every OpenShift Container Platform cluster includes a default application Ingress Controller, which must have an wildcard DNS record associated with it. By default, hosted clusters that are created by using the HyperShift KubeVirt provider automatically become a subdomain of the OpenShift Container Platform cluster that the KubeVirt virtual machines run on.


### Default Ingress and DNS Behavior
* Configuring the default ingress and DNS for hosted control planes on OpenShift Virtualization:
   > By default, OpenShift clusters include an ingress controller that requires a wildcard DNS record. When using the KubeVirt provider with HyperShift, Hosted Clusters are created as subdomains of the RHACM hub's domain.  
   > For example, if the RHACM hub uses `*.apps.ocp4.example.com` as the default ingress domain, a Hosted Cluster named `my-cluster-1` will use a subdomain like `*.apps.my-cluster-1.ocp4.example.com` when deployed with the HyperShift KubeVirt provider.
   ```
   oc patch ingresscontroller -n openshift-ingress-operator default --type=json -p '[{ "op": "add", "path": "/spec/routeAdmission", "value": {"wildcardPolicy": "WildcardsAllowed"}}]'
   ```
   > **Note:**
   > When you use the default hosted cluster ingress, connectivity is limited to HTTPS traffic over port 443. Plain HTTP traffic over port 80 is rejected. This limitation applies to only the default ingress behavior.


### Customized Ingress and DNS Behavior
* If you do not want to use the default ingress and DNS behavior, you can configure a KubeVirt hosted cluster with a unique base domain at creation time. This option requires manual configuration steps during creation and involves three main steps: cluster creation, load balancer creation, and wildcard DNS configuration.

#### Deploying a hosted cluster that specifies the base domain 
* Deploying a hosted cluster that specifies the base domain 
  ~~~
  export HOSTED_CLUSTER_NAME=example
  export PULL_SECRET="$HOME/pull-secret"
  export MEM="6Gi"
  export CPU="2"
  export WORKER_COUNT="2"
  export BASE_DOMAIN=hypershift.lab

  hcp create cluster kubevirt \
  --name $HOSTED_CLUSTER_NAME \
  --node-pool-replicas $WORKER_COUNT \
  --pull-secret $PULL_SECRET \
  --memory $MEM \
  --cores $CPU \
  --base-domain $BASE_DOMAIN
  ~~~
  
* With above configuration we will end up having a HostedCluster with an ingress wildcard configured for `*.apps.example.hypershift.lab`.

* This time, the HostedCluster will not finish the deployment (will remain in Partial progress) as we saw in the previous section, since we have configured a base domain we need to make sure that the required DNS records and load balancer are in-place:
  ~~~
  oc get --namespace clusters hostedclusters
  NAME            VERSION   KUBECONFIG                       PROGRESS   AVAILABLE   PROGRESSING   MESSAGE
  example                   example-admin-kubeconfig         Partial    True        False         The hosted control plane is available
  ~~~

* If we access the HostedCluster this is what we will see, In the next section we will fix that.
  ~~~
  hcp create kubeconfig --name $CLUSTER_NAME > $CLUSTER_NAME-kubeconfig
  
  oc --kubeconfig $CLUSTER_NAME-kubeconfig get co
  NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
  console                                    4.14.0    False       False         False      30m     RouteHealthAvailable: failed to GET route (https://console-openshift-console.apps.example.hypershift.lab): Get "https://console-openshift-console.apps.example.hypershift.lab": dial tcp: lookup console-openshift-console.apps.example.hypershift.lab on 172.31.0.10:53: no such host
  .
  ingress                                    4.14.0    True        False         True       28m     The "default" ingress controller reports Degraded=True: DegradedConditions: One or more other status conditions indicate a degraded state: CanaryChecksSucceeding=False (CanaryChecksRepetitiveFailures: Canary route checks for the default ingress controller are failing)
  ~~~

#### Set up the LoadBalancer
* Set up the load balancer service that routes ingress traffic to the KubeVirt VMs and assigns a wildcard DNS entry to the load balancer IP address.

* Get the HTTP/HTTPS node port by entering the following command:
  ~~~
  export HTTP_NODEPORT=$(oc --kubeconfig $CLUSTER_NAME-kubeconfig get services -n openshift-ingress router-nodeport-default -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
  export HTTPS_NODEPORT=$(oc --kubeconfig $CLUSTER_NAME-kubeconfig get services -n openshift-ingress router-nodeport-default -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
  ~~~
  
* Create the load balancer service by entering the following command:
  ~~~
  cat << EOF | oc apply -f -
  apiVersion: v1
  kind: Service
  metadata:
    labels:
      app: $HOSTED_CLUSTER_NAME
    name: $HOSTED_CLUSTER_NAME-apps
    namespace: clusters-$HOSTED_CLUSTER_NAME
  spec:
    ports:
    - name: https-443
      port: 443
      protocol: TCP
      targetPort: ${HTTPS_NODEPORT}
    - name: http-80
      port: 80
      protocol: TCP
      targetPort: ${HTTP_NODEPORT}
    selector:
      kubevirt.io: virt-launcher
    type: LoadBalancer
  EOF
  ~~~

#### Setting up a wildcard DNS 
* Set up a wildcard DNS record or CNAME that references the external IP of the load balancer service.

* Get the external IP address by entering the following command:
  ~~~
  export EXTERNAL_IP=$(oc -n clusters-$HOSTED_CLUSTER_NAME get service $HOSTED_CLUSTER_NAME-apps -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  ~~~

* Configure a wildcard DNS entry that references the external IP address. View the following example DNS entry:
  ~~~
  *.apps.$HOSTED_CLUSTER_NAME.$BASE_DOMAIN
  ~~~

* The DNS entry must be able to route inside and outside of the cluster.
  ~~~
  dig +short test.apps.$HOSTED_CLUSTER_NAME.$BASE_DOMAIN

  192.168.20.30  
  ~~~

* Check that hosted cluster status has moved from Partial to Completed by entering the following command:
  ~~~
  oc get --namespace clusters hostedclusters
  NAME            VERSION   KUBECONFIG                       PROGRESS    AVAILABLE   PROGRESSING   MESSAGE
  example         4.14.0    example-admin-kubeconfig         Completed   True        False         The hosted control plane is available
  ~~~


#### Configuring MetalLB 
* You must install the MetalLB Operator before you configure [MetalLB](/operator/metallb/readme.md).
