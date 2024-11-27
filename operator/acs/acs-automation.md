
### 1.Download Github repository
~~~
git clone https://github.com/liuxiaoyu-git/acs-automation.git
~~~

### 2.Deploy Pipeline resources
~~~
oc new-project rox-ctl-pipeline
cd acs-automation/ci/OpenShift-Pipelines
oc apply -f Tasks/
oc apply -f Pipeline/
~~~

### 3. Creating a Continuous Integration
~~~
1. RHACS Console -> Platform Configuratio -> Integrations -> StackRox API Token -> Token name: pipeline-token -> Role: Continuous Integration -> Generate

2. Copying a String
~~~ 

### 4.Create a secret based on the PIPELINE-TOKEN obtained earlier
~~~
export PIPELINE_TOKEN=

oc create secret generic acs-secret -n rox-ctl-pipeline \
	--from-literal=acs_central_endpoint=$(oc get route central -n stackrox --template='{{ .spec.host }}'):443 \
	--from-literal=acs_api_token=$PIPELINE_TOKEN
~~~

### 5.Run PipelineRun
~~~
oc create -f PipelineRun/
~~~

### 6.Check the running status of PipelineRun
* Check the running status of PipelineRun in the OpenShift console to confirm that all PipelineRuns can be successfully executed.
~~~
OpenShift Console ->

# Check the execution log of the "resource-deployment-check" task and confirm that the last display is "Setting overall result to pass".
# This means that the default PipelineRun only needs RHACS to check "ci/OpenShift-Pipelines/assets-for-validation/namespace.yaml",
# so it can pass the security test.
~~~

### 7.Modify acs-pipelineRun.yaml
* Modify the local "ci/OpenShift-Pipelines/PipelineRun/acs-pipelineRun.yaml" file and change the following "fasle" to "true".
~~~
 - name: recursive-search
   value: "true"
~~~

### 8.Execute the command again to run the PipelineRun
~~~
oc create -f PipelineRun/
~~~

### 9.Check the running status of PipelineRun
* Then check the running status of PipelineRun in the OpenShift console and confirm that PipelineRun has only completed the second task. You can check the execution log of the "rox-deployment-check" task and confirm that "assets-for-validation/layer1/layer1-service.yaml", "assets-for-validation/layer1/pod.yml", and "assets-for-validation/layer1/layer1.yaml" all contain violations, which ultimately leads to "Setting overall result to fail".
~~~
Getting roxctl
Deployment check on file : /files/ci/Tekton/Scenario2/assets-for-validation/namespace.yaml
Flag --json has been deprecated, use the new output format which also offers JSON. NOTE: The new output format's structure has changed in a non-backward compatible way.
 -- No errors found in this file --
 
Deployment check on file : /files/ci/Tekton/Scenario2/assets-for-validation/layer1/layer1-service.yaml
Flag --json has been deprecated, use the new output format which also offers JSON. NOTE: The new output format's structure has changed in a non-backward compatible way.
6 alerts found ...
  Alert policy name : Latest tag
  Description : Alert on deployments with images using tag 'latest'
  Rationale   : Using latest tag can result in running heterogeneous versions of code. Many Docker hosts cache the Docker images, which means newer versions of the latest tag will not be picked up. See https://docs.docker.com/develop/dev-best-practices for more best practices.
  Remediation : Consider moving to semantic versioning based on code releases (semver.org) or using the first 12 characters of the source control SHA. This will allow you to tie the Docker image to the code.
  -- Policy violations will not stop the build process --
。。。。

-----------------------------------------------------
Deployment check on file : /files/ci/Tekton/Scenario2/assets-for-validation/layer1/pod.yml
Flag --json has been deprecated, use the new output format which also offers JSON. NOTE: The new output format's structure has changed in a non-backward compatible way.
5 alerts found ...
  Alert policy name : Pod Service Account Token Automatically Mounted
  Description : Protect pod default service account tokens from compromise by minimizing the mounting of the default service account token to only those pods whose application requires interaction with the Kubernetes API.
  Rationale   : By default, Kubernetes automatically provisions a service account for each pod and mounts the secret at runtime. This service account is not typically used. If this pod is compromised and the compromised user has access to the service account, the service account could be used to escalate privileges within the cluster. To reduce the likelihood of privilege escalation this service account should not be mounted by default unless the pod requires direct access to the Kubernetes API as part of the pods functionality.
  Remediation : Add `automountServiceAccountToken: false` or a value distinct from 'default' for the `serviceAccountName` key to the deployment's Pod configuration.
  -- Policy violations will not stop the build process --
。。。。

 -----------------------------------------------------
Deployment check on file : /files/ci/OpenShift-Pipelines/assets-for-validation/layer1/layer1-service.yaml
Flag --json has been deprecated, use the new output format which also offers JSON. NOTE: The new output format's structure has changed in a non-backward compatible way.
  -- No errors found in this file --

Setting overall result to fail
~~~
