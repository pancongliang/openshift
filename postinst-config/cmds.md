#### Enable or disable the default OperatorHub source
~~~
oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": false}]'

oc patch OperatorHub cluster --type json -p '[{"op": "add", "path": "/spec/disableAllDefaultSources", "value": true}]'
~~~

#### Update Global Pull Secret
~~~
oc get secret/pull-secret -n openshift-config --output="jsonpath={.data.\.dockerconfigjson}" | base64 -d > pull-secret 
oc set data secret/pull-secret -n openshift-config --from-file=.dockerconfigjson=pull-secret
~~~

#### Export and Update htpasswd Secret
~~~
oc extract secret/htpasswd-secret -n openshift-config --to . --confirm
oc set data secret/htpasswd-secret --from-file htpasswd=htpasswd -n openshift-config

#!/bin/bash
for Hostname in $(oc get nodes  -o jsonpath='{.items[*].status.addresses[?(@.type=="Hostname")].address}')
do
   echo "--- [$Hostname] ---"
   ssh -o StrictHostKeyChecking=no core@$Hostname sudo cat /var/lib/kubelet/config.json
   echo
done
~~~

#### Use the master node's kubeconfig for cluster administration
~~~
export KUBECONFIG=/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/lb-int.kubeconfig
~~~~

#### Disable or enable master node scheduling of custom pods
~~~
oc patch schedulers.config.openshift.io cluster --type merge --patch '{"spec": {"mastersSchedulable": false}}'

oc patch schedulers.config.openshift.io cluster --type merge --patch '{"spec": {"mastersSchedulable": true}}'
~~~

#### Pausing and Unpausing the machine config pools
~~~
oc patch --type=merge --patch='{"spec":{"paused":true}}' machineconfigpool/master
oc patch --type=merge --patch='{"spec":{"paused":true}}' machineconfigpool/worker

oc patch --type=merge --patch='{"spec":{"paused":false}}' machineconfigpool/master
oc patch --type=merge --patch='{"spec":{"paused":false}}' machineconfigpool/worker
~~~

#### Extract ConfigMap/Secret Certificates and View Expiration
~~~
oc extract configmap/<ConfigMap> -n <[project]>
oc get secret <SECRET-NAME> -o "jsonpath={.data['tls\.crt']}" | base64 --decode | openssl x509 -noout -text -in -
openssl x509 -in tls.crt -noout -date
openssl x509 -in  tls.crt -text -noout
~~~

#### Export Root CA Certificate
~~~
oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator
oc rsh -n openshift-authentication $(oc get pods -n openshift-authentication -l app=oauth-openshift -o jsonpath="{.items[0].metadata.name}") cat /run/secrets/kubernetes.io/serviceaccount/ca.crt > ca.crt
~~~

#### Get Current Cluster Certificate Expiration
~~~
oc get secret -A -o json | jq -r '.items[] | select(.metadata.annotations."auth.openshift.io/certificate-not-after"!=null) | select(.metadata.name|test("-[0-9]+$")|not) | "\(.metadata.namespace) \(.metadata.name) \(.metadata.annotations."auth.openshift.io/certificate-not-after")"' | column -t
~~~

#### Check Certificates Expiring Within One Year
~~~
oc get secret -A -o json | jq -r ' .items[] | select( .metadata.annotations."auth.openshift.io/certificate-not-after" | .!=null and fromdateiso8601<='$( date --date='+100year' +%s )' ) | "expiration: \( .metadata.annotations."auth.openshift.io/certificate-not-after" ) \( .type ) -n \( .metadata.namespace ) \( .metadata.name )" ' | sort | column -t
~~~

#### List Expiration Dates of All TLS Secrets
~~~
echo -e "NAMESPACE\tNAME\tEXPIRY" && oc get secrets -A -o go-template='{{range .items}}{{if eq .type "kubernetes.io/tls"}}{{.metadata.namespace}}{{" "}}{{.metadata.name}}{{" "}}{{index .data "tls.crt"}}{{"\n"}}{{end}}{{end}}' | while read namespace name cert; do echo -en "$namespace\t$name\t"; echo $cert | base64 -d | openssl x509 -noout -enddate; done | column -t
~~~

#### Force Immediate Certificate Renewal
~~~
oc get secret -A -o json | jq -r '.items[] | select(.metadata.annotations."auth.openshift.io/certificate-not-after" | .!=null and fromdateiso8601<='$( date --date='+1year' +%s )') | "-n \(.metadata.namespace) \(.metadata.name)"' | xargs -n3 oc patch secret -p='{"metadata": {"annotations": {"auth.openshift.io/certificate-not-after": null}}}'
~~~

#### Assign SCC to a Deployment
~~~
oc get pod <pod-name> -o yaml | oc adm policy scc-subject-review -f -
oc create serviceaccount <sa-name> -n <project>
oc adm policy add-scc-to-user privileged -z <sa-name> -n <project>
oc set serviceaccount deployment/<deployment-name> <sa-name> -n <project>
~~~

#### Build Trigger Workflow
~~~
oc new-project trigger-build-test

oc import-image php \
  --from registry.redhat.io/ubi8/php-74:latest --confirm

oc new-app --name trigger \
  php~http://github.com/pancongliang/DO288-apps \
  --context-dir trigger-builds

oc -n trigger-build rollout history deployment/trigger

oc start-build trigger -n trigger-build

oc rollout undo deploy/trigger --to-revision=2

oc get build -n trigger-build-test

oc logs --version=1 bc/trigger -n trigger-build-test
~~~

#### Access API
~~~
export TOKEN=$(oc whoami -t)
export ENDPOINT=$(oc config current-context | cut -d/ -f2 | tr - .)
export NAMESPACE=copan-dem
curl -k -H "Authorization: Bearer $TOKEN" \
     -H 'Accept: application/json' \
     https://$ENDPOINT/apis/events.k8s.io/v1/namespaces/$NAMESPACE/events
~~~
