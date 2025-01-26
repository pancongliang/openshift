## Install and configure multiclusterengine Operator

### Install multiclusterengine Operator

* Install the Operator using the default namespace
  ```
  export CHANNEL_NAME="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="multicluster-engine"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/mce/01-operator.yaml | envsubst | oc create -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```

### Create multiclusterengine custom resources
* Create Central instance
  ```
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/operator/mce/02-multiclusterengine.yaml
  ```

### Check resources
* Check  resources
  ```
  $ oc get pods -n open-cluster-management-hub
  NAME                                                        READY   STATUS    RESTARTS   AGE
  cluster-manager-addon-manager-controller-545b88f995-8wps4   1/1     Running   1          170m
  cluster-manager-addon-manager-controller-545b88f995-cgtgx   1/1     Running   1          170m
  cluster-manager-addon-manager-controller-545b88f995-ln989   1/1     Running   1          170m
  cluster-manager-placement-controller-677bd69f76-5ptsl       1/1     Running   1          170m
  cluster-manager-placement-controller-677bd69f76-frmr7       1/1     Running   1          170m
  cluster-manager-placement-controller-677bd69f76-mb2qx       1/1     Running   1          170m
  cluster-manager-registration-controller-666c744b89-fphxc    1/1     Running   1          170m
  cluster-manager-registration-controller-666c744b89-hgcrg    1/1     Running   1          170m
  cluster-manager-registration-controller-666c744b89-kpgsk    1/1     Running   1          170m
  cluster-manager-registration-webhook-54777b6d6b-dvp5x       1/1     Running   1          170m
  cluster-manager-registration-webhook-54777b6d6b-gxdlf       1/1     Running   1          170m
  cluster-manager-registration-webhook-54777b6d6b-ks2qt       1/1     Running   1          170m
  cluster-manager-work-webhook-74cfb9cb4d-djckv               1/1     Running   1          170m
  cluster-manager-work-webhook-74cfb9cb4d-g6tlp               1/1     Running   1          170m
  cluster-manager-work-webhook-74cfb9cb4d-z6mbl               1/1     Running   1          170m

  $ oc get pods -n open-cluster-management-agent
  NAME                                READY   STATUS    RESTARTS   AGE
  klusterlet-65f68df9fb-rsp8f         1/1     Running   0          11m
  klusterlet-agent-85c5754bf7-5v6jq   1/1     Running   0          11m
  klusterlet-agent-85c5754bf7-8dhsx   1/1     Running   0          11m
  oc get pods -n open-cluster-management-agent-addon
  klusterlet-agent-85c5754bf7-gngbz   1/1     Running   0          11m
  
  $ oc get pods -n open-cluster-management-agent-addon
  NAME                                                  READY   STATUS      RESTARTS   AGE
  cluster-proxy-proxy-agent-5bb6576799-x775r            3/3     Running     0          12m
  hypershift-addon-agent-6b6b99bd56-58t96               2/2     Running     0          12m
  hypershift-install-job-h7w57-l67nv                    0/1     Completed   0          12m
  klusterlet-addon-workmgr-665c6b5fcf-9xj6h             1/1     Running     0          12m
  managed-serviceaccount-addon-agent-7f47c6f868-6tfwf   1/1     Running     0          12m
  
  oc get mce -o=jsonpath='{.items[0].status.phase}'
  ```
