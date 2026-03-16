
### Show certificates expiring within 1 year
~~~
oc get secret -A -o json | jq -r ' .items[] | select( .metadata.annotations."auth.openshift.io/certificate-not-after" | .!=null and fromdateiso8601<='$( date --date='+1year' +%s )' ) | "expiration: \( .metadata.annotations."auth.openshift.io/certificate-not-after" ) \( .type ) -n \( .metadata.namespace ) \( .metadata.name )" ' | sort | column -t
~~~

### Print all TLS secret expiry dates
~~~
echo -e "NAMESPACE\tNAME\tEXPIRY" && oc get secrets --all-namespaces -o go-template='{{range .items}}{{if eq .type "kubernetes.io/tls"}}{{.metadata.namespace}}{{" "}}{{.metadata.name}}{{" "}}{{index .data "tls.crt"}}{{"\n"}}{{end}}{{end}}' | while read namespace name cert; do echo -en "$namespace\t$name\t"; echo $cert | base64 -d | openssl x509 -noout  -enddate; done | sort | column -t
~~~

### Export CA Certificates
~~~
oc extract secrets/router-ca --keys tls.crt -n openshift-ingress-operator
~~~
~~~
oc rsh -n openshift-authentication $(oc get pods -n openshift-authentication -l app=oauth-openshift -o jsonpath="{.items[0].metadata.name}") cat /run/secrets/kubernetes.io/serviceaccount/ca.crt > ca.crt
~~~

### Force update all certificates
~~~
oc get secret -A -o json | jq -r '.items[] | select(.metadata.annotations."auth.openshift.io/certificate-not-after" | .!=null and fromdateiso8601<='$( date --date='+1year' +%s )') | "-n \(.metadata.namespace) \(.metadata.name)"' | xargs -n3 oc patch secret -p='{"metadata": {"annotations": {"auth.openshift.io/certificate-not-after": null}}}'
~~~

### Certificate-related documents
[How to check the internal certificates information in OCP 4](https://access.redhat.com/solutions/5925951)

[How to renew certificates in Openshift 4.x?](https://access.redhat.com/solutions/5018231)

[How to list all OpenShift TLS certificate expire date?](https://access.redhat.com/solutions/3930291)

[OpenShift certificate location](https://github.com/openshift/api/tree/master/tls/docs)



