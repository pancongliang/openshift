#!/bin/bash

#while true; do
#    echo "waiting for installplan..."
#    INSTALLPLAN=$(oc get ip --all-namespaces -o=jsonpath='{range .items[?(@.spec.approved==false)]}{.metadata.name} {.metadata.namespace}{"\n"}{end}')
#    if [[ -n "$INSTALLPLAN" ]]; then
#        NAME=$(echo "$INSTALLPLAN" | awk '{print $1}')
#        NAMESPACE=$(echo "$INSTALLPLAN" | awk '{print $2}')
#        oc patch installplan "$NAME" -n "$NAMESPACE" --type merge --patch '{"spec":{"approved":true}}' 
#        break
#    fi
#    sleep 15
#done

while true; do
    echo "waiting for installplan..."
    INSTALLPLAN=$(oc get ip --all-namespaces -o=jsonpath='{range .items[?(@.spec.approved==false)]}{.metadata.name} {.metadata.namespace}{"\n"}{end}' | tr -d '\r')
    
    if [[ -n "$INSTALLPLAN" ]]; then
        echo "$INSTALLPLAN" | while read -r NAME NAMESPACE; do
            if [[ -n "$NAME" && -n "$NAMESPACE" ]]; then
                echo "Approving InstallPlan: $NAME in namespace: $NAMESPACE"
                oc patch installplan "$NAME" -n "$NAMESPACE" --type merge --patch '{"spec":{"approved":true}}'
            else
                echo "Skipping invalid entry: NAME=$NAME, NAMESPACE=$NAMESPACE"
            fi
        done
        break
    fi
    sleep 15
done



# for i in {1..2}; do curl -s https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/approve_ip.sh | bash; done

