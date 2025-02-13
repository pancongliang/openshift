#!/bin/bash
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

export CONTROL_PLANE_NS=istio-system
export BOOKINFO_NS=bookinfo

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
servicemesh_deployment=$(oc get deployment -n openshift-operators -o name 2>/dev/null | grep istio)
while [ -z "${servicemesh_deployment}" ]; do
    sleep 2
    servicemesh_deployment=$(oc get deployment -n openshift-operators -o name 2>/dev/null | grep istio)
done

# Wait for Kiali Operator deployment
kiali_deployment=$(oc get deployment -n openshift-operators -o name 2>/dev/null | grep kiali)
while [ -z "${kiali_deployment}" ]; do
    sleep 2
    kiali_deployment=$(oc get deployment -n openshift-operators -o name 2>/dev/null | grep kiali)
done

# Wait for Jaeger Operator deployment (修正 servicemesh_deployment 错误)
jaeger_deployment=$(oc get deployment -n openshift-operators -o name 2>/dev/null | grep jaeger)
while [ -z "${jaeger_deployment}" ]; do
    sleep 2
    jaeger_deployment=$(oc get deployment -n openshift-operators -o name 2>/dev/null | grep jaeger)
done

# Wait for Elastic Operator deployment
elastic_deployment=$(oc get deployment -n openshift-operators -o name 2>/dev/null | grep elastic)
while [ -z "${elastic_deployment}" ]; do
    sleep 2
    elastic_deployment=$(oc get deployment -n openshift-operators -o name 2>/dev/null | grep elastic)
done


echo "waiting for operator deployments to start..."
for op in ${servicemesh_deployment} ${kiali_deployment} ${jaeger_deployment} ${elastic_deployment}; do
    echo -n "waiting for ${op} to be ready..."
    
    readyReplicas=""
    
    while [ -z "$readyReplicas" ] || [ "$readyReplicas" = "0" ]; do
        sleep 1
        echo -n '.'
        readyReplicas="$(oc get ${op} -n openshift-operators -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
    done
    
    echo "done"
done


cat <<EOM | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${CONTROL_PLANE_NS}
EOM

cat <<EOM | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${BOOKINFO_NS}
EOM

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
basic_install_smcp=$(oc get smcp -n "${CONTROL_PLANE_NS}" basic 2>/dev/null | grep ComponentsReady)

while [ -z "${basic_install_smcp}" ]; do
    echo -n '.'
    sleep 5
    basic_install_smcp=$(oc get smcp -n "${CONTROL_PLANE_NS}" basic 2>/dev/null | grep ComponentsReady)
done

echo "done."

# install bookinfo
echo "success, deploying bookinfo..."
oc patch -n ${CONTROL_PLANE_NS} --type='json' smmr default -p '[{"op": "add", "path": "/spec/members", "value":["'"${BOOKINFO_NS}"'"]}]'
oc apply -n ${BOOKINFO_NS} -f https://raw.githubusercontent.com/Maistra/istio/maistra-2.6/samples/bookinfo/platform/kube/bookinfo.yaml 2>/dev/null
oc apply -n ${BOOKINFO_NS} -f https://raw.githubusercontent.com/Maistra/istio/maistra-2.6/samples/bookinfo/networking/bookinfo-gateway.yaml 2>/dev/null
oc apply -n ${BOOKINFO_NS} -f https://raw.githubusercontent.com/Maistra/istio/maistra-2.6/samples/bookinfo/networking/destination-rule-all.yaml 2>/dev/null
export GATEWAY_URL=$(oc -n ${CONTROL_PLANE_NS} get route istio-ingressgateway -o jsonpath='{.spec.host}')

echo "service mesh and bookinfo has been deployed!"
echo "test the bookinfo application out at: http://${GATEWAY_URL}/productpage"
