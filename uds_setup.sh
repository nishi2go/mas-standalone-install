#!/usr/bin/env bash

## This Script installs UDS operator for MAS.
SCRIPT_DIR=$(
    cd $(dirname $0)
    pwd
)

source "${SCRIPT_DIR}/util.sh"

if [ -z "${UDS_STORAGE_CLASS}" ]; then
    export UDS_STORAGE_CLASS="local-path"
fi

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

echo "--- Install User Data Services Operand opetator"
cat <<EOF | oc apply -f -
---
apiVersion: operator.ibm.com/v1alpha1
kind: OperandRequest
metadata:
  name: user-data-services
  namespace: ibm-common-services
spec:
  requests:
    - operands:
        - name: ibm-user-data-services-operator
      registry: common-service
EOF

echo "--- Verify UDS installation"
cmd="oc get -n ibm-common-services subscription ibm-user-data-services-operator --ignore-not-found=true -o jsonpath={.status.currentCSV}"
waitUntilAvailable "${cmd}"
csv=$(${cmd})
cmd="oc get csv -n ibm-common-services ${csv} --ignore-not-found=true -o jsonpath={.status.phase}"
state="Succeeded"
waitUntil "${cmd}" "${state}"

echo "--- Install Analytics Proxy"
cat <<EOF | oc apply -f -
---
apiVersion: uds.ibm.com/v1
kind: AnalyticsProxy
metadata:
 name: analyticsproxy
 namespace: ibm-common-services
spec:
 license:
   accept: true
 db_archive:
   persistent_storage:
     storage_size: 10G
 kafka:
   storage_size: 5G
   zookeeper_storage_size: 5G
 airgappeddeployment:
   enabled: false
 env_type: lite
 event_scheduler_frequency: '@hourly'
 storage_class: ${UDS_STORAGE_CLASS}
 proxy_settings:
   http_proxy: ''
   https_proxy: ''
   no_proxy: ''
 ibmproxyurl: 'https://iaps.ibm.com'
 allowed_domains: '*'
 postgres:
   backup_frequency: '@daily'
   backup_type: incremental
   storage_size: 10G
 tls:
   airgap_host: ''
   uds_host: ''
EOF

echo "--- Wait Analytics Proxy config completion"
cmd="oc get analyticsproxies.uds.ibm.com analyticsproxy -n ibm-common-services --ignore-not-found=true -o jsonpath={.status.phase}"
state="Ready"
waitUntil "${cmd}" "${state}"

echo "--- Generate UDS API Key"
cat <<EOF | oc apply -f -
apiVersion: uds.ibm.com/v1
kind: GenerateKey
metadata:
  name: uds-api-key
  namespace: ibm-common-services
spec:
  image_pull_secret: uds-images-pull-secret
EOF
