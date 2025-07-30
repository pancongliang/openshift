### Setting Node Reboot Order During RHOCP 4 Upgrade

#### 1. Pause the worker MachineConfigPool(MCP):
~~~
$ oc patch --type=merge --patch='{"spec":{"paused":true}}' machineconfigpool/worker

$ oc get mcp worker -o yaml | grep paused
  paused: true
~~~

#### 2. Trigger a Cluster Upgrade:
~~~
$ oc patch clusterversion version --type merge -p '{"spec": {"channel": "stable-4.17"}}'
$ oc adm upgrade --to=$TARGET_VERSION --allow-not-recommended
~~~

#### 3. Verify CO Status, Only machine-config is pending upgrade:
~~~
$ oc get co | grep -v '.True.*False.*False'
NAME                                       VERSION   AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE

$ oc get co | awk -v ver="4.16.21" '$2 == ver { print $0 }'
machine-config                             4.16.21   True        True          False      104m    Working towards 4.17.30
~~~

#### 4. Verify all three master nodes are upgraded by comparing the MCP spec.configuration.name with each node's currentConfig.
~~~
$ oc get mcp master -o custom-columns=NAME:metadata.name,DESIRED:spec.configuration.name
NAME     DESIRED
master   rendered-master-14b94cd27b54d023036df6e8ead4a73c

$ oc get node -l node-role.kubernetes.io/master= \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n  currentConfig: "}{.metadata.annotations.machineconfiguration\.openshift\.io/currentConfig}{"\n  desiredConfig: "}{.metadata.annotations.machineconfiguration\.openshift\.io/desiredConfig}{"\n\n"}{end}'
copan-t7d6v-master-0
  currentConfig: rendered-master-14b94cd27b54d023036df6e8ead4a73c
  desiredConfig: rendered-master-14b94cd27b54d023036df6e8ead4a73c

copan-t7d6v-master-1
  currentConfig: rendered-master-14b94cd27b54d023036df6e8ead4a73c
  desiredConfig: rendered-master-14b94cd27b54d023036df6e8ead4a73c

copan-t7d6v-master-2
  currentConfig: rendered-master-14b94cd27b54d023036df6e8ead4a73c
  desiredConfig: rendered-master-14b94cd27b54d023036df6e8ead4a73c

$ oc get node
NAME                         STATUS   ROLES                  AGE    VERSION
copan-t7d6v-master-0         Ready    control-plane,master   100m   v1.30.12
copan-t7d6v-master-1         Ready    control-plane,master   100m   v1.30.12
copan-t7d6v-master-2         Ready    control-plane,master   100m   v1.30.12
copan-t7d6v-worker-0-6v2w9   Ready    worker                 111m   v1.29.9+5865c5b
copan-t7d6v-worker-0-g6tvq   Ready    worker                 111m   v1.29.9+5865c5b
copan-t7d6v-worker-0-qpl8q   Ready    worker                 111m   v1.29.9+5865c5b
~~~

#### 5. View the desired rendered MachineConfig spec on the worker MachineConfigPool.
~~~
$ oc get mcp worker -o custom-columns=NAME:metadata.name,DESIRED:spec.configuration.name
NAME     DESIRED
worker   rendered-worker-0de55f4f91ac087adf8eb31463bfc043
~~~

#### 6. To upgrade/restart a specific worker node, update its annotations with the new desired rendered MachineConfig.
~~~
$ oc get nodes -l node-role.kubernetes.io/worker
NAME                         STATUS   ROLES    AGE    VERSION
copan-t7d6v-worker-0-6v2w9   Ready    worker   134m   v1.29.9+5865c5b
copan-t7d6v-worker-0-g6tvq   Ready    worker   134m   v1.29.9+5865c5b
copan-t7d6v-worker-0-qpl8q   Ready    worker   134m   v1.29.9+5865c5b

$ oc get nodes copan-t7d6v-worker-0-6v2w9 -o yaml | grep Config:
    machineconfiguration.openshift.io/currentConfig: rendered-worker-3251092830c3aaaf43eb2a185f621902
    machineconfiguration.openshift.io/desiredConfig: rendered-worker-3251092830c3aaaf43eb2a185f621902

# To trigger an upgrade and restart of the node copan-t7d6v-worker-0-6v2w9, update its desiredConfig annotation to the desired rendered MachineConfig.
$ WORKER_DESIRED_CONFIG=$(oc get mcp worker -o jsonpath='{.spec.configuration.name}')
$ oc patch node copan-t7d6v-worker-0-6v2w9 -p "{\"metadata\":{\"annotations\":{\"machineconfiguration.openshift.io/desiredConfig\":\"$WORKER_DESIRED_CONFIG\"}}}" --type=merge

$ oc get nodes copan-t7d6v-worker-0-6v2w9 -o yaml | grep Config:
    machineconfiguration.openshift.io/currentConfig: rendered-worker-3251092830c3aaaf43eb2a185f621902
    machineconfiguration.openshift.io/desiredConfig: rendered-worker-0de55f4f91ac087adf8eb31463bfc043

