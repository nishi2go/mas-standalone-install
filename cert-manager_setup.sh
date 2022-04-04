#!/usr/bin/env bash

## This Script installs ibm cert manager operator 
SCRIPT_DIR=$(
  cd $(dirname $0)
  pwd
)

source "${SCRIPT_DIR}/util.sh"

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
  echo "Login to OpenShift to continue installation." 1>&2
  exit 1
fi

echo "--- Check IBM Common Services installed"
if [[ ! $(oc get crd operandrequests.operator.ibm.com 2> /dev/null) ]]; then
  echo "IBM Common Services not found." 1>&2
  exit 1
fi

echo "--- Install Cert Manager"
cat <<EOF | oc apply -f -
---
apiVersion: operator.ibm.com/v1alpha1
kind: OperandRequest
metadata:
  name: common-service
  namespace: ibm-common-services
spec:
  requests:
    - operands:
        - name: ibm-cert-manager-operator
      registry: common-service
EOF

echo "--- Verify Cert Manager installation"
cmd="oc get subscription -n ibm-common-services ibm-cert-manager-operator --ignore-not-found=true -o jsonpath={.status.currentCSV}"
waitUntilAvailable "${cmd}"
csv=$(${cmd})
cmd="oc get csv -n ibm-common-services ${csv} --ignore-not-found=true -o jsonpath={.status.phase}"
state="Succeeded"
waitUntil "${cmd}" "${state}"
cmd="oc get CertManager default --ignore-not-found=true -o jsonpath={.status.certManagerStatus}"
state="Successfully deployed cert-manager"
waitUntil "${cmd}" "${state}"

echo "Done."
