### Add keys and values
~~~
#!/bin/bash

NODE_SELECTOR_KEY="kubernetes.io/hostname"
NODE_SELECTOR_VALUE="master01.ocp4.example.com"

oc get deployment --no-headers -o custom-columns=":metadata.name" | \
while read -r deployment_name; do
    # Add keys and values
    oc patch deployment/"$deployment_name" --type=json -p="$(echo '[{"op": "add", "path": "/spec/template/spec/nodeSelector", "value": {"'${NODE_SELECTOR_KEY}'": "'${NODE_SELECTOR_VALUE}'"}}]' | envsubst)"
done

# After application
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/hostname: master01.ocp4.example.com
~~~


### Remove keys and values
~~~
#!/bin/bash

NODE_SELECTOR_KEY="kubernetes.io/hostname"
NODE_SELECTOR_VALUE="master01.ocp4.example.com"

oc get deployment --no-headers -o custom-columns=":metadata.name" | \
while read -r deployment_name; do
    # Remove keys and values
    oc patch deployment/"$deployment_name" --type=json -p="$(echo '[{"op": "remove", "path": "/spec/template/spec/nodeSelector", "value": {"'${NODE_SELECTOR_KEY}'": "'${NODE_SELECTOR_VALUE}'"}}]' | envsubst)"
done
~~~

### Add name and values
~~~
oc patch central stackrox-central-services -n stackrox \
   --type=json -p="$(echo '[{"op": "add", "path": "/spec/customize", "value": {"envVars": [{"name": "ROX_REPROCESSING_INTERVAL", "value": "${ROX_REPROCESSING_INTERVAL}"}]}}]' | envsubst)"

# After application
spec:
  customize:
    envVars:
      - name: ROX_REPROCESSING_INTERVAL
        value: "30m"
~~~
