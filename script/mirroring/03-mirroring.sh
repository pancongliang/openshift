#SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

#CONFIG_FILE="${SCRIPT_DIR}/02-imageset-config.yaml"

#oc mirror --config="${CONFIG_FILE}" docker://${LOCAL_REGISTRY} --dest-skip-tls
oc mirror --config=./02-imageset-config.yaml docker://${LOCAL_REGISTRY} --dest-skip-tls
