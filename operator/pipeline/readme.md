### Install Pipelines Operator

* Install the Operator using the default namespace
  ```
  export CHANNEL_NAME="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/pipeline/01-operator.yaml | envsubst | oc create -f -

  sleep 20
  
  oc patch installplan $(oc get ip -n openshift-operators -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-operators --type merge --patch '{"spec":{"approved":true}}'

  oc get ip -n openshift-operators
  ```
  
### Install Tekton
* Installing the Tekton Command
  ```
  curl -L https://github.com/tektoncd/cli/releases/download/v0.29.1/tkn_0.29.1_Linux_x86_64.tar.gz | tar -xzf -
  sudo mv tkn /usr/bin/
  ```
  
### Configure OpenShift Pipeline

* Creating a Task Object
  ```
  oc new-project pipelines-tutorial

  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/pipeline/02-apply-manifest-task.yaml -n pipelines-tutorial
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/pipeline/03-update-deployment-task.yaml -n pipelines-tutorial

  # View Task Object
  oc get task -n pipelines-tutorial
  tkn task ls -n pipelines-tutorial
  ```

* Creating a Pipeline Object
  ```
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/pipeline/04-pipeline.yaml -n pipelines-tutorial

  # View Pipeline Object
  tkn pipeline ls -n pipelines-tutorial
  ```

* Running the Pipeline Object
  ```
  tkn pipeline start build-and-deploy -n pipelines-tutorial \
    -w name=shared-workspace,volumeClaimTemplateFile=https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/pipeline/05-pvc.yaml \
    -p deployment-name=pipelines-vote-api \
    -p git-url=https://github.com/openshift/pipelines-vote-api.git \
    -p IMAGE=image-registry.openshift-image-registry.svc:5000/pipelines-tutorial/pipelines-vote-api \
    --use-param-defaults
  
  tkn pipeline start build-and-deploy -n pipelines-tutorial \
    -w name=shared-workspace,volumeClaimTemplateFile=https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/pipeline/05-pvc.yaml \
    -p deployment-name=pipelines-vote-ui \
    -p git-url=https://github.com/openshift/pipelines-vote-ui.git \
    -p IMAGE=image-registry.openshift-image-registry.svc:5000/pipelines-tutorial/pipelines-vote-ui \
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
