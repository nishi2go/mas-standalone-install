#!/bin/bash

## This Script installs sls operator for MAS.
SCRIPT_DIR=$(
  cd $(dirname $0)
  pwd
)

source "${SCRIPT_DIR}/behavior-analytics-services/Installation Scripts/bas-script-functions.bash"
source "${SCRIPT_DIR}/util.sh"

function stepLog() {
  echo -e "STEP $1/8: $2"
}

DATETIME=$(date +%Y%m%d_%H%M%S)

logFile="${SCRIPT_DIR}/logs/sls-installation-${DATETIME}.log"
touch "${logFile}"
projectName="ibm-sls"

if [ -z "${ENTITLEMENT_KEY}" ]; then
  echoRed "Missing entitlement key in environemnt variable ENTITLEMENT_KEY."
  exit 1
fi

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
  echoRed "Login to OpenShift to continue SLS Operator installation."
  exit 1
fi

displayStepHeader 1 "Install IBM Operator Catalog"
oc project default
oc apply -f "${SCRIPT_DIR}/suite-license-services/ibm-catalog.yaml" | tee -a "${logFile}"

displayStepHeader 2 "Create namespace for IBM SLS"
createProject

# displayStepHeader 4 "Create a custom SecurityContextConstraints for SLS"
# oc -n ${projectName} apply -f "${SCRIPT_DIR}/suite-license-services/sls-custom-scc.yaml" | tee -a "${logFile}"

displayStepHeader 3 "Install IBM Suite License Service"
operatorName="ibm-sls"
oc apply -n "${projectName}" -f "${SCRIPT_DIR}/suite-license-services/sls-operator-subscription.yaml" | tee -a "${logFile}"

displayStepHeader 4 "Verify IBM Suite License Service installation"
check_for_csv_success=$(checkOperatorInstallationSucceeded 2>&1)

if [[ "${check_for_csv_success}" == "Succeeded" ]]; then
  echoGreen "IBM Suite License Services Operator installed"
else
  echoRed "IBM Suite License Services Operator installation failed."
  exit 1
fi

displayStepHeader 5 "Add IBM Entitlement Registry"
oc -n ${projectName} create secret docker-registry ibm-entitlement \
  --docker-server=cp.icr.io/cp \
  --docker-username=cp \
  --docker-password="${ENTITLEMENT_KEY}" | tee -a "${logFile}"

displayStepHeader 6 "Create Mongo DB credentials"
MONGO_PASSWORD=$(oc get secret mas-mongo-ce-admin-password -n mongo --output="jsonpath={.data.password}" | base64 -d)
cat <<EOF | oc apply -f - | tee -a "${logFile}"
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

displayStepHeader 7 "Create License Service instance."
MONGO_CERT=$(oc get configmap mas-mongo-ce-cert-map -n mongo -o jsonpath='{.data.ca\.crt}' | sed -E  ':a;N;$!ba;s/\r{0,1}\n/\\n/g')
cat <<EOF | oc apply -f - | tee -a "${logFile}"
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
  domain: apps-crc.testing
  mongo:
    authMechanism: DEFAULT
    configDb: admin
    nodes:
      - host: mas-mongo-ce-0.mas-mongo-ce-svc.mongo.svc.cluster.local
        port: 27017
      - host: mas-mongo-ce-1.mas-mongo-ce-svc.mongo.svc.cluster.local
        port: 27017
      - host: mas-mongo-ce-2.mas-mongo-ce-svc.mongo.svc.cluster.local
        port: 27017
    secretName: sls-mongo-credentials
    certificates:
      - alias: mongodb
        crt: "${MONGO_CERT}"
  rlks:
    storage:
      class: local-path
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

displayStepHeader 8 "Wait License Service instance ready."
while [[ $(oc get -n ibm-sls licenseservice | grep sls | tr -s " " | cut -d' ' -f 3) != "True" ]]; do sleep 5s; done
