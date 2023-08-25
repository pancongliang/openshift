#!/bin/bash
cp /etc/crts/${REGISTRY_HOSTNAME}.ca.crt /etc/crts/${REGISTRY_HOSTNAME}.bk.ca.crt
sed -i 's/^/  /' /etc/crts/${REGISTRY_HOSTNAME}.bk.ca.crt
export REGISTRY_CA="$(cat /etc/crts/${REGISTRY_HOSTNAME}.bk.ca.crt)"
export REGISTRY_ID_PW=$(echo -n "$REGISTRY_ID:$REGISTRY_PW" | base64)
export ID_RSA_PUB=$(cat $ID_RSA_PUB)

cat << EOF > /root/test/install-config.yaml 
apiVersion: v1
baseDomain: $BASE_DOMAIN
compute: 
- hyperthreading: Enabled 
  name: worker
  replicas: 0 
controlPlane: 
  hyperthreading: Enabled 
  name: master
  replicas: 3 
metadata:
  name: $CLUSTER_NAME
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14 
    hostPrefix: 23 
  networkType: $NETWORK_TYPE
  serviceNetwork: 
  - 172.30.0.0/16
platform:
  none: {} 
fips: false 
pullSecret: '{"auths":{"${REGISTRY_HOSTNAME}:5000": {"auth": "$REGISTRY_ID_PW","email": "xxx@xxx.com"}}}' 
sshKey: '$ID_RSA_PUB'
additionalTrustBundle: | 
$REGISTRY_CA
imageContentSources:
- mirrors:
  - ${REGISTRY_HOSTNAME}:5000/${LOCAL_REPOSITORY}
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - ${REGISTRY_HOSTNAME}:5000/${LOCAL_REPOSITORY}
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
EOF

# Create kubernetes manifests:**
mkdir $INSTALL_DIR
cp install-config.yaml $INSTALL_DIR
openshift-install create manifests --dir $INSTALL_DIR/
sed -i 's/mastersSchedulable: true/mastersSchedulable: false/' $INSTALL_DIR/manifests/cluster-scheduler-02-config.yml

# Create and modify ignition configuration files
openshift-install create ignition-configs --dir $INSTALL_DIR
cp $INSTALL_DIR/bootstrap.ign $INSTALL_DIR/bootstrapbk.ign
for i in {01..03}; do cp $INSTALL_DIR/master.ign $INSTALL_DIR/master$i.ign; done
for i in {01..02}; do cp $INSTALL_DIR/worker.ign $INSTALL_DIR/worker$i.ign; done
sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,bootstrap.ocp4.example.com"},"mode": 420}]}}/' $INSTALL_DIR/bootstrapbk.ign
sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,master01.ocp4.example.com"},"mode": 420}]}}/' $INSTALL_DIR/master01.ign
sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,master02.ocp4.example.com"},"mode": 420}]}}/' $INSTALL_DIR/master02.ign
sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,master03.ocp4.example.com"},"mode": 420}]}}/' $INSTALL_DIR/master03.ign
sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,worker01.ocp4.example.com"},"mode": 420}]}}/' $INSTALL_DIR/worker01.ign
sed -i 's/}$/,"storage":{"files":[{"path":"\/etc\/hostname","contents":{"source":"data:,worker02.ocp4.example.com"},"mode": 420}]}}/' $INSTALL_DIR/worker02.ign
chmod a+r $INSTALL_DIR/*.ign
