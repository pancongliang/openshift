## Deploy Applications Using Argo CD

* In GitOps, Argo CD has its own RBAC management strategy that has nothing to do with OCP. 
  OCP only provides authentication identities, and all related permissions are managed by its own Argo CD RBAC.
* The following test contains the steps to deploy a Spring Boot application using Argo CD and how to configure Argo CD RBAC to align with OCP projects.


### Install GitOps Operator

* Install the Operator using the default namespace
  ```
  export CHANNEL_NAME="latest"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/gitops/01-deploy-operator.yaml | envsubst | oc apply -f -

  oc patch installplan $(oc get ip -n openshift-operators  -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-operators --type merge --patch '{"spec":{"approved":true}}'

  oc get ip -n openshift-operators

  oc get pods -n openshift-gitops
  oc get pods -n openshift-gitops-operator
  ```

### Access control and user management

* Argo CD controls access to resources through RBAC policies set in the Argo CD instance. So first get the admin role for Argo CD
  ```
  oc edit argocd openshift-gitops -n openshift-gitops
    rbac:
      policy: |
        g, system:cluster-admins, role:admin     #<-- "system:cluster-admins" group has "role:admin"
        g, cluster-admins, role:admin
      scopes: '[groups]

  oc adm groups new cluster-admins
  oc adm groups add-users cluster-admins admin
  ```

* Create groups for users and assign openshift project-admin role to the groups.
  ```
  oc adm groups new spring-dev-group
  oc adm groups new spring-prod-group

  oc adm groups add-users spring-dev-group user01
  oc adm groups add-users spring-prod-group user02

  oc adm policy add-role-to-group admin spring-dev-group -n spring-dev
  oc adm policy add-role-to-group admin spring-prod-group -n spring-prod

  oc get group
  NAME                USERS
  cluster-admins      admin
  spring-dev-group    user01
  spring-prod-group   user02
  ```

* Add RBAC policy in Argo CD, More policy reference [RBAC Resources and Actions](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/#basic-built-in-roles).
  ```
  oc edit argocd openshift-gitops -n openshift-gitops
  spec:
    rbac:
      defaultPolicy: ""                       #(1)
      policy: |
        g, system:cluster-admins, role:admin
        g, cluster-admins, role:admin
        g, spring-dev-group, role:all-actions-dev     #(2)
        g, spring-prod-group, role:all-actions-prod   #(2)
        p, role:all-actions-dev, applications, *, spring-dev/*, allow     #(3)
        p, role:all-actions-prod, applications, *, spring-prod/*, allow   #(4)
      scopes: '[groups]'
  ```
  - (1) ArgoCD has ReadOnly permission for all members by default. Remove the default permission.
  - (2) Specify the ocp group and specify the role name for subsequent creation of policies.
  - (3) Members of the "spring-dev-group" group can have view/edit/update/delete permissions on "spring-dev applications".
  - (4) Members of the "spring-prod-group" group can have view/edit/update/delete permissions on "spring-prod applications".



### Deploying a Spring Boot application with Argo CD

* Create test namespaces that host the application load and label them to indicate that the projects are managed by openshift-gitops.
  ```
  oc new-project spring-dev
  oc label namespace spring-dev argocd.argoproj.io/managed-by=openshift-gitops

  oc new-project spring-prod
  oc label namespace spring-prod argocd.argoproj.io/managed-by=openshift-gitops
  ```

* Get the Argo CD UI url with the following commend, then select the `LOG IN VIA OPENSHIFT` option and log in with a user in the "cluster-admins" group.
  ```
  oc get route openshift-gitops-server -o jsonpath='{.spec.host}' -n openshift-gitops
  ```
  
* Create spring-dev AppProject.
  ```
  cat << EOF | oc apply -f -
  apiVersion: argoproj.io/v1alpha1
  kind: AppProject
  metadata:
    name: spring-dev
    namespace: openshift-gitops
  spec:
    sourceRepos:
    - '*'
  EOF
  ```

* Create a spring-prod AppProject and limit the deployment location(namespace) of the application.
  ```
  cat << EOF | oc apply -f -
  apiVersion: argoproj.io/v1alpha1
  kind: AppProject
  metadata:
    name: spring-prod
    namespace: openshift-gitops
  spec:
    sourceRepos:
    - 'spring-prod'
  EOF
  ```
  ```
  oc get appproject -n openshift-gitops
  NAME          AGE
  default       12h
  spring-dev    9m17s
  spring-prod   7m49s
  ```

* Create an application and verify that the application load is generated in the specified ocp project managed by openshift-gitops.
  - Create an "application" with a member of the "spring-dev-group" group.
  ```
   cat << EOF | oc apply -f -
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: spring-dev-app1
    namespace: openshift-gitops
  spec:
    destination:
      namespace: spring-dev
      server: https://kubernetes.default.svc
    project: spring-dev
    source:
      repoURL: https://github.com/siamaksade/openshift-gitops-getting-started
      targetRevision: HEAD
      path: app
    syncPolicy:
      automated:
        selfHeal: true
  EOF
  ```
  
  - Create an "application" with a member of the "spring-prod-group" group.
  ```
  cat << EOF | oc apply -f -
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: spring-prod
    namespace: openshift-gitops
  spec:
    destination:
      namespace: spring-prod
      server: https://kubernetes.default.svc
    project: spring-prod
    source:
      repoURL: https://github.com/siamaksade/openshift-gitops-getting-started
      targetRevision: HEAD
      path: app
    syncPolicy:
      automated:
        selfHeal: true
  EOF
  ```

  - Check that the application is generated as expected
  ```
  oc get applications -n openshift-gitops
  NAME               SYNC STATUS   HEALTH STATUS
  spring-dev-app1    Synced        Healthy
  spring-prod-app1   Synced        Healthy

  oc get po -n spring-dev
  NAME                                READY   STATUS    RESTARTS   AGE
  spring-petclinic-566fd65d6c-mj6dg   1/1     Running   0          78m

  oc get po -n spring-prod
  NAME                                READY   STATUS    RESTARTS   AGE
  spring-petclinic-566fd65d6c-vsrmd   1/1     Running   0          16m
  ```
