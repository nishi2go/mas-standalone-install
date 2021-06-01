#!/bin/bash

## This Script installs BAS operator for MAS.
SCRIPT_DIR=$(cd $(dirname $0); pwd)

source "${SCRIPT_DIR}/behavior-analytics-services/Installation Scripts/bas-script-functions.bash"

WORK_DIR="${SCRIPT_DIR}/work/bas"

mkdir -p "${WORK_DIR}"

cp -r "${SCRIPT_DIR}/behavior-analytics-services/Installation Scripts/"* "${WORK_DIR}/"

if [ -z "${BAS_DB_PASSWORD}" ]; then
  BAS_DB_PASSWORD=`openssl rand -hex 15`
fi

if [ -z "${BAS_GRAFANA_PASSWORD}" ]; then
  BAS_GRAFANA_PASSWORD=`openssl rand -hex 15`
fi

cat <<EOF > "${WORK_DIR}/cr.properties"
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
EOF

cd "${WORK_DIR}/"

sed -i -e "s/retryCount=20/retryCount=120/" -e "/read -r continueInstall/d" "${WORK_DIR}/bas-script-functions.bash"

export continueInstall=Y

bash BAS_installation.sh
