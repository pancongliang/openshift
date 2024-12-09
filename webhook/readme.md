~~~
oc create -f https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/webhook/pod.yaml
oc get po -n webhooktest
oc create -f https://github.com/pancongliang/openshift/blob/main/webhook/webhook.yaml
~~~