$ oc get nodes -l node-role.kubernetes.io/worker
NAME                         STATUS                     ROLES    AGE    VERSION
copan-t7d6v-worker-0-6v2w9   Ready,SchedulingDisabled   worker   141m   v1.29.9+5865c5b
copan-t7d6v-worker-0-g6tvq   Ready                      worker   141m   v1.29.9+5865c5b
copan-t7d6v-worker-0-qpl8q   Ready                      worker   141m   v1.29.9+5865c5b

$ oc get nodes -l node-role.kubernetes.io/worker
NAME                         STATUS                        ROLES    AGE    VERSION
copan-t7d6v-worker-0-6v2w9   NotReady,SchedulingDisabled   worker   145m   v1.29.9+5865c5b
copan-t7d6v-worker-0-g6tvq   Ready                         worker   146m   v1.29.9+5865c5b
copan-t7d6v-worker-0-qpl8q   Ready                         worker   146m   v1.29.9+5865c5b

$ oc get nodes -l node-role.kubernetes.io/worker
NAME                         STATUS   ROLES    AGE    VERSION
copan-t7d6v-worker-0-6v2w9   Ready    worker   147m   v1.30.12
copan-t7d6v-worker-0-g6tvq   Ready    worker   147m   v1.29.9+5865c5b
copan-t7d6v-worker-0-qpl8q   Ready    worker   148m   v1.29.9+5865c5b

$ oc get nodes copan-t7d6v-worker-0-6v2w9 -o yaml | grep Config:
    machineconfiguration.openshift.io/currentConfig: rendered-worker-0de55f4f91ac087adf8eb31463bfc043
    machineconfiguration.openshift.io/desiredConfig: rendered-worker-0de55f4f91ac087adf8eb31463bfc043


$ WORKER_DESIRED_CONFIG=$(oc get mcp worker -o jsonpath='{.spec.configuration.name}')
$ oc patch node copan-t7d6v-worker-0-g6tvq -p "{\"metadata\":{\"annotations\":{\"machineconfiguration.openshift.io/desiredConfig\":\"$WORKER_DESIRED_CONFIG\"}}}" --type=merge
$ oc patch node copan-t7d6v-worker-0-qpl8q -p "{\"metadata\":{\"annotations\":{\"machineconfiguration.openshift.io/desiredConfig\":\"$WORKER_DESIRED_CONFIG\"}}}" --type=merge

$ oc get nodes copan-t7d6v-worker-0-g6tvq -o yaml | grep Config:
    machineconfiguration.openshift.io/currentConfig: rendered-worker-3251092830c3aaaf43eb2a185f621902
    machineconfiguration.openshift.io/desiredConfig: rendered-worker-0de55f4f91ac087adf8eb31463bfc043

$ oc get nodes copan-t7d6v-worker-0-qpl8q -o yaml | grep Config:
    machineconfiguration.openshift.io/currentConfig: rendered-worker-3251092830c3aaaf43eb2a185f621902
    machineconfiguration.openshift.io/desiredConfig: rendered-worker-0de55f4f91ac087adf8eb31463bfc043

$ oc get nodes -l node-role.kubernetes.io/worker
NAME                         STATUS                     ROLES    AGE    VERSION
copan-t7d6v-worker-0-6v2w9   Ready                      worker   150m   v1.30.12
copan-t7d6v-worker-0-g6tvq   Ready,SchedulingDisabled   worker   150m   v1.29.9+5865c5b
copan-t7d6v-worker-0-qpl8q   Ready,SchedulingDisabled   worker   150m   v1.29.9+5865c5b

$ oc get nodes -l node-role.kubernetes.io/worker
NAME                         STATUS                        ROLES                  AGE    VERSION
copan-t7d6v-worker-0-6v2w9   Ready                         worker                 154m   v1.30.12
copan-t7d6v-worker-0-g6tvq   NotReady,SchedulingDisabled   worker                 154m   v1.29.9+5865c5b
copan-t7d6v-worker-0-qpl8q   NotReady,SchedulingDisabled   worker                 154m   v1.29.9+5865c5b

$ oc get node
NAME                         STATUS   ROLES                  AGE     VERSION
copan-t7d6v-master-0         Ready    control-plane,master   3h39m   v1.30.12
copan-t7d6v-master-1         Ready    control-plane,master   3h39m   v1.30.12
copan-t7d6v-master-2         Ready    control-plane,master   3h39m   v1.30.12
copan-t7d6v-worker-0-6v2w9   Ready    worker                 3h27m   v1.30.12
copan-t7d6v-worker-0-g6tvq   Ready    worker                 3h27m   v1.30.12
copan-t7d6v-worker-0-qpl8q   Ready    worker                 3h28m   v1.30.12
~~~

#### 7. After upgrading and restarting all worker nodes one by one, unpause MCP automatic reboot:
~~~
$ oc patch --type=merge --patch='{"spec":{"paused":false}}' machineconfigpool/worker
$ oc get node
$ oc get co 
~~~
