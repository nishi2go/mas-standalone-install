#!/bin/bash

## This Script installs mongo operator for MAS.
SCRIPT_DIR=$(
  cd $(dirname $0)
  pwd
)

source "${SCRIPT_DIR}/behavior-analytics-services/Installation Scripts/bas-script-functions.bash"

function stepLog() {
  echo -e "STEP $1/3: $2"
}

if [ -z "$MONGO_NAMESPACE" ]; then
  export MONGO_NAMESPACE="mongo"
fi

if [ -z "$MONGODB_STORAGE_CLASS" ]; then
  export MONGODB_STORAGE_CLASS="local-path"
fi

if [ -z "$MONGOD_STORAGE_GB" ]; then
  export MONGOD_STORAGE_GB="5Gi"
fi

if [ -z "$MONGOD_STORAGE_LOGS_GB" ]; then
  export MONGOD_STORAGE_LOGS_GB="500Mi"
fi

if [ -z "${MONGO_PASSWORD}" ]; then
  export MONGO_PASSWORD=$(openssl rand -hex 10)
fi

if [ -z "${MONGOD_REPLICAS}" ]; then
  export MONGOD_REPLICAS=1
fi

mkdir -p logs
WORK_DIR="${SCRIPT_DIR}/work"
DATETIME=$(date +%Y%m%d_%H%M%S)

logFile="${SCRIPT_DIR}/logs/mongo-installation-${DATETIME}.log"
touch "${logFile}"

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
  echoRed "Login to OpenShift to continue MongoDB Operator installation."
  exit 1
fi

displayStepHeader 1 "Prepare setup scripts for MongoDB CE Operator."
mkdir -p "${WORK_DIR}/mongodb"
rm -rf "${WORK_DIR}/mongodb/*"
cp -r "${SCRIPT_DIR}/iot-docs/mongodb" "${WORK_DIR}"
sed -i.bak "s|cpu: 500m|cpu: 10m|g" "${WORK_DIR}/mongodb/config/manager/__manager__.yaml"
sed -i.bak "s|members: 3|members: ${MONGOD_REPLICAS}|g" "${WORK_DIR}/mongodb/config/mas-mongo-ce/__mas_v1_mongodbcommunity_openshift_cr__.yaml"
sed -i.bak "s|!= \"3\"|!= \"${MONGOD_REPLICAS}\"|g" "${WORK_DIR}/mongodb/install-mongo-ce.sh"

displayStepHeader 2 "Generate self-signed certificates."

cd "${WORK_DIR}/mongodb/certs"
bash "${WORK_DIR}/mongodb/certs/generateSelfSignedCert.sh" | tee -a tee "${logFile}"

displayStepHeader 3 "Install MongoDB Operator."

cd "${WORK_DIR}/mongodb/"

bash ./install-mongo-ce.sh
