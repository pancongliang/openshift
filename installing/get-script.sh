#!/bin/bash
set -euo pipefail

BASE="$HOME/ocp-inst"

info() {
    printf "\033[96mINFO\033[0m $1"
}

rm -rf "$BASE"
mkdir -p "$BASE" "$BASE/quay" "$BASE/storage" "$BASE/vsphere" "$BASE/aws" "$BASE/upi"

# Operator
wget -q -O "$BASE/acs.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/acs/acs.sh && info "Downloaded $BASE/acs.sh"
wget -q -O "$BASE/es.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/logging/elasticsearch/es.sh && info "Downloaded $BASE/es.sh"
wget -q -O "$BASE/loki.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/logging/lokistack/loki.sh && info "Downloaded $BASE/loki.sh"
wget -q -O "$BASE/rhbk.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhbk/rhbk.sh && info "Downloaded $BASE/rhbk.sh"
wget -q -O "$BASE/rhsso.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/rhsso/rhsso.sh && info "Downloaded $BASE/rhsso.sh"
wget -q -O "$BASE/bookinfo.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/operator/servicemesh/bookinfo.sh && info "Downloaded $BASE/bookinfo.sh"

# Quay
wget -q -O "$BASE/quay/omr.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/registry/mirror-registry/omr.sh && info "Downloaded $BASE/quay/omr.sh"
wget -q -O "$BASE/quay/quay.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/registry/quay-operator/quay.sh && info "Downloaded $BASE/quay/quay.sh"
wget -q -O "$BASE/quay/standalone-quay.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/registry/quay-standalone/standalone-quay.sh && info "Downloaded $BASE/quay/standalone-quay.sh"

# Storage
wget -q -O "$BASE/storage/lso.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/storage/local-sc/lso.sh && info "Downloaded $BASE/storage/lso.sh"
wget -q -O "$BASE/storage/minio.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/storage/minio/minio.sh && info "Downloaded $BASE/storage/minio.sh"
wget -q -O "$BASE/storage/nfs-sc.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/storage/nfs-sc/nfs-sc.sh && info "Downloaded $BASE/storage/nfs-sc.sh"
wget -q -O "$BASE/storage/odf.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/storage/odf/odf.sh && info "Downloaded $BASE/storage/odf.sh"

# UPI
wget -q -O "$BASE/upi/ocp-upi-inst.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/installing/any-platform/online/ocp-upi-inst.sh && info "Downloaded $BASE/upi/ocp-upi-inst.sh"
wget -q -O "$BASE/upi/ocp-upi-offline.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/installing/any-platform/offline/ocp-upi-offline.sh && info "Downloaded $BASE/upi/ocp-upi-offline.sh"

# vSphere
wget -q -O "$BASE/vsphere/vsphere-ipi-dhcp.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/installing/vsphere-ipi/vsphere-ipi-dhcp.sh && info "Downloaded $BASE/vsphere/vsphere-ipi-dhcp.sh"
wget -q -O "$BASE/vsphere/vsphere-ipi-static.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/installing/vsphere-ipi/vsphere-ipi-static.sh && info "Downloaded $BASE/vsphere/vsphere-ipi-static.sh"
wget -q -O "$BASE/vsphere/vsphere-ipi-uninst.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/installing/vsphere-ipi/vsphere-ipi-uninst.sh && info "Downloaded $BASE/vsphere/vsphere-ipi-uninst.sh"

# AWS
wget -q -O "$BASE/aws/aws-ipi-inst.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/installing/aws-ipi/online/aws-ipi-inst.sh && info "Downloaded $BASE/aws/aws-ipi-inst.sh"
wget -q -O "$BASE/aws/aws-ipi-uninst.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/installing/aws-ipi/online/aws-ipi-uninst.sh && info "Downloaded $BASE/aws/aws-ipi-uninst.sh"
wget -q -O "$BASE/aws/aws-del-bastion.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/installing/aws-ipi/online/aws-del-bastion.sh && info "Downloaded $BASE/aws/aws-del-bastion.sh"
wget -q -O "$BASE/aws/aws-inst-bastion.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/installing/aws-ipi/online/aws-inst-bastion.sh && info "Downloaded $BASE/aws/aws-inst-bastion.sh"
wget -q -O "$BASE/aws/aws-ssh-deploy.sh" https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/installing/aws-ipi/online/aws-ssh-deploy.sh && info "Downloaded $BASE/aws/aws-ssh-deploy.sh"

# Grant script execution permissions
find $BASE -type f -name "*.sh" -exec chmod +x {} +  && info "Grant script execution permissions"
