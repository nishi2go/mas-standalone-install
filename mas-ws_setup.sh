#!/usr/bin/env bash

## This Script installs MAS workspace.
SCRIPT_DIR=$(
  cd $(dirname $0)
  pwd
)

source "${SCRIPT_DIR}/util.sh"

if [ -z "${UDS_EMAIL}" ]; then
    echo "Missing email address in environemnt variable UDS_EMAIL." 1>&2
    exit 1
fi

if [ -z "${UDS_LASTNAME}" ]; then
    echo "Missing last name in environemnt variable UDS_LASTNAME." 1>&2
    exit 1
fi

if [ -z "${UDS_FIRSTNAME}" ]; then
    echo "Missing first name in environemnt variable UDS_FIRSTNAME." 1>&2
    exit 1
fi

if [ -z "$SLS_NAMESPACE" ]; then
    SLS_NAMESPACE="ibm-sls"
fi

if [ -z "${MAS_INSTANCE_ID}" ]; then
    MAS_INSTANCE_ID="crc"
fi

if [ -z "${MAS_WORKSPACE_ID}" ]; then
    MAS_WORKSPACE_ID="dev"
fi

if [ -z "${MAS_WORKSPACE_NAME}" ]; then
    MAS_WORKSPACE_NAME="Maximo dev"
fi

if [ -z "${MAS_DOMAIN_NAME}" ]; then
    MAS_DOMAIN_NAME="mas.apps-crc.testing"
fi

if [ -z "$MONGODB_NAMESPACE" ]; then
    MONGODB_NAMESPACE="mongodb"
fi

if [ -z "${MONGODB_REPLICAS}" ]; then
    MONGODB_REPLICAS=3
fi

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
    echo "Login to OpenShift to continue installation." 1>&2
    exit 1
fi

echo "--- Set up the project"
projectName="mas-${MAS_INSTANCE_ID}-core"
createProject

