## Deploy Local Storage

* Set necessary parameters

  ```
  export NAMESPACE="test"
  export PV_NAME="test-pv"
  export PVC_NAME="test-pvc"
  export STORAGE_SIZE="100Gi"
  export PV_NODE_NAME="worker01.ocp4.example.com"
  ```
  
* Deploy Local Storage PV/PVC
  ```
  ssh core@${PV_NODE_NAME} sudo mkdir -p -m 777 /mnt/${PV_NAME}
  
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/storage/local-storage/deploy-local-storage.yaml | envsubst | oc apply -f -

  oc get sc
  oc get pvc -n ${NAMESPACE}
  ```

* Test mount
  ```
  oc new-app --name nginx --docker-image quay.io/redhattraining/hello-world-nginx:v1.0
  oc set volumes deployment/nginx --add --name test-volume \
     --type persistentVolumeClaim --claim-name ${PVC_NAME} --mount-path /usr/share/nginx/html

  oc rsh nginx-d75558854-7575d
  sh-4.4$ touch /usr/share/nginx/html/1

  ssh core@${PV_NODE_NAME} sudo ls /mnt/test-pv/
  1
  ```
