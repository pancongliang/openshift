#!/bin/bash
set -euo pipefail

# Check for required argument
if [ $# -ne 1 ]; then
  echo "Usage: $0 <namespace>"
  exit 1
fi

NAMESPACE="$1"

# Start oc proxy in the background
pkill -f "oc proxy" || true
oc proxy &

# Wait briefly for proxy to start
sleep 1

# Remove finalizers from the namespace and save to temp.json
oc get namespace "$NAMESPACE" -o json | jq '.spec = {"finalizers":[]}' > temp.json

# Send the updated namespace spec to the Kubernetes API to finalize deletion
curl -k -H "Content-Type: application/json" \
     -X PUT --data-binary @temp.json \
     "http://127.0.0.1:8001/api/v1/namespaces/${NAMESPACE}/finalize"

# Optional: Kill the background oc proxy process
pkill -f "oc proxy" || true
rm -rf temp.json  || true
