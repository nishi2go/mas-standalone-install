#!/bin/bash

## This Script installs cert manager for MAS.
SCRIPT_DIR=$(cd $(dirname $0); pwd)

source "${SCRIPT_DIR}/behavior-analytics-services/Installation Scripts/bas-script-functions.bash"

function stepLog() {
  echo -e "STEP $1/2: $2"
}

DATETIME=`date +%Y%m%d_%H%M%S`

mkdir -p logs
logFile="${SCRIPT_DIR}/logs/cert-manager-installation-${DATETIME}.log"
touch "${logFile}"

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
    echoRed "Login to OpenShift to continue Cert manager Operator installation."
        exit 1;
fi

displayStepHeader 1 "Create cert-manager namespace."
oc create namespace cert-manager | tee -a ${logFile}

displayStepHeader 2 "Install Cert Manager."
oc apply -f https://github.com/jetstack/cert-manager/releases/download/v1.1.1/cert-manager.yaml | tee -a ${logFile}

