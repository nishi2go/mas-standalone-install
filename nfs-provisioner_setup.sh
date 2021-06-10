#!/bin/bash

## This Script installs NFS Provisioner operator for MAS.
SCRIPT_DIR=$(cd $(dirname $0); pwd)

source "${SCRIPT_DIR}/behavior-analytics-services/Installation Scripts/bas-script-functions.bash"
source "${SCRIPT_DIR}/util.sh"

function stepLog() {
  echo -e "STEP $1/6: $2"
}

DATETIME=`date +%Y%m%d_%H%M%S`

mkdir -p logs
logFile="${SCRIPT_DIR}/logs/nfs-provisioner-installation-${DATETIME}.log"
touch "${logFile}"

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
    echoRed "Login to OpenShift to continue NFS Provisioner installation."
        exit 1;
fi

displayStepHeader 1 "Create managed-nfs-storage Storage Class."
oc create -f "${SCRIPT_DIR}/openshift-nfs-server/yaml/nfs-subdir-external-provisioner/class.yaml" | tee -a ${logFile}

displayStepHeader 2 "Create namespace for NFS storage class"
projectName="nfs"
createProject

displayStepHeader 3 "Build nfs services."
oc project nfs | tee -a ${logFile}
oc new-build --strategy docker --binary -n ${projectName} --name nfs-server -l app=nfs-server | tee -a ${logFile}
oc start-build nfs-server -n ${projectName} --from-dir "${SCRIPT_DIR}/openshift-nfs-server/volume-nfs" --follow | tee -a ${logFile}

displayStepHeader 4 "Create service account for NFS."
oc create sa nfs-server | tee -a ${logFile}
oc adm policy add-scc-to-user anyuid -z nfs-server  | tee -a ${logFile}
oc adm policy add-scc-to-user privileged -z nfs-server  | tee -a ${logFile}

displayStepHeader 5 "Install NFS server."
oc project nfs
sed "s|DOCKERIMAGEREFERENCE|$(oc get istag/nfs-server:latest -o jsonpath='{.image.dockerImageReference}')|" "${SCRIPT_DIR}/openshift-nfs-server/yaml/nfs-server.yml" | sed -e "s|gp2||g" | oc apply -n ${projectName} -f -

echoBlue "Waiting for NFS server ..."
while [[ $(oc get statefulset nfs-server -n ${projectName} -o 'jsonpath={..status.readyReplicas}') != "1" ]];do sleep 5s; done

displayStepHeader 6 "Install NFS client provisioner."
NFS_SERVER=$(oc get svc/nfs-server -o jsonpath='{.spec.clusterIP}')

set +e
cat "${SCRIPT_DIR}/openshift-nfs-server/yaml/nfs-subdir-external-provisioner/rbac.yaml" | sed -e "s|NAMESPACE|${projectName}|g" | oc apply -f -
oc apply -f "${SCRIPT_DIR}/openshift-nfs-server/yaml/nfs-subdir-external-provisioner/scc.yaml"
oc adm policy add-scc-to-user nfs-admin -z nfs-client-provisioner -n "${projectName}"
cat "${SCRIPT_DIR}/openshift-nfs-server/yaml/nfs-subdir-external-provisioner/deployment.yaml" | sed -e "s|NAMESPACE|${projectName}|g" -e "s|NFSSERVERIP|${NFS_SERVER}|g" -e "s|NFSPATH|/|g" | oc apply -f -

echoBlue "Waiting for NFS client provisioner ..."
while [[ $(oc get deployment nfs-client-provisioner -n ${projectName} -o 'jsonpath={..status.conditions[?(@.type=="Available")].status}') != "True" ]];do sleep 5s; done

for  sc in $(oc get storageclass -o name); do
    oc patch $sc -p '{"metadata": {"annotations": {"storageclass.kubernetes.io/is-default-class": "false"}}}'
done
