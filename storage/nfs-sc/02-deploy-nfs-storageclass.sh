#!/bin/bash
# === Function to print a task with uniform length ===
# Function to print a task with uniform length
PRINT_TASK() {
    max_length=90  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}
# ====================================================


# Function to check command success and display appropriate message
run_command() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}


# === Task: Install NFS storage class ===
PRINT_TASK "[TASK: Install NFS storage class]"

# Create namespace
cat << EOF > namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF
oc delete -f namespace.yaml &>/dev/null
oc create -f namespace.yaml &>/dev/null
run_command "[create new namespace: ${NAMESPACE}]"
rm -rf namespace.yaml &>/dev/null

# Create sa and rbac
cat << EOF > sa_and_rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nfs-client-provisioner
  # replace with namespace where provisioner is deployed
  namespace: ${NAMESPACE}
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: nfs-client-provisioner-runner
rules:
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list", "watch", "create", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims"]
    verbs: ["get", "list", "watch", "update"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create", "update", "patch"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: run-nfs-client-provisioner
subjects:
  - kind: ServiceAccount
    name: nfs-client-provisioner
    # replace with namespace where provisioner is deployed
    namespace: ${NAMESPACE}
roleRef:
  kind: ClusterRole
  name: nfs-client-provisioner-runner
  apiGroup: rbac.authorization.k8s.io
---
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
  # replace with namespace where provisioner is deployed
  namespace: ${NAMESPACE}
rules:
  - apiGroups: [""]
    resources: ["endpoints"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: leader-locking-nfs-client-provisioner
  # replace with namespace where provisioner is deployed
  namespace: ${NAMESPACE}
subjects:
  - kind: ServiceAccount
    name: nfs-client-provisioner
    # replace with namespace where provisioner is deployed
    namespace: ${NAMESPACE}
roleRef:
  kind: Role
  name: leader-locking-nfs-client-provisioner
  apiGroup: rbac.authorization.k8s.io
EOF

oc delete -f sa_and_rbac.yaml &>/dev/null
oc create -f sa_and_rbac.yaml &>/dev/null
run_command "[create rbac configuration]"
rm -rf sa_and_rbac.yaml &>/dev/null

# scc
oc adm policy add-scc-to-user hostmount-anyuid system:serviceaccount:${NAMESPACE}:nfs-client-provisioner &>/dev/null
run_command "[add SCC hostmount-anyuid to nfs-client-provisioner user]"

# deployment
cat << EOF > deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-client-provisioner
  labels:
    app: nfs-client-provisioner
  # replace with namespace where provisioner is deployed
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: nfs-client-provisioner
  template:
    metadata:
      labels:
        app: nfs-client-provisioner
    spec:
      serviceAccountName: nfs-client-provisioner
      containers:
        - name: nfs-client-provisioner
          image: k8s.gcr.io/sig-storage/nfs-subdir-external-provisioner:v4.0.2
          volumeMounts:
            - name: nfs-client-root
              mountPath: /persistentvolumes
          env:
            - name: PROVISIONER_NAME
              value: nfs-storage-provisioner
            - name: NFS_SERVER
              value: ${NFS_SERVER_IP}
            - name: NFS_PATH
              value: ${NFS_DIR}
      volumes:
        - name: nfs-client-root
          nfs:
            server: ${NFS_SERVER_IP}
            path: ${NFS_DIR}
EOF
oc delete -f deployment.yaml &>/dev/null
oc create -f deployment.yaml &>/dev/null
run_command "[deploy nfs-client-provisioner]"
rm -rf deployment.yaml &>/dev/null

# storage class
cat << EOF > storageclass.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-nfs-storage
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: nfs-storage-provisioner     
parameters:
  archiveOnDelete: "false"
  reclaimPolicy: Retain
EOF
oc delete -f storageclass.yaml &>/dev/null
oc create -f storageclass.yaml &>/dev/null
run_command "[create nfs storage class]"
rm -rf storageclass.yaml &>/dev/null
