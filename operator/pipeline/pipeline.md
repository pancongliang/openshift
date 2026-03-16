### Install Pipelines Operator
```bash
export SUB_CHANNEL=latest

cat << EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator-rh
  namespace: openshift-operators 
spec:
  channel: ${SUB_CHANNEL}
  installPlanApproval: "Automatic"
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```
  
###  Installing the Tekton Command
```bash
curl -L https://github.com/tektoncd/cli/releases/download/v0.43.0/tkn_0.43.0_Linux_x86_64.tar.gz | tar -xzf -
sudo mv tkn /usr/bin/
rm -rf LICENSE README.md   
```
  
### Creating a Task Object
```bash
oc new-project pipelines-tutorial
cat << 'EOF' | oc apply -n pipelines-tutorial -f -
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: apply-manifests
spec:
  workspaces:
  - name: source
  params:
    - name: manifest_dir
      description: The directory in source that contains yaml manifests
      type: string
      default: "k8s"
  steps:
    - name: apply
      image: image-registry.openshift-image-registry.svc:5000/openshift/cli:latest
      workingDir: /workspace/source
      command: ["/bin/bash", "-c"]
      args:
        - |-
          echo Applying manifests in $(inputs.params.manifest_dir) directory
          oc apply -f $(inputs.params.manifest_dir)
          echo -----------------------------------
EOF

cat << 'EOF' | oc apply -n pipelines-tutorial -f -
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: update-deployment
spec:
  params:
    - name: deployment
      description: The name of the deployment patch the image
      type: string
    - name: IMAGE
      description: Location of image to be patched with
      type: string
  steps:
    - name: patch
      image: image-registry.openshift-image-registry.svc:5000/openshift/cli:latest
      command: ["/bin/bash", "-c"]
      args:
        - |-
          oc patch deployment $(inputs.params.deployment) --patch='{"spec":{"template":{"spec":{
            "containers":[{
              "name": "$(inputs.params.deployment)",
              "image":"$(inputs.params.IMAGE)"
            }]
          }}}}'

          # issue: https://issues.redhat.com/browse/SRVKP-2387
          # images are deployed with tag. on rebuild of the image tags are not updated, hence redeploy is not happening
          # as a workaround update a label in template, which triggers redeploy pods
          # target label: "spec.template.metadata.labels.patched_at"
          # NOTE: this workaround works only if the pod spec has imagePullPolicy: Always
          patched_at_timestamp=`date +%s`
          oc patch deployment $(inputs.params.deployment) --patch='{"spec":{"template":{"metadata":{
            "labels":{
              "patched_at": '\"$patched_at_timestamp\"'
            }
          }}}}'
EOF
``` 

### View the currently created Task object
```bash  
$ oc get task -n pipelines-tutorial
NAME                AGE
apply-manifests     10s
update-deployment   10s

$ tkn task ls -n pipelines-tutorial
NAME                DESCRIPTION   AGE
apply-manifests                   15 seconds ago
update-deployment                 15 seconds ago
```

### List the existing Task templates in the openshift-pipelines namespace
```bash  
$ oc get task -n openshift-pipelines
NAME                        AGE
buildah                     21m
git-clone                   21m
···
  
$ tkn task ls -n openshift-pipelines
NAME                        DESCRIPTION              AGE
buildah                     
git-clone                   This object represe...   22 minutes ago
···
```

###  Creating a Pipeline Object
```bash
cat << 'EOF' | oc apply -n pipelines-tutorial -f -
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: build-and-deploy
spec:
  workspaces:
  - name: shared-workspace
  params:
  - name: deployment-name
    type: string
    description: name of the deployment to be patched
  - name: git-url
    type: string
    description: url of the git repo for the code of deployment
  - name: git-revision
    type: string
    description: revision to be used from repo of the code for deployment
    default: pipelines-1.21
  - name: IMAGE
    type: string
    description: image to be build from the code
  tasks:
  - name: fetch-repository
    taskRef:
      resolver: cluster
      params:
      - name: kind
        value: task
      - name: name
        value: git-clone
      - name: namespace
        value: openshift-pipelines
    workspaces:
    - name: output
      workspace: shared-workspace
    params:
    - name: URL
      value: $(params.git-url)
    - name: SUBDIRECTORY
      value: ""
    - name: DELETE_EXISTING
      value: "true"
    - name: REVISION
      value: $(params.git-revision)
  - name: build-image
    taskRef:
      resolver: cluster
      params:
      - name: kind
        value: task
      - name: name
        value: buildah
      - name: namespace
        value: openshift-pipelines
    params:
    - name: IMAGE
      value: $(params.IMAGE)
    workspaces:
    - name: source
      workspace: shared-workspace
    runAfter:
    - fetch-repository
  - name: apply-manifests
    taskRef:
      name: apply-manifests
    workspaces:
    - name: source
      workspace: shared-workspace
    runAfter:
    - build-image
  - name: update-deployment
    taskRef:
      name: update-deployment
    params:
    - name: deployment
      value: $(params.deployment-name)
    - name: IMAGE
      value: $(params.IMAGE)
    runAfter:
    - apply-manifests
EOF
```

### View the currently created Pipeline Object
```bash
$ tkn pipeline ls -n pipelines-tutorial
NAME               AGE             LAST RUN   STARTED   DURATION   STATUS
build-and-deploy   9 seconds ago   ---        ---       ---        ---
```
  
### Creating a PVC for the shared workspace used to store Git repository files
```bash 
cat > pvc.yaml << EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: source-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
EOF
```

### Start the pipeline for the back-end application
```bash  
tkn pipeline start build-and-deploy \
    -w name=shared-workspace,volumeClaimTemplateFile=pvc.yaml \
    -p deployment-name=pipelines-vote-api \
    -p git-url=https://github.com/openshift/pipelines-vote-api.git \
    -p IMAGE='image-registry.openshift-image-registry.svc:5000/pipelines-tutorial/pipelines-vote-api' \
    --use-param-defaults
```
  
### Start the pipeline for the front-end application:
```bash  
tkn pipeline start build-and-deploy \
    -w name=shared-workspace,volumeClaimTemplateFile=pvc.yaml \
    -p deployment-name=pipelines-vote-ui \
    -p git-url=https://github.com/openshift/pipelines-vote-ui.git \
    -p IMAGE='image-registry.openshift-image-registry.svc:5000/pipelines-tutorial/pipelines-vote-ui' \
    --use-param-defaults
```

### After a few minutes, use tkn pipelinerun list command to verify that the pipeline ran successfully by listing all the pipeline runs
```bash
tkn pipelinerun list -n pipelines-tutorial
oc get pipelineruns -n pipelines-tutorial
oc get taskruns -n pipelines-tutorial
tkn pipeline logs -f -L
```  

### Get the application route
```bash
oc get route pipelines-vote-ui --template='http://{{.spec.host}}'
```  

### To rerun the last pipeline run, using the pipeline resources and service account of the previous pipeline, run:
```bash
tkn pipeline start build-and-deploy --last
```  