#!/usr/bin/env bash

## This Script installs sls operator for MAS.
SCRIPT_DIR=$(
    cd $(dirname $0)
    pwd
)

source "${SCRIPT_DIR}/util.sh"

if [ -z "${ENTITLEMENT_KEY}" ]; then
    echo "Missing entitlement key in environemnt variable ENTITLEMENT_KEY." 1>&2
    exit 1
fi

if [ -z "$MONGODB_NAMESPACE" ]; then
    MONGODB_NAMESPACE="mongodb"
fi

if [ -z "${MONGODB_REPLICAS}" ]; then
    MONGODB_REPLICAS="3"
fi

if [ -z "${SLS_STORAGE_CLASS}" ]; then
    SLS_STORAGE_CLASS=local-path
fi

if [ -z "${SLS_DOMAIN_NAME}" ]; then
    SLS_DOMAIN_NAME=apps-crc.testing
fi

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
    echo "Login to OpenShift to continue SLS Operator installation." 1>&2
    exit 1
fi

echo "--- Install IBM Operator Catalog"
oc project default
oc apply -f "${SCRIPT_DIR}/suite-license-services/ibm-catalog.yaml"

echo "--- Create namespace for IBM SLS"
projectName="ibm-sls"
createProject

echo "--- Install IBM Suite License Service"
oc apply -n "${projectName}" -f "${SCRIPT_DIR}/suite-license-services/sls-operator-subscription.yaml"

echo "--- Verify IBM Suite License Service installation"
operatorName="ibm-sls"
cmd="oc get subscription -n ${projectName} ${operatorName} -o jsonpath={.status.currentCSV}"
waitUntilAvailable "${cmd}"
csv=$(${cmd})

cmd="oc get csv -n ${projectName} ${csv} -o jsonpath={.status.phase}"
state="Succeeded"
waitUntil "${cmd}" "${state}"

echo "--- Add IBM Entitlement Registry"
oc -n ${projectName} create secret docker-registry ibm-entitlement \
--docker-server=cp.icr.io/cp \
--docker-username=cp \
--docker-password="${ENTITLEMENT_KEY}"

echo "--- Create Mongo DB credentials"
MONGO_PASSWORD=$(oc get secret mas-mongo-ce-admin-password -n ${MONGODB_NAMESPACE} --output="jsonpath={.data.password}" | base64 -d)
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: sls-mongo-credentials
  namespace: ${projectName}
stringData:
  username: "admin"
  password: "${MONGO_PASSWORD}"
EOF

echo "--- Create License Service instance."
MONGO_NODES=""
for i in $(seq 0 $((${MONGODB_REPLICAS} - 1))); do
    MONGO_NODES="${MONGO_NODES}\n      - host: mas-mongo-ce-${i}.mas-mongo-ce-svc.${MONGODB_NAMESPACE}.svc.cluster.local\n        port: 27017\n"
done
MONGO_NODES=$(echo -ne "${MONGO_NODES}")
MONGO_CERT=$(oc get configmap mas-mongo-ce-cert-map -n ${MONGODB_NAMESPACE} -o jsonpath='{.data.ca\.crt}' | sed -E ':a;N;$!ba;s/\r{0,1}\n/\\n/g')
cat <<EOF | oc apply -f -
apiVersion: sls.ibm.com/v1
kind: LicenseService
metadata:
  name: sls
  namespace: ${projectName}
  labels:
    app.kubernetes.io/instance: ibm-sls
    app.kubernetes.io/managed-by: olm
    app.kubernetes.io/name: ibm-sls
spec:
  license:
    accept: true
  domain: ${SLS_DOMAIN_NAME}
  mongo:
    authMechanism: DEFAULT
    configDb: admin
    nodes:
${MONGO_NODES}
    retryWrites: true
    secretName: sls-mongo-credentials
    certificates:
      - alias: mongodb
        crt: "${MONGO_CERT}"
  rlks:
    storage:
      class: ${SLS_STORAGE_CLASS}
      size: 5G
  settings:
    auth:
      enforce: true
    compliance:
      enforce: true
    reconciliation:
      enabled: true
      reconciliationPeriod: 1800
    registration:
      open: true
    reporting:
      maxDailyReports: 90
      maxHourlyReports: 24
      maxMonthlyReports: 12
      reportGenerationPeriod: 3600
      samplingPeriod: 900
EOF

if [ -v SLS_INSTANCE_ID ]; then
    echo "--- Add bootstrap secret."
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  namespace: ${projectName}
  name: sls-bootstrap
stringData:
  licensingId: ${SLS_INSTANCE_ID}
  registrationKey: ${SLS_REGISTRATION_KEY}
EOF
fi

echo "--- Wait License Service instance ready."
cmd="oc get -n ${projectName} licenseservice -o=jsonpath={.items[0].status.conditions[?(@.type=='Ready')].status}"
state="True"
waitUntil "${cmd}" "${state}"

echo "Done"