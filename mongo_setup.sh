#!/bin/bash

## This Script installs mongo operator for MAS.
SCRIPT_DIR=$(cd $(dirname $0); pwd)

source "${SCRIPT_DIR}/behavior-analytics-services/Installation Scripts/bas-script-functions.bash"

function stepLog() {
  echo -e "STEP $1/6: $2"
}

if [ -z "$MONGO_NAMESPACE" ]; then
  MONGO_NAMESPACE="mongo"
fi

mkdir -p logs
WORK_DIR="${SCRIPT_DIR}/work"
DATETIME=`date +%Y%m%d_%H%M%S`

logFile="${SCRIPT_DIR}/logs/mongo-installation-${DATETIME}.log"
touch "${logFile}"

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
    echoRed "Login to OpenShift to continue MongoDB Operator installation."
        exit 1;
fi

displayStepHeader 1 "Create namespace for MongoDB"
projectName=${MONGO_NAMESPACE}
createProject

displayStepHeader 2 "Copy necessary files from MongoDB CE Operator."
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

displayStepHeader 3 "Generate self-signed certificates."

cd "${WORK_DIR}/mongodb/certs"
bash "${WORK_DIR}/mongodb/certs/generateSelfSignedCert.sh" | tee -a tee "${logFile}"

displayStepHeader 4 "Update MongoDB password."

if [ -z "${MONGO_PASSWORD}" ]; then
  MONGO_PASSWORD=`openssl rand -hex 10`
fi

cat <<EOF | oc apply -f - | tee -a tee "${logFile}"
apiVersion: v1
kind: Secret
metadata:
  name: mas-mongo-ce-admin-password
  namespace: ${MONGO_NAMESPACE}
type: Opaque
stringData:
  password: ${MONGO_PASSWORD}
EOF

displayStepHeader 5 "Install MongoDB Operator."
cp "${SCRIPT_DIR}/mongodb/msi-mas_v1_mongodbcommunity_openshift_cr.yaml" "${WORK_DIR}/mongodb/config/mas-mongo-ce/mas_v1_mongodbcommunity_openshift_cr.yaml"

cd "${WORK_DIR}/mongodb/"

oc new-project ${MONGO_NAMESPACE}

oc apply -f config/crd/mongodbcommunity.mongodb.com_mongodbcommunity.yaml -n ${MONGO_NAMESPACE}

oc apply -k config/rbac/.  -n ${MONGO_NAMESPACE}

oc adm policy add-scc-to-user anyuid system:serviceaccount:${MONGO_NAMESPACE}:default
oc adm policy add-scc-to-user anyuid system:serviceaccount:${MONGO_NAMESPACE}:mongodb-kubernetes-operator

oc create -f config/manager/manager.yaml -n ${MONGO_NAMESPACE}
echo -n " - Waiting for MongoDB CE Operator  "
while [[ $(oc get deployment mongodb-kubernetes-operator -n ${MONGO_NAMESPACE} -o 'jsonpath={..status.conditions[?(@.type=="Available")].status}') != "True" ]];do sleep 5s; done

cd certs
oc create configmap mas-mongo-ce-cert-map --from-file=ca.crt=ca.pem -n ${MONGO_NAMESPACE}
oc create secret tls mas-mongo-ce-cert-secret --cert=server.crt --key=server.key -n ${MONGO_NAMESPACE}
cd ..

oc apply -f config/mas-mongo-ce/mas_v1_mongodbcommunity_openshift_cr.yaml -n ${MONGO_NAMESPACE}
sleep 5s
while [[ $(oc get statefulset mas-mongo-ce -n ${MONGO_NAMESPACE} --ignore-not-found -o 'jsonpath={..status.readyReplicas}') != "1" ]];do sleep 5s; done

oc rollout restart statefulset mas-mongo-ce -n ${MONGO_NAMESPACE}
sleep 5s

displayStepHeader 6 "Enable SCRAM-SHA-1 Auth."
JSON=$(oc get secret mas-mongo-ce-config -n ${MONGO_NAMESPACE} -o 'jsonpath={..data.cluster-config\.json}' | base64 -d  | jq -c '.auth.autoAuthMechanisms|=["SCRAM-SHA-256", "SCRAM-SHA-1"]' | jq -c '.auth.deploymentAuthMechanisms|=["SCRAM-SHA-256", "SCRAM-SHA-1"]' | base64 -w 0)

oc patch secret mas-mongo-ce-config -n "${MONGO_NAMESPACE}" -p="{\"data\":{\"cluster-config.json\": \"${JSON}\"}}" -v=1
oc rollout restart statefulset mas-mongo-ce -n "${MONGO_NAMESPACE}"
sleep 10s
while [[ $(oc get statefulset mas-mongo-ce -n ${MONGO_NAMESPACE} --ignore-not-found -o 'jsonpath={..status.readyReplicas}') != "1" ]];do sleep 5s; done
