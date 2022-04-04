#!/usr/bin/env bash

## This Script installs sb operator for MAS.
SCRIPT_DIR=$(
    cd $(dirname $0)
    pwd
)

source "${SCRIPT_DIR}/util.sh"

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
    echo "Login to OpenShift to continue Service Binding Operator installation."
    exit 1
fi

echo "--- Install Service Binding Operator"
oc project default
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rh-service-binding-operator
  namespace: openshift-operators
  labels:
    operators.coreos.com/rh-service-binding-operator.openshift-operators: ''
spec:
  channel: stable
  name: rh-service-binding-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

echo "--- Verify Service Binding Operator installation"
projectName="openshift-operators"
operatorName="rh-service-binding-operator"
cmd="oc get subscription -n ${projectName} ${operatorName} --ignore-not-found=true -o jsonpath={.status.currentCSV}"
waitUntilAvailable "${cmd}"
csv=$(${cmd})

cmd="oc get csv -n ${projectName} ${csv} --ignore-not-found=true -o jsonpath={.status.phase}"
state="Succeeded"
waitUntil "${cmd}" "${state}"
echo "Done."
