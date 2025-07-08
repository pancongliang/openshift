### Install Pipelines Operator

* Install the Operator using the default namespace
  ```
  export CHANNEL_NAME="pipelines-1.17"
  export CATALOG_SOURCE_NAME="redhat-operators"
  export NAMESPACE="openshift-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/pipeline/01-operator.yaml | envsubst | oc create -f -
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash
  ```
  
### Install Tekton
* Installing the Tekton Command
  ```
  curl -L https://mirror.openshift.com/pub/openshift-v4/clients/pipelines/1.17.0/tkn-linux-amd64.tar.gz | tar -xzf -
  sudo mv tkn /usr/bin/
  ```
  
### Configure OpenShift Pipeline

* Creating a Task Object
  ```
  oc new-project pipelines-tutorial

  oc create -f https://raw.githubusercontent.com/openshift/pipelines-tutorial/pipelines-1.17/01_pipeline/01_apply_manifest_task.yaml -n pipelines-tutorial
  oc create -f https://raw.githubusercontent.com/openshift/pipelines-tutorial/pipelines-1.17/01_pipeline/02_update_deployment_task.yaml -n pipelines-tutorial

  # View Task Object
  oc get task -n pipelines-tutorial
  tkn task ls -n pipelines-tutorial
  ```

* Creating a Pipeline Object
  ```
  oc create -f https://raw.githubusercontent.com/openshift/pipelines-tutorial/pipelines-1.17/01_pipeline/04_pipeline.yaml -n pipelines-tutorial

  # View Pipeline Object
  tkn pipeline ls -n pipelines-tutorial
  ```

* Running the Pipeline Object
  ```
  tkn pipeline start build-and-deploy \
    -w name=shared-workspace,volumeClaimTemplateFile=https://raw.githubusercontent.com/openshift/pipelines-tutorial/pipelines-1.17/01_pipeline/03_persistent_volume_claim.yaml \
    -p deployment-name=pipelines-vote-ui \
    -p git-url=https://github.com/openshift/pipelines-vote-ui.git \
    -p IMAGE='image-registry.openshift-image-registry.svc:5000/pipelines-tutorial/pipelines-vote-ui' \
    --use-param-defaults
  
  tkn pipeline start build-and-deploy \
    -w name=shared-workspace,volumeClaimTemplateFile=https://raw.githubusercontent.com/openshift/pipelines-tutorial/pipelines-1.17/01_pipeline/03_persistent_volume_claim.yaml \
    -p deployment-name=pipelines-vote-ui \
    -p git-url=https://github.com/openshift/pipelines-vote-ui.git \
    -p IMAGE='image-registry.openshift-image-registry.svc:5000/pipelines-tutorial/pipelines-vote-ui' \
    --use-param-defaults
  ```

* View  running status
  ```  
  tkn pipeline list -n pipelines-tutorial

  oc get pipelineruns -n pipelines-tutorial

  oc get taskruns -n pipelines-tutorial

  tkn pipeline logs -f -L
  ```

* After the Pipeline is successfully executed, a Route is generated and accessed
  ```
  oc expose svc pipelines-vote-ui -n pipelines-tutorial
  ```
