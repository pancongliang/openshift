#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u
set -e
set -o pipefail
trap 'echo "failed: [line $LINENO: command \`$BASH_COMMAND\`]"; exit 1' ERR

# Set environment variables
export OCP_INSTALL_DIR="$HOME/ocp"

PRINT_TASK "TASK [Uninstalling a cluster]"

echo "info: [uninstalling the cluster, waiting...]"
openshift-install destroy cluster --dir $OCP_INSTALL_DIR --log-level info
run_command "[uninstalled cluster]"
