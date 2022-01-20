#!/bin/bash

## This Script installs BAS operator for MAS.
SCRIPT_DIR=$(
  cd $(dirname $0)
  pwd
)

source "${SCRIPT_DIR}/behavior-analytics-services/Installation Scripts/bas-script-functions.bash"
source "${SCRIPT_DIR}/util.sh"

function stepLog() {
  echo -e "STEP $1/8: $2"
}

mkdir -p logs
WORK_DIR="${SCRIPT_DIR}/work/bas"

mkdir -p "${WORK_DIR}"

# cp -r "${SCRIPT_DIR}/behavior-analytics-services/Installation Scripts/"* "${WORK_DIR}/"

if [ -z "${BAS_DB_PASSWORD}" ]; then
  BAS_DB_PASSWORD=$(openssl rand -hex 15)
fi

if [ -z "${BAS_GRAFANA_PASSWORD}" ]; then
  BAS_GRAFANA_PASSWORD=$(openssl rand -hex 15)
fi

basVersion=-certified.v1.1.3
projectName="bas"
storageClassKafka="local-path"
storageClassZookeeper="local-path"
storageClassDB="local-path"
storageClassArchive="managed-nfs-storage"
dbuser=admin
dbpassword="${BAS_DB_PASSWORD}"
grafanauser=admin
grafanapassword="${BAS_GRAFANA_PASSWORD}"
####Keeping the values of below properties to default is advised.
storageSizeKafka=5G
storageSizeZookeeper=5G
storageSizeDB=10G
storageSizeArchive=10G
eventSchedulerFrequency='*/10 * * * *'
prometheusSchedulerFrequency='@daily'
envType=lite
ibmproxyurl='https://iaps.ibm.com'
airgappedEnabled=false
imagePullSecret=bas-images-pull-secret

mkdir -p logs
logFile="${SCRIPT_DIR}/logs/bas-installation-${DATETIME}.log"
touch "${logFile}"

cd "${WORK_DIR}/"

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
  echoRed "Login to OpenShift to continue SLS Operator installation."
  exit 1
fi

displayStepHeader 1 "Create a new project"
createProject

displayStepHeader 2 "Apply a BAS OperatorGroup object"

cat <<EOF | oc apply -f - | tee -a "${logFile}"
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: bas-operator-group
  namespace: "${projectName}"
spec:
  targetNamespaces:
  - "${projectName}"
EOF

displayStepHeader 3 "Subscribe the BAS operator"

cat <<EOF | oc apply -f - | tee -a "${logFile}"
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: behavior-analytics-services-operator-certified
  namespace: "${projectName}"
spec:
  channel: alpha
  installPlanApproval: Automatic
  name: behavior-analytics-services-operator-certified
  source: certified-operators
  sourceNamespace: openshift-marketplace
  startingCSV: behavior-analytics-services-operator${basVersion}
EOF

displayStepHeader 4 "Verify the Operator subscription"
retryCount=300
retries=0
check_for_csv_success=$(oc get csv -n "${projectName}" behavior-analytics-services-operator${basVersion} -o jsonpath='{.status.phase}' --ignore-not-found)
until [[ $retries -eq $retryCount || $check_for_csv_success = "Succeeded" ]]; do
  sleep 5
  check_for_csv_success=$(oc get csv -n "${projectName}" behavior-analytics-services-operator${basVersion} -o jsonpath='{.status.phase}' --ignore-not-found)
  retries=$((retries + 1))
done

if [[ "${check_for_csv_success}" == "Succeeded" ]]; then
  echoGreen "Behavior Analytics Services Operator installed"
else
  echoRed "Behavior Analytics Services Operator installation failed."
  exit 1
fi

displayStepHeader 5 "Create a secret named database-credentials for PostgreSQL DB and grafana-credentials for Grafana"

oc create secret generic database-credentials --from-literal=db_username=${dbuser} --from-literal=db_password=${dbpassword} -n "${projectName}" &>>"${logFile}"
oc create secret generic grafana-credentials --from-literal=grafana_username=${grafanauser} --from-literal=grafana_password=${grafanapassword} -n "${projectName}" &>>"${logFile}"

displayStepHeader 6 "Create the AnalyticsProxy instance."
cat <<EOF | oc apply -f - | tee -a "${logFile}"
apiVersion: bas.ibm.com/v1
kind: AnalyticsProxy
metadata:
  name: analyticsproxydeployment
  namespace: "${projectName}"
spec:
  allowed_domains: "*"
  db_archive:
    frequency: '@monthly'
    retention_age: 6
    persistent_storage:
      storage_class: "${storageClassArchive}"
      storage_size: "${storageSizeArchive}"
  airgapped:
    enabled: ${airgappedEnabled}
    backup_deletion_frequency: '@daily'
    backup_retention_period: 7
  event_scheduler_frequency: "${eventSchedulerFrequency}"
  ibmproxyurl: "${ibmproxyurl}"
  image_pull_secret: "${imagePullSecret}"
  postgres:
    storage_class: ${storageClassDB}
    storage_size: ${storageSizeDB}
  kafka:
    storage_class: "${storageClassKafka}"
    storage_size: "${storageSizeKafka}"
    zookeeper_storage_class: "${storageClassZookeeper}"
    zookeeper_storage_size: "${storageSizeZookeeper}"
  env_type: "${envType}"
EOF

sleep 10

displayStepHeader 7 "Check AnalyticsProxy instance creation"
retryCount=300
retries=0
check_for_inst_success=$(oc get AnalyticsProxy analyticsproxydeployment -n "${projectName}" --output="jsonpath={.status.phase}")
until [[ $retries -eq $retryCount || $check_for_inst_success = "Ready" ]]; do
  sleep 5
  check_for_inst_success=$(oc get AnalyticsProxy analyticsproxydeployment -n "${projectName}" --output="jsonpath={.status.phase}")
  retries=$((retries + 1))
done

if [[ "${check_for_inst_success}" == "Ready" ]]; then
  echoGreen "Analytics Proxy Deployment setup ready"
else
  echoRed "Analytics Proxy Deployment setup failed."
  exit 1
fi

displayStepHeader 8 "Create API key"
cat <<EOF | oc apply -f - | tee -a "${logFile}"
apiVersion: bas.ibm.com/v1
kind: GenerateKey
metadata:
  name: bas-api-key
spec:
  image_pull_secret: bas-images-pull-secret
EOF
