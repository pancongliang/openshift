#!/bin/bash
NODE_SELECTOR_KEY="kubernetes.io/hostname"
NODE_SELECTOR_VALUE="master02.ocp4.example.com"

oc get deployment --no-headers -o custom-columns=":metadata.name" | \
while read -r deployment_name; do
    oc patch deployment/"$deployment_name" -p '{"spec":{"template":{"spec":{"nodeSelector":{"'"$NODE_SELECTOR_KEY"'":"'"$NODE_SELECTOR_VALUE"'"}}}}}'
done
