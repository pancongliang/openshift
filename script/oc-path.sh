#!/bin/bash

NODE_SELECTOR_KEY="kubernetes.io/hostname"
NODE_SELECTOR_VALUE="master01.ocp4.example.com"

oc get deployment --no-headers -o custom-columns=":metadata.name" | \
while read -r deployment_name; do
    # 
    oc patch deployment/"$deployment_name" --type=json -p="$(echo '[{"op": "add", "path": "/spec/template/spec/nodeSelector", "value": {"'${NODE_SELECTOR_KEY}'": "'${NODE_SELECTOR_VALUE}'"}}]' | envsubst)"
done


#!/bin/bash

NODE_SELECTOR_KEY="kubernetes.io/hostname"
NODE_SELECTOR_VALUE="master01.ocp4.example.com"

oc get deployment --no-headers -o custom-columns=":metadata.name" | \
while read -r deployment_name; do
    oc patch deployment/"$deployment_name" --type=json -p="$(echo '[{"op": "remove", "path": "/spec/template/spec/nodeSelector", "value": {"'${NODE_SELECTOR_KEY}'": "'${NODE_SELECTOR_VALUE}'"}}]' | envsubst)"
done
