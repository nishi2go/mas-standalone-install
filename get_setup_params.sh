#!/usr/bin/env bash

SCRIPT_DIR=$(
  cd $(dirname $0)
  pwd
)

WORK_DIR="${SCRIPT_DIR}/work"
mkdir -p "${WORK_DIR}"

if [ -z ${MAS_INSTANCE_ID} ]; then
    MAS_INSTANCE_ID=crc
fi

if [ -z ${MONGODB_NAMESPACE} ]; then
    MONGODB_NAMESPACE=mongodb
fi

if [ -z ${UDS_NAMESPACE} ]; then
    UDS_NAMESPACE=ibm-common-services
fi

if [ -z ${SLS_NAMESPACE} ]; then
    SLS_NAMESPACE=ibm-sls
fi

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
  echo "Login to OpenShift to continue."
  exit 1
fi

echo "MongoDB Setup Parameters"
echo "===========Hosts=============="
oc get MongoDBCommunity -n ${MONGODB_NAMESPACE} -o 'jsonpath={..status.mongoUri}' | sed -e 's|mongodb\://||g' -e 's/,/\n/g'

echo ""
echo "===========MongoDB login account credentials=============="
echo "Username: admin"
MONGO_PASSWORD=$(oc get secret mas-mongo-ce-admin-password -n ${MONGODB_NAMESPACE} --output="jsonpath={.data.password}" | base64 -d)
echo "Password: ${MONGO_PASSWORD}"

echo "===========Certificates=============="
oc get configmap mas-mongo-ce-cert-map -n ${MONGODB_NAMESPACE} -o jsonpath='{.data.ca\.crt}'
echo ""

echo "UDS Setup Parameters"
echo "===========Endpoint URL=============="
echo https://$(oc get routes uds-endpoint -n "${UDS_NAMESPACE}" |awk 'NR==2 {print $2}')

echo "===========API KEY=============="
oc get secret uds-api-key -n "${UDS_NAMESPACE}" --output="jsonpath={.data.apikey}" | base64 -d
echo ""

echo "===========Certificates=============="
oc get secret router-certs-default -n "openshift-ingress" -o "jsonpath={.data.tls\.crt}" | base64 -d

oc get secret -n ${SLS_NAMESPACE} sls-cert-client -o jsonpath='{.data.tls\.key}' | base64 -d -w 0 > ${WORK_DIR}/tls.key
oc get secret -n ${SLS_NAMESPACE} sls-cert-client -o jsonpath='{.data.tls\.crt}' | base64 -d -w 0 > ${WORK_DIR}/tls.crt
oc get secret -n ${SLS_NAMESPACE} sls-cert-client -o jsonpath='{.data.ca\.crt}' | base64 -d -w 0 > ${WORK_DIR}/ca.crt

echo "SLS Setup Parameters"
echo ""
echo "===========SLS Endpoint URL=============="
oc get configmap -n ${SLS_NAMESPACE} sls-suite-registration -o jsonpath='{.data.url}'
echo ""
echo "===========Registration Key=============="
oc get configmap -n ${SLS_NAMESPACE} sls-suite-registration -o jsonpath='{.data.registrationKey}'
echo ""
echo "===========Certificates=============="
oc get configmap -n ${SLS_NAMESPACE} sls-suite-registration -o jsonpath='{.data.ca}'
echo ""

echo "===========Registration Info=============="
function getSlsInfo() {
    curl -ks --cert ${WORK_DIR}/tls.crt --key ${WORK_DIR}/tls.key --cacert ${WORK_DIR}/tls.crt  $(oc get configmap -n ${SLS_NAMESPACE} sls-suite-registration -o jsonpath='{.data.url}')/api/entitlement/config | jq ${path}
}
path=".rlks.configuration"
echo "Configuration: $(getSlsInfo)"
path=".rlks.hosts[0].id"
echo "Registration ID: $(getSlsInfo)"
path=".rlks.hosts[0].hostname"
echo "Hostname: $(getSlsInfo)"
path=".rlks.hosts[0].port"
echo "port: $(getSlsInfo)"

rm -r ${WORK_DIR}

echo ""
echo "MAS Setup Parameters"
echo "===========Initial Setup URL=============="
echo https://$(oc get route -n mas-${MAS_INSTANCE_ID}-core ${MAS_INSTANCE_ID}-admin -o jsonpath='{.spec.host}')/initialsetup
echo "===========Superuser Username=============="
oc get secret ${MAS_INSTANCE_ID}-credentials-superuser -n mas-${MAS_INSTANCE_ID}-core -o jsonpath='{.data.username}' | base64 --decode && echo ""
echo "===========Superuser Password=============="
oc get secret ${MAS_INSTANCE_ID}-credentials-superuser -n mas-${MAS_INSTANCE_ID}-core -o jsonpath='{.data.password}' | base64 --decode && echo ""

