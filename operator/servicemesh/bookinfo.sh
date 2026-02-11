# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Applying environment variables
export CONTROL_PLANE_NS=istio-system
export BOOKINFO_NS=bookinfo

# Add user's local bin to PATH
export PATH="$HOME/.local/bin:$PATH"

# Delete custom resources
echo "uninstall custom resources..."
oc delete ns $BOOKINFO_NS >/dev/null 2>&1 || true
oc delete ServiceMeshMemberRoll --all -n $CONTROL_PLANE_NS >/dev/null 2>&1 || true
oc delete ServiceMeshControlPlane --all -n $CONTROL_PLANE_NS >/dev/null 2>&1 || true
oc delete kiali --all -n $CONTROL_PLANE_NS >/dev/null 2>&1 || true
oc delete jaeger --all -n $CONTROL_PLANE_NS >/dev/null 2>&1 || true
oc delete sub elasticsearch-operator -n openshift-operators >/dev/null 2>&1 || true
oc delete sub kiali-ossm -n openshift-operators >/dev/null 2>&1 || true
oc delete sub jaeger-product -n openshift-operators >/dev/null 2>&1 || true
oc delete sub servicemeshoperator -n openshift-operators >/dev/null 2>&1 || true

oc get csv -n openshift-operators -o name | grep elasticsearch | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-operators >/dev/null 2>&1 || true
oc get csv -n openshift-operators -o name | grep kiali | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-operators >/dev/null 2>&1 || true
oc get csv -n openshift-operators -o name | grep jaeger | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-operators >/dev/null 2>&1 || true
oc get csv -n openshift-operators -o name | grep servicemesh | awk -F/ '{print $2}' | xargs -I {} oc delete csv {} -n openshift-operators >/dev/null 2>&1 || true

oc delete ns $CONTROL_PLANE_NS >/dev/null 2>&1 || true

#install the elastic operator
cat <<EOM | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: elasticsearch-operator
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: elasticsearch-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOM

#install the Kiali operator
cat <<EOM | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kiali-ossm
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: kiali-ossm
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOM

#install the Jaeger operator
cat <<EOM | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: jaeger-product
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: jaeger-product
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOM

#install the ServiceMesh operator
cat <<EOM | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: servicemeshoperator
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: servicemeshoperator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOM

sleep 30

#wait for crds
for crd in servicemeshcontrolplanes.maistra.io servicemeshmemberrolls.maistra.io kialis.kiali.io jaegers.jaegertracing.io
do
    echo -n "waiting for $crd ..."
    while ! oc get crd $crd > /dev/null 2>&1
    do
        sleep 2
        echo -n '.'
    done
    echo "done"
done

# Wait for Service Mesh Operator deployment
servicemesh_deployment=$(oc get deployment -n openshift-operators -o name | grep istio 2>/dev/null || true)
while [ -z "${servicemesh_deployment}" ]; do
    sleep 2
    servicemesh_deployment=$(oc get deployment -n openshift-operators -o name | grep istio 2>/dev/null || true)
done

# Wait for Kiali Operator deployment
kiali_deployment=$(oc get deployment -n openshift-operators -o name | grep kiali 2>/dev/null || true)
while [ -z "${kiali_deployment}" ]; do
    sleep 2
    kiali_deployment=$(oc get deployment -n openshift-operators -o name | grep kiali 2>/dev/null || true)
done

# Wait for Jaeger Operator deployment
jaeger_deployment=$(oc get deployment -n openshift-operators -o name | grep jaeger 2>/dev/null || true)
while [ -z "${jaeger_deployment}" ]; do
    sleep 2
    jaeger_deployment=$(oc get deployment -n openshift-operators -o name | grep jaeger 2>/dev/null || true)
done

# Wait for Elastic Operator deployment
elastic_deployment=$(oc get deployment -n openshift-operators -o name | grep elastic 2>/dev/null || true)
while [ -z "${elastic_deployment}" ]; do
    sleep 2
    elastic_deployment=$(oc get deployment -n openshift-operators -o name | grep elastic 2>/dev/null || true)
done

echo "waiting for operator deployments to start..."
for op in ${servicemesh_deployment} ${kiali_deployment} ${jaeger_deployment} ${elastic_deployment}; do
    echo -n "waiting for ${op} to be ready..."
    
    readyReplicas=""
    
    while [ -z "$readyReplicas" ] || [ "$readyReplicas" = "0" ]; do
        sleep 1
        echo -n '.'
        readyReplicas="$(oc get ${op} -n openshift-operators -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0))"
    done
    
    echo "done"
done

cat <<EOM | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${CONTROL_PLANE_NS}
EOM

sleep 60

echo "creating the scmp/smmr..."
#create our smcp
cat <<EOM | oc apply -f -
apiVersion: maistra.io/v2
kind: ServiceMeshControlPlane
metadata:
  namespace: ${CONTROL_PLANE_NS}
  name: basic
spec:
  tracing:
    sampling: 10000
    type: Jaeger
  policy:
    type: Istiod
  addons:
    grafana:
      enabled: true
    jaeger:
      install:
        storage:
          type: Memory
    kiali:
      enabled: true
    prometheus:
      enabled: true
  version: v2.5
  telemetry:
    type: Istiod
EOM

#create our smmr
cat <<EOM | oc apply -f -
apiVersion: maistra.io/v1
kind: ServiceMeshMemberRoll
metadata:
  namespace: ${CONTROL_PLANE_NS}
  name: default
spec:
  members:
EOM

#wait for smcp to fully install
echo -n "waiting for smcp to fully install (this will take a few moments) ..."
basic_install_smcp=$(oc get smcp -n "${CONTROL_PLANE_NS}" basic | grep ComponentsReady 2>/dev/null || true)

while [ -z "${basic_install_smcp}" ]; do
    echo -n '.'
    sleep 5
    basic_install_smcp=$(oc get smcp -n "${CONTROL_PLANE_NS}" basic | grep ComponentsReady 2>/dev/null || true)
done

echo "done."

cat <<EOM | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${BOOKINFO_NS}
EOM

# install bookinfo
echo "success, deploying bookinfo..."
oc patch -n ${CONTROL_PLANE_NS} --type='json' smmr default -p '[{"op": "add", "path": "/spec/members", "value":["'"${BOOKINFO_NS}"'"]}]'
oc apply -n ${BOOKINFO_NS} -f https://raw.githubusercontent.com/Maistra/istio/maistra-2.6/samples/bookinfo/platform/kube/bookinfo.yaml 2>/dev/null
oc apply -n ${BOOKINFO_NS} -f https://raw.githubusercontent.com/Maistra/istio/maistra-2.6/samples/bookinfo/networking/bookinfo-gateway.yaml 2>/dev/null
oc apply -n ${BOOKINFO_NS} -f https://raw.githubusercontent.com/Maistra/istio/maistra-2.6/samples/bookinfo/networking/destination-rule-all.yaml 2>/dev/null
export GATEWAY_URL=$(oc -n ${CONTROL_PLANE_NS} get route istio-ingressgateway -o jsonpath='{.spec.host}')

echo "service mesh and bookinfo has been deployed!"
echo "test the bookinfo application out at: http://${GATEWAY_URL}/productpage"
