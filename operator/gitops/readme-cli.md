### Install GitOps Operator

* Install the Operator using the default namespace
  ```
  export CHANNEL_NAME="latest"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/gitops/01-deploy-operator.yaml | envsubst | oc apply -f -

  sleep 6

  oc patch installplan $(oc get ip -n openshift-gitops-operator -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-gitops-operator --type merge --patch '{"spec":{"approved":true}}'

  oc get ip -n openshift-gitops-operator
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

### Deploying a Spring Boot application with Argo CD

* Create test namespaces that host the application load and label them to indicate that the projects are managed by openshift-gitops.
  ```
  oc new-project spring-petclinic
  oc label namespace spring-petclinic argocd.argoproj.io/managed-by=openshift-gitops
  ```

* Get the Argo CD UI url with the following commend, then select the `LOG IN VIA OPENSHIFT` option and log in with a user in the "cluster-admins" group.
  ```
  oc get route openshift-gitops-server -o jsonpath='{.spec.host}' -n openshift-gitops
  ```
  
* Create spring-petclinic AppProject.
  ```
  cat << EOF | oc apply -f -
  apiVersion: argoproj.io/v1alpha1
  kind: AppProject
  metadata:
    name: spring-petclinic
    namespace: openshift-gitops
  spec:
    clusterResourceWhitelist:
    - group: '*'
      kind: '*'
    destinations:
    - namespace: '*'
      server: '*'
    sourceRepos:
    - '*'
  EOF
  ```

  ```
  oc get appproject -n openshift-gitops
  NAME               AGE
  default            19h
  spring-petclinic   6s
  ```

* Create application
  ```
  cat << EOF | oc apply -f -
  apiVersion: argoproj.io/v1alpha1
  kind: Application
  metadata:
    name: app-spring-petclinic
    namespace: openshift-gitops
  spec:
    destination:
      namespace: spring-petclinic
      server: https://kubernetes.default.svc
    project: spring-petclinic
    source:
      directory:
        recurse: true
      repoURL: https://github.com/siamaksade/openshift-gitops-getting-started
      targetRevision: HEAD
      path: app
    syncPolicy:
      automated:
        selfHeal: true
  EOF
  ```

  ```
  oc get applications -n openshift-gitops
  NAME                   SYNC STATUS   HEALTH STATUS
  app-spring-petclinic   Synced        Healthy

  oc get po -n spring-petclinic
  NAME                                READY   STATUS    RESTARTS   AGE
  spring-petclinic-66864bf846-c5xdk   1/1     Running   0          3m48s
  ```
