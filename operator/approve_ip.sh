#!/bin/bash

while true; do
    echo "waiting for install plan"
    INSTALLPLAN=$(oc get ip --all-namespaces -o=jsonpath='{range .items[?(@.spec.approved==false)]}{.metadata.name} {.metadata.namespace}{"\n"}{end}')
    if [[ -n "$INSTALLPLAN" ]]; then
        NAME=$(echo "$INSTALLPLAN" | awk '{print $1}')
        NAMESPACE=$(echo "$INSTALLPLAN" | awk '{print $2}')
        oc patch installplan "$NAME" -n "$NAMESPACE" --type merge --patch '{"spec":{"approved":true}}' 
        break
    fi
    sleep 15
done
