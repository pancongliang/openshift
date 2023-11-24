## Kyverno
RBAC Role has no deny rules, so can use third-party software <kyverno> to deny specific users (cluster-admin role) access to openshift resources.


### Installing kyverno
* Check [compatibility](https://kyverno.io/docs/installation/#compatibility-matrix) before installing kyverno[1]
  ```
  $ oc create -f https://github.com/kyverno/kyverno/releases/download/v1.10.0/install.yaml
  ```

### Create a policy
* Create a policy that will prohibit specific users from being able to execute <oc exec/attach/rsh>
  ```
  $ oc create -f- << EOF
  apiVersion: kyverno.io/v1
  kind: ClusterPolicy
  metadata:
    name: deny-exec-by-pod-and-container
    annotations:
      policies.kyverno.io/title: Block Pod Exec by Pod and Container
      policies.kyverno.io/category: Sample
      policies.kyverno.io/minversion: 1.6.0
      policies.kyverno.io/subject: Pod
      policies.kyverno.io/description: >-
        Deny specific users from using the oc exec/rsh/attach command
  spec:
    validationFailureAction: Enforce
    background: false
    rules:
    - name: deny-exec-for-specific-users
      match:
        any:
        - resources:
            kinds:
            - Pod/exec
            - Pod/attach
      preconditions:
        all:
        - key: "{{ request.operation || 'BACKGROUND' }}"
          operator: Equals
          value: CONNECT
        - key: "{{ request.userInfo.username }}"
          operator: In
          value:
          - "user01"
          - "user02"
      validate:
        message: Users are not allowed to execute exec commands on all Pods.
        deny:
          conditions: []
  EOF

  $ oc get clusterpolicy
  NAME                             BACKGROUND   VALIDATE ACTION   READY   AGE   MESSAGE
  deny-exec-by-pod-and-container   false        Enforce           True    10s   Ready
  ```

3. Test verification
* Expected user <user01/user02> to not be able to access pod
  ```
  $ oc adm policy add-cluster-role-to-user cluster-admin user01

  $ oc whoami
  user01
  $ oc -n test exec nginx -c nginx -- date
  Error from server: admission webhook "validate.kyverno.svc-fail" denied the request: 
  resource PodExecOptions/test/ was blocked due to the following policies 
  deny-exec-by-pod-and-container:
    deny-exec-for-specific-users: Users are not allowed to execute exec commands on all Pods.

  $ oc -n test rsh -c nginx nginx date
  Error from server: admission webhook "validate.kyverno.svc-fail" denied the request: 
  resource PodExecOptions/test/ was blocked due to the following policies 
  deny-exec-by-pod-and-container:
    deny-exec-for-specific-users: Users are not allowed to execute exec commands on all Pods.

  $ oc -n test attach -it nginx -c shell 
  If you don't see a command prompt, try pressing enter.
  Error from server: admission webhook "validate.kyverno.svc-fail" denied the request: 
  resource PodAttachOptions/test/ was blocked due to the following policies 
  deny-exec-by-pod-and-container:
    deny-exec-for-specific-users: Users are not allowed to execute exec commands on all Pods.

  $ oc -n openshift-console exec console-56746b7d59-59xlg -- date
  Error from server: admission webhook "validate.kyverno.svc-fail" denied the request: 
  resource PodExecOptions/openshift-console/ was blocked due to the following policies 
  deny-exec-by-pod-and-container:
    deny-exec-for-specific-users: Users are not allowed to execute exec commands on all Pods.
  ```

* User <user03 or other user with permissions> is expected to have access to the pod
  ```
  $ oc adm policy add-cluster-role-to-user cluster-admin user01
  $ oc whoami
  user03
  $ oc -n test exec nginx -c nginx -- date
  Wed Nov 22 08:58:33 UTC 2023

  $ oc -n test rsh -c nginx nginx date
  Wed Nov 22 08:58:45 UTC 2023

  $ oc -n test attach -it nginx -c shell 
  If you don't see a command prompt, try pressing enter.
  / # 

  $ oc -n openshift-console exec console-56746b7d59-59xlg -- date
  Wed Nov 22 09:00:08 UTC 2023

  $ oc whoami
  $ oc -n test exec nginx -c nginx -- date
  Wed Nov 22 09:05:07 UTC 2023
  ```
  
* Can specify only one user using the following policy
  ```
  $ oc create -f- << EOF
  apiVersion: kyverno.io/v1
  kind: ClusterPolicy
  metadata:
    name: deny-exec-by-pod-and-container
    annotations:
      policies.kyverno.io/title: Block Pod Exec by Pod and Container
      policies.kyverno.io/category: Sample
      policies.kyverno.io/minversion: 1.6.0
      policies.kyverno.io/subject: Pod
      policies.kyverno.io/description: >-
        Deny specific users from using the oc exec/rsh/attach command
  spec:
    validationFailureAction: Enforce
    background: false
    rules:
    - name: deny-exec-for-specific-users
      match:
        any:
        - resources:
            kinds:
            - Pod/exec
            - Pod/attach
      preconditions:
        all:
        - key: "{{ request.operation || 'BACKGROUND' }}"
          operator: Equals
          value: CONNECT
        - key: "{{ request.userInfo.username }}"
          operator: Equals
          value: "user01"
      validate:
        message: Users are not allowed to execute exec commands on all Pods.
        deny:
          conditions: []
  EOF
  ```
