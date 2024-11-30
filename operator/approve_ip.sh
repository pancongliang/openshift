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

#!/bin/bash

# NAMESPACE=("rhsso" "openshift-gitops-operator")
# NAMESPACE="rhsso"

while true; do
    echo "waiting for installplan..."
    INSTALLPLANS=$(oc get ip --all-namespaces -o=jsonpath='{range .items[?(@.spec.approved==false)]}{.metadata.name} {.metadata.namespace}{"\n"}{end}' | tr -d '\r')
    
    if [[ -n "$INSTALLPLANS" ]]; then
        echo "$INSTALLPLANS" | while read -r INSTALLPLAN_NAME INSTALLPLAN_NAMESPACE; do
            if [[ -n "$INSTALLPLAN_NAME" && -n "$INSTALLPLAN_NAMESPACE" ]]; then
                if [[ "$INSTALLPLAN_NAMESPACE" == "$NAMESPACE" ]]; then
                    oc patch installplan "$INSTALLPLAN_NAME" -n "$INSTALLPLAN_NAMESPACE" --type merge --patch '{"spec":{"approved":true}}'
                fi
            fi
        done
        break
    fi
    sleep 15
done