echo "--- Install MongoDB Config for MAS"
MONGO_PASSWORD=$(oc get secret mas-mongo-ce-admin-password -n ${MONGODB_NAMESPACE} --output="jsonpath={.data.password}" | base64 -d)
MONGO_CERT=$(oc get configmap mas-mongo-ce-cert-map -n ${MONGODB_NAMESPACE} -o jsonpath='{.data.ca\.crt}' | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g')
MONGO_NODES=""
for i in $(seq 0 $((${MONGODB_REPLICAS} - 1))); do
    MONGO_NODES="${MONGO_NODES}\n      - host: mas-mongo-ce-${i}.mas-mongo-ce-svc.${MONGODB_NAMESPACE}.svc.cluster.local\n        port: 27017\n"
done
MONGO_NODES=$(echo -ne "${MONGO_NODES}")

cat <<EOF | oc apply -f -
---
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: "${MAS_INSTANCE_ID}-mongodb-admin"
  namespace: ${projectName}
stringData:
  username: admin
  password: "${MONGO_PASSWORD}"
---
apiVersion: config.mas.ibm.com/v1
kind: MongoCfg
metadata:
  name: "${MAS_INSTANCE_ID}-mongo-system"
  namespace: "${projectName}"
  labels:
    app.kubernetes.io/instance: ibm-mas
    app.kubernetes.io/managed-by: olm
    app.kubernetes.io/name: ibm-mas
    mas.ibm.com/configScope: system
    mas.ibm.com/instanceId: "${MAS_INSTANCE_ID}"
spec:
  displayName: "MongoDB in ${MONGODB_NAMESPACE}"
  type: external
  config:
    hosts:
${MONGO_NODES}
    configDb: admin
    authMechanism: DEFAULT
    credentials:
      secretName: "${MAS_INSTANCE_ID}-mongodb-admin"
  certificates:
    - alias: mongodbca
      crt: "${MONGO_CERT}" 
EOF

echo "--- Install UDS Config for MAS"
UDS_NAMESPACE="ibm-common-services"
UDS_URL=$(echo -n https://$(oc get routes uds-endpoint -n "${UDS_NAMESPACE}" |awk 'NR==2 {print $2}'))
UDS_APIKEY=$(oc get secret uds-api-key -n "${UDS_NAMESPACE}" --output="jsonpath={.data.apikey}" | base64 -d)
UDS_CERT1=$(oc get secret router-certs-default -n "openshift-ingress" -o "jsonpath={.data.tls\.crt}" | base64 -d | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g')

cat <<EOF | oc apply -f - 
---
apiVersion: v1
kind: Secret
type: opaque
metadata:
  name: uds-apikey
  namespace: "${projectName}"
stringData:
  api_key: "${UDS_APIKEY}"
---
apiVersion: config.mas.ibm.com/v1
kind: BasCfg
metadata:
  labels:
    app.kubernetes.io/instance: ibm-mas
    app.kubernetes.io/managed-by: olm
    app.kubernetes.io/name: ibm-mas
    mas.ibm.com/configScope: system
    mas.ibm.com/instanceId: "${MAS_INSTANCE_ID}"
  name: ${MAS_INSTANCE_ID}-bas-system
  namespace: "${projectName}"
spec:
  certificates:
    - alias: uds-crt1
      crt: "${UDS_CERT1}" 
  config:
    contact:
      email: "${UDS_EMAIL}"
      firstName: ${UDS_FIRSTNAME}
      lastName: ${UDS_LASTNAME}
    credentials:
      secretName: uds-apikey
    url: ${UDS_URL}
  displayName: System BAS Configuration
EOF

echo "--- Install SLS Config for MAS"
SLS_URL=$(oc get configmap -n "${SLS_NAMESPACE}" sls-suite-registration -o jsonpath='{.data.url}')
SLS_KEY=$(oc get configmap -n "${SLS_NAMESPACE}" sls-suite-registration -o jsonpath='{.data.registrationKey}')
SLS_CERT=$(oc get configmap -n "${SLS_NAMESPACE}" sls-suite-registration -o jsonpath='{.data.ca}' | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g')

cat <<EOF | oc apply -f - 
---
apiVersion: v1
kind: Secret
type: opaque
metadata:
  name: sls-registration-key
  namespace: "${projectName}"
stringData:
  registrationKey: "${SLS_KEY}"
---
kind: SlsCfg
apiVersion: config.mas.ibm.com/v1
metadata:
  labels:
    app.kubernetes.io/instance: ibm-mas
    app.kubernetes.io/managed-by: olm
    app.kubernetes.io/name: ibm-mas
    mas.ibm.com/configScope: system
    mas.ibm.com/instanceId: "${MAS_INSTANCE_ID}"
  name: ${MAS_INSTANCE_ID}-sls-system
  namespace: "${projectName}"
spec:
  certificates:
    - alias: slsca
      crt: "${SLS_CERT}"
  config:
    credentials:
      secretName: sls-registration-key
    url: ${SLS_URL}
  displayName: System SLS Configuration
EOF

echo "--- Install MAS Workspace Config"
cat <<EOF | oc apply -f -
---
apiVersion: core.mas.ibm.com/v1
kind: Workspace
metadata:
  name: "${MAS_INSTANCE_ID}-${MAS_WORKSPACE_ID}"
  namespace: "${projectName}"
  labels:
    mas.ibm.com/instanceId: "${MAS_INSTANCE_ID}"
    mas.ibm.com/workspaceId: "${MAS_WORKSPACE_ID}"
spec:
  displayName: "${MAS_WORKSPACE_NAME}"
EOF

echo "--- Wait MongoDB config completion"
cmd="oc get suite.core.mas.ibm.com ${MAS_INSTANCE_ID} -n ${projectName} -o jsonpath={.status.conditions[?(@.type==\"SystemDatabaseReady\")].status}"
state="True"
waitUntil "${cmd}" "${state}"

echo "--- Wait SLS config completion"
if [ -v SLS_LICENSE_FILE ]; then
    echo "--- Upload SLS lisence file"
    WORK_DIR="${SCRIPT_DIR}/work"
    mkdir -p "${WORK_DIR}"
    oc get secret -n ${SLS_NAMESPACE} sls-cert-client -o jsonpath='{.data.tls\.key}' | base64 -d -w 0 > ${WORK_DIR}/tls.key
    oc get secret -n ${SLS_NAMESPACE} sls-cert-client -o jsonpath='{.data.tls\.crt}' | base64 -d -w 0 > ${WORK_DIR}/tls.crt
    oc get secret -n ${SLS_NAMESPACE} sls-cert-client -o jsonpath='{.data.ca\.crt}' | base64 -d -w 0 > ${WORK_DIR}/ca.crt
    curl -ks --cert ${WORK_DIR}/tls.crt --key ${WORK_DIR}/tls.key --cacert ${WORK_DIR}/ca.crt -X PUT -F "file=@${SLS_LICENSE_FILE}" $(oc get configmap -n ${SLS_NAMESPACE} sls-suite-registration -o jsonpath='{.data.url}')/api/entitlement/file
    curl -ks --cert ${WORK_DIR}/tls.crt --key ${WORK_DIR}/tls.key --cacert ${WORK_DIR}/ca.crt $(oc get configmap -n ${SLS_NAMESPACE} sls-suite-registration -o jsonpath='{.data.url}')/api/tokens | jq '.[0]'
    rm -r ${WORK_DIR}
    echo ""

    cmd="oc get suite.core.mas.ibm.com ${MAS_INSTANCE_ID} -n ${projectName} -o jsonpath={.status.conditions[?(@.type==\"SLSIntegrationReady\")].status}"
    state="True"
    waitUntil "${cmd}" "${state}"

    cmd="oc get suite.core.mas.ibm.com ${MAS_INSTANCE_ID} -n ${projectName} -o jsonpath={.status.conditions[?(@.type==\"Ready\")].status}"
    state="True"
    waitUntil "${cmd}" "${state}"
else
    cmd="oc get suite.core.mas.ibm.com ${MAS_INSTANCE_ID} -n ${projectName} -o jsonpath={.status.conditions[?(@.type==\"SLSIntegrationReady\")].reason}"
    state="MissingLicenseFile"
    waitUntil "${cmd}" "${state}"
    echo "Put your license file to enable MAS workspece."
fi

echo "--- Wait UDS config completion"
cmd="oc get suite.core.mas.ibm.com ${MAS_INSTANCE_ID} -n ${projectName} -o jsonpath={.status.conditions[?(@.type==\"BASIntegrationReady\")].status}"
state="True"
waitUntil "${cmd}" "${state}"

echo "Done"
