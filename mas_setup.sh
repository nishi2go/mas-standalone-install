#!/usr/bin/env bash

## This Script installs MAS core.
SCRIPT_DIR=$(
  cd $(dirname $0)
  pwd
)

source "${SCRIPT_DIR}/util.sh"

if [ -z "${ENTITLEMENT_KEY}" ]; then
  echo "Missing entitlement key in environemnt variable ENTITLEMENT_KEY." 1>&2
  exit 1
fi

if [ -z "${MAS_INSTANCE_ID}" ]; then
  MAS_INSTANCE_ID="crc"
fi

if [ -z "${MAS_DOMAIN_NAME}" ]; then
  MAS_DOMAIN_NAME="mas.apps-crc.testing"
fi

if [ -z "${MAS_CHANNEL}" ]; then
  MAS_CHANNEL="8.7.x"
fi

#if [ -z "${MAS_UPGRADE_PLAN}" ]; then
MAS_UPGRADE_PLAN="Automatic"
#fi

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
  echo "Login to OpenShift to continue installation." 1>&2
  exit 1
fi

echo "--- Create the project"
projectName="mas-${MAS_INSTANCE_ID}-core"
createProject

echo "--- Add IBM Entitlement Registry"
oc -n ${projectName} create secret docker-registry ibm-entitlement \
  --docker-server=cp.icr.io/cp \
  --docker-username=cp \
  --docker-password="${ENTITLEMENT_KEY}"

echo "--- Install IBM Operator Catalog"
cat <<EOF | oc apply -f -
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: "IBM Operator Catalog"
  publisher: IBM
  sourceType: grpc
  image: docker.io/ibmcom/ibm-operator-catalog
  updateStrategy:
    registryPoll:
      interval: 45m
EOF

echo "--- Install IBM Operator Group"
cat <<EOF | oc apply -f -
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-mas-operator-group
  namespace: "${projectName}"
spec:
  targetNamespaces:
    - "${projectName}"
EOF

echo "--- Install MAS subscription"
cat <<EOF | oc apply -f -
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mas-operator
  namespace: "${projectName}"
spec:
  channel: "${MAS_CHANNEL}"
  installPlanApproval: "${MAS_UPGRADE_PLAN}"
  name: ibm-mas
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF

echo "--- Wait MAS Operator installation"
operatorName=ibm-mas-operator
cmd="oc get subscription -n ${projectName} ${operatorName} --ignore-not-found=true -o jsonpath={.status.currentCSV}"
waitUntilAvailable "${cmd}"
csv=$(${cmd})

cmd="oc get csv -n ${projectName} ${csv}  --ignore-not-found=true -o jsonpath={.status.phase}"
state="Succeeded"
waitUntil "${cmd}" "${state}"

echo "--- Wait IBM Common Service installation"
operatorSelector="operators.coreos.com/ibm-common-service-operator.${projectName}"
cmd="oc get subscription -n ${projectName} -l ${operatorSelector} --ignore-not-found=true -o jsonpath={.items[0].status.currentCSV}"
waitUntilAvailable "${cmd}"
csv=$(${cmd})

cmd="oc get csv -n ${projectName} ${csv} --ignore-not-found=true -o jsonpath={.status.phase}"
state="Succeeded"
waitUntil "${cmd}" "${state}"

echo "--- Install Suite Config"
cat <<EOF | oc apply -f -
---
apiVersion: core.mas.ibm.com/v1
kind: Suite
metadata:
  name: "${MAS_INSTANCE_ID}"
  namespace: "${projectName}"
  labels:
    mas.ibm.com/instanceId: "${MAS_INSTANCE_ID}"
spec:
  certManagerNamespace: ibm-common-services
  domain: "${MAS_DOMAIN_NAME}"
  license:
    accept: true
  settings:
    icr:
      cp: cp.icr.io/cp
      cpopen: icr.io/cpopen
EOF

echo "--- Wait Suite config completion"
cmd="oc get deployment/${MAS_INSTANCE_ID}-admin-dashboard --ignore-not-found=true -o jsonpath={.status.readyReplicas} -n ${projectName}"
state="1"
waitUntil "${cmd}" "${state}"

cmd="oc get deployment/${MAS_INSTANCE_ID}-coreapi --ignore-not-found=true -o jsonpath={.status.readyReplicas} -n ${projectName}"
state="3"
waitUntil "${cmd}" "${state}"

echo "Done"
