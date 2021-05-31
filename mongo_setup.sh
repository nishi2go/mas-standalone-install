#!/bin/bash

## This Script installs mongo operator for MAS.
SCRIPT_DIR=$(cd $(dirname $0); pwd)

source "${SCRIPT_DIR}/behavior-analytics-services/Installation Scripts/bas-script-functions.bash"

function stepLog() {
  echo -e "STEP $1/4: $2"
}

WORK_DIR="${SCRIPT_DIR}/work"
DATETIME=`date +%Y%m%d_%H%M%S`

logFile="${SCRIPT_DIR}/logs/mongo-installation-${DATETIME}.log"
touch "${logFile}"

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
    echoRed "Login to OpenShift to continue MongoDB Operator installation."
        exit 1;
fi

displayStepHeader 1 "Copy necessary files from MongoDB CE Operator."
mkdir -p "${WORK_DIR}"
cp -r "${SCRIPT_DIR}/iot-docs/mongodb" "${WORK_DIR}"

mkdir -p "${WORK_DIR}/mongodb/config/rbac"
cp "${SCRIPT_DIR}/mongodb-kubernetes-operator/config/rbac/kustomization.yaml" "${WORK_DIR}/mongodb/config/rbac/"
cp "${SCRIPT_DIR}/mongodb-kubernetes-operator/config/rbac/role_binding.yaml" "${WORK_DIR}/mongodb/config/rbac/"
cp "${SCRIPT_DIR}/mongodb-kubernetes-operator/config/rbac/role.yaml" "${WORK_DIR}/mongodb/config/rbac/"
cp "${SCRIPT_DIR}/mongodb-kubernetes-operator/config/rbac/service_account.yaml" "${WORK_DIR}/mongodb/config/rbac/"

mkdir -p "${WORK_DIR}/mongodb/config/manager"
cp "${SCRIPT_DIR}/mongodb-kubernetes-operator/config/manager/manager.yaml" "${WORK_DIR}/mongodb/config/manager/"

mkdir -p "${WORK_DIR}/mongodb/config/crd"
cp "${SCRIPT_DIR}/mongodb-kubernetes-operator/config/crd/bases/mongodbcommunity.mongodb.com_mongodbcommunity.yaml" "${WORK_DIR}/mongodb/config/crd/"

displayStepHeader 2 "Generate self-signed certificates."

cd "${WORK_DIR}/mongodb/certs"
bash "${WORK_DIR}/mongodb/certs/generateSelfSignedCert.sh" | tee -a tee "${logFile}"

displayStepHeader 3 "Update MongoDB password."

if [ -z "${MONGO_PASSWORD}" ]; then
  MONGO_PASSWORD=`openssl rand -base64 10`
fi

cat "${SCRIPT_DIR}/mongodb/msi-mas_v1_mongodbcommunity_openshift_cr.yaml" | sed '$d' > "${WORK_DIR}/mongodb/config/mas-mongo-ce/mas_v1_mongodbcommunity_openshift_cr.yaml"
cat <<EOF | oc apply -n ${projectName} -f -
apiVersion: v1
kind: Secret
metadata:
  name: mas-mongo-ce-admin-password
type: Opaque
stringData:
  password: ${MONGO_PASSWORD}
EOF

displayStepHeader 4 "Install MongoDB Operator."

cd "${WORK_DIR}/mongodb/"
bash "${WORK_DIR}/mongodb/install-mongo-ce.sh" | tee -a "${logFile}"
