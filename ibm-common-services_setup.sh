#!/usr/bin/env bash

## This Script installs ibm cert manager operator 

SCRIPT_DIR=$(
  cd $(dirname $0)
  pwd
)

source "${SCRIPT_DIR}/util.sh"

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
  echo "Login to OpenShift to continue cert manager installation." 1>&2
  exit 1
fi

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
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: opencloud-operators
  namespace: openshift-marketplace
spec:
  displayName: IBMCS Operators
  publisher: IBM
  sourceType: grpc
  image: docker.io/ibmcom/ibm-common-service-catalog:latest
  updateStrategy:
    registryPoll:
      interval: 45m
EOF

echo "--- Install IBM Common Services"
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ibm-common-services
---
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: operatorgroup
  namespace: ibm-common-services
spec:
  targetNamespaces:
    - ibm-common-services
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-common-service-operator
  namespace: ibm-common-services
spec:
  channel: v3
  installPlanApproval: Automatic
  name: ibm-common-service-operator
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF

echo "--- Wait until Operand CRD available"
cmd="oc get crd operandrequests.operator.ibm.com -n ibm-common-services --ignore-not-found=true -o jsonpath={.status.conditions[?(@.type=='Established')].status}"
state="True"
waitUntil "${cmd}" "${state}"

echo "Done."
