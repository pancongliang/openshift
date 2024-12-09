~~~
oc create -f https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/webhook/pod.yaml
oc get po -n webhooktest
oc create -f https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/webhook.yaml
oc get validatingwebhookconfiguration |grep val-webhook
~~~
