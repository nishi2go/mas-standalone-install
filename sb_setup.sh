#!/bin/bash

## This Script installs sb operator for MAS.
SCRIPT_DIR=$(cd $(dirname $0); pwd)

source "${SCRIPT_DIR}/behavior-analytics-services/Installation Scripts/bas-script-functions.bash"
source "${SCRIPT_DIR}/util.sh"

function stepLog() {
  echo -e "STEP $1/2: $2"
}

DATETIME=`date +%Y%m%d_%H%M%S`

mkdir -p logs
logFile="${SCRIPT_DIR}/logs/sb-installation-${DATETIME}.log"
touch "${logFile}"
projectName="default"

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
    echoRed "Login to OpenShift to continue Service Binding Operator installation."
        exit 1;
fi

displayStepHeader 1 "Install Service Binding Operator"
oc project default
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rh-service-binding-operator
  namespace: openshift-operators
spec:
  channel: preview
  name: rh-service-binding-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Manual
  startingCSV: service-binding-operator.v0.8.0
EOF

installplan=$(oc get installplan -n openshift-operators | grep -i service-binding | awk '{print $1}')

oc patch installplan ${installplan} -n openshift-operators --type merge --patch '{"spec":{"approved":true}}'

displayStepHeader 2 "Verify Service Binding Operator installation"
operatorName="service-binding-operator"
check_for_csv_success=$(checkOperatorInstallationSucceeded 2>&1)

if [[ "${check_for_csv_success}" == "Succeeded" ]]; then
	echoGreen "Service Binding Operators Operator installed"
else
    echoRed "Service Binding Operators Operator installation failed."
	exit 1;
fi
