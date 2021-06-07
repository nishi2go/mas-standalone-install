#!/bin/bash

SCRIPT_DIR=$(cd $(dirname $0); pwd)

source "${SCRIPT_DIR}/behavior-analytics-services/Installation Scripts/bas-script-functions.bash"

function stepLog() {
  echo -e "STEP $1/2: $2"
}

WORK_DIR="${SCRIPT_DIR}/work"
DATETIME=`date +%Y%m%d_%H%M%S`

logFile="${SCRIPT_DIR}/logs/disable-cpu-${DATETIME}.log"
touch "${logFile}"

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
    echoRed "Login to OpenShift to continue disabling cpu limit installation."
        exit 1;
fi

displayStepHeader 1 "Add a label to worker"
oc label machineconfigpool worker custom-kubelet=disable-cpu-limit | tee -a ${logFile}

displayStepHeader 2 "Disable CPU Limit to the worker"
cat <<EOF | oc apply -f - | tee -a ${logFile}
apiVersion: machineconfiguration.openshift.io/v1
kind: KubeletConfig
metadata:
  name: disable-cpu-units
spec:
  machineConfigPoolSelector:
    matchLabels:
      custom-kubelet: disable-cpu-limit
  kubeletConfig:
    cpuCfsQuota:
      - "false"
EOF
