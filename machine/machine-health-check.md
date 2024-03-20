## Automatically replace failed OpenShift cluster nodes

### Configure Machine health checks

* View the current MachineSet and get the name of the MachineSet.
  ```
  oc get machineset -n openshift-machine-api
  MACHINESET_NAME=$(oc get machineset -n openshift-machine-api --no-headers -o custom-columns=NAME:metadata.name | grep worker)
  ```

* Create a MachineHealthCheck object
  ```
  cat << EOF | oc apply -f -
  apiVersion: machine.openshift.io/v1beta1
  kind: MachineHealthCheck
  metadata:
    name: my-machine-health-check
    namespace: openshift-machine-api
  spec:
    selector:
      matchLabels:
        machine.openshift.io/cluster-api-machine-role: worker
        machine.openshift.io/cluster-api-machine-type: worker
        machine.openshift.io/cluster-api-machineset: ${MACHINESET_NAME}
    unhealthyConditions:
      - type: Ready
        status: Unknown
        timeout: 300s
      - type: Ready
        status: 'False'
        timeout: 300s
    maxUnhealthy: 50%
  EOF
  ```

### Verify automatic replacement of failed nodes
* View the node where the application pod is located
  ```
  oc -n test-1 get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP
  POD                           STATUS    NODE                                            IP
  mysql-6ddb7bf95f-whdtk        Running   ip-10-0-7-156.ap-northeast-2.compute.internal   10.131.0.31
  nginx-5bc755d967-2lm6w        Running   ip-10-0-7-156.ap-northeast-2.compute.internal   10.131.0.29
  postgresql-5687bd8948-ss7vn   Running   ip-10-0-7-156.ap-northeast-2.compute.internal   10.131.0.30

  oc -n test-2 get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP
  POD                             STATUS    NODE                                            IP
  famous-quotes-67dc6cb8f-9xlsc   Running   ip-10-0-7-156.ap-northeast-2.compute.internal   10.131.0.33
  loadtest-cff78c6f6-6rtk7        Running   ip-10-0-75-82.ap-northeast-2.compute.internal   10.128.2.18
  todo-http-957579ff5-n84lt       Running   ip-10-0-7-156.ap-northeast-2.compute.internal   10.131.0.34
  
  ```
* Simulate worker node failure
  ```
  oc get nodes --selector=node-role.kubernetes.io/worker=
  NAME                                             STATUS   ROLES    AGE    VERSION
  ip-10-0-59-251.ap-northeast-2.compute.internal   Ready    worker   102m   v1.27.10+c79e5e2
  ip-10-0-7-156.ap-northeast-2.compute.internal    Ready    worker   103m   v1.27.10+c79e5e2
  ip-10-0-75-82.ap-northeast-2.compute.internal    Ready    worker   103m   v1.27.10+c79e5e2

  oc debug node/ip-10-0-7-156.ap-northeast-2.compute.internal
  # chroot /host
  # sudo systemctl disable kubelet.service --now
  ```

* Observe the replacement process of failed nodes
  ```
  # The status of the faulty Worker node changes to NOTReady, SchedulingDisabled
  oc get node -l node-role.kubernetes.io/worker


  # At this time, there is a new item in the Machine list, which is in the `Provisioning` stage (it will then enter the Provisioned stage);
  # and the Machine corresponding to the faulty node becomes the `Deleting` stage (then the Machine will be deleted and disappear).
  oc get machine -n openshift-machine-api -o custom-columns=NAME:metadata.name,PHASE:status.phase,STATE:status.providerStatus.instanceState,HOSTNAME:status.nodeRef.name

  # Subsequently, the Worker node corresponding to the newly created Machine will be regenerated,
  # and the status will change from `NOTReady` to `Ready`.
  # Finally, the failed Machine and Worker nodes in the cluster were restored to normal.
  oc get node -l node-role.kubernetes.io/worker


  oc get machine -n openshift-machine-api -o custom-columns=NAME:metadata.name,PHASE:status.phase,STATE:status.providerStatus.instanceState,HOSTNAME:status.nodeRef.name

  ```
  
* The application pod will be rescheduled to other normal nodes due to triggering node failover default mechanisms (when the notReady state continues for more than 5 minutes and 40 to 50 seconds)
  ```
  oc -n test-1 get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP



  oc -n test-2 get pods -o custom-columns=POD:metadata.name,STATUS:status.phase,NODE:spec.nodeName,IP:status.podIP

  ```

