#!/usr/bin/env bash

## This Script installs MongoDB Community operator
## Based on the blog https://www.mongodb.com/blog/post/run-secure-containerized-mongodb-deployments-using-the-mongo-db-community-kubernetes-oper?hmsr=joyk.com&utm_source=joyk.com&utm_medium=referral

SCRIPT_DIR=$(
    cd $(dirname $0)
    pwd
)

source "${SCRIPT_DIR}/util.sh"

if [ -z "${MONGODB_NAMESPACE}" ]; then
    MONGODB_NAMESPACE="mongodb"
fi

if [ -z "${MONGODB_REPLICAS}" ]; then
    MONGODB_REPLICAS=3
fi

if [ -z "${MONGODB_CPU_REQUEST}" ]; then
    MONGODB_CPU_REQUEST="100m"
fi

if [ -z "${MONGODB_MEM_REQUEST}" ]; then
    MONGODB_MEM_REQUEST="256Mi"
fi

if [ -z "${MONGODB_CPU_LIMIT}" ]; then
    MONGODB_CPU_LIMIT="1"
fi

if [ -z "${MONGODB_MEM_LIMIT}" ]; then
    MONGODB_MEM_LIMIT="1Gi"
fi

if [ -z "${MONGODB_STORAGE_SIZE}" ]; then
    MONGODB_STORAGE_SIZE="20Gi"
fi

if [ -z "${MONGODB_STORAGE_LOG_SIZE}" ]; then
    MONGODB_STORAGE_LOG_SIZE="2Gi"
fi

if [ -z "${MONGODB_STORAGE_CLASS}" ]; then
    MONGODB_STORAGE_CLASS="local-path"
fi

if [ -z "${MONGODB_PASSWORD}" ]; then
    MONGODB_PASSWORD=$(openssl rand -base64 29 | tr -d "=+/" | cut -c1-25)
fi

if [ -z "${MONGODB_ALWAYS_GEN_PASSWORD}" ]; then
    MONGODB_ALWAYS_GEN_PASSWORD=0
fi

if [ -z "${MONGODB_ALWAYS_GEN_CERT}" ]; then
    MONGODB_ALWAYS_GEN_CERT=0
fi

status=$(oc whoami 2>&1)
if [[ $? -gt 0 ]]; then
    echo "Login to OpenShift to continue installation." 1>&2
    exit 1
fi

echo "--- Create namespace for MongoDB"
projectName=${MONGODB_NAMESPACE}
createProject

echo "--- Install MongoDB Community CRD"
oc apply -n ${MONGODB_NAMESPACE} -f https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/master/config/crd/bases/mongodbcommunity.mongodb.com_mongodbcommunity.yaml

echo "--- Install MongoDB Roles"
oc apply -n ${MONGODB_NAMESPACE} -f https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/master/config/rbac/role.yaml
oc apply -n ${MONGODB_NAMESPACE} -f https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/master/config/rbac/role_database.yaml

echo "--- Install MongoDB RoleBinding"
oc apply -n ${MONGODB_NAMESPACE} -f https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/master/config/rbac/role_binding.yaml
oc apply -n ${MONGODB_NAMESPACE} -f https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/master/config/rbac/role_binding_database.yaml

echo "--- Install MongoDB Service Account"
oc apply -n ${MONGODB_NAMESPACE} -f https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/master/config/rbac/service_account.yaml
oc apply -n ${MONGODB_NAMESPACE} -f https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/master/config/rbac/service_account_database.yaml

echo "--- Install MongoDB Certificate"
oldCert=$(oc get secret mas-mongo-ce-cert-secret -n ${MONGODB_NAMESPACE} --ignore-not-found)
if [ ${MONGODB_ALWAYS_GEN_CERT} = 1 ] || [ -z "${oldCert}" ]; then
    WORK_DIR="${SCRIPT_DIR}/work"
    mkdir -p "${WORK_DIR}"
    openssl genrsa -out ${WORK_DIR}/ca.key 4096
    openssl req -new -x509 -days 3650 -key ${WORK_DIR}/ca.key -reqexts v3_req -extensions v3_ca -out ${WORK_DIR}/ca.crt -subj "/C=US/ST=NY/L=New York/O=AIAPPS/OU=MAS/CN=MAS"
    
    oc create secret tls ca-mas-mongodb-key-pair --cert=${WORK_DIR}/ca.crt --key=${WORK_DIR}/ca.key -n ${MONGODB_NAMESPACE}
    oc create configmap mas-mongo-ce-cert-map --from-file=ca.crt=${WORK_DIR}/ca.crt -n ${MONGODB_NAMESPACE}
    
cat <<EOF | oc apply -n ${MONGODB_NAMESPACE} -f -
---
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: mas-mongodb-issuer
spec:
  ca:
    secretName: ca-mas-mongodb-key-pair
EOF
    MONGO_NODES=""
    for i in $(seq 0 $((${MONGODB_REPLICAS} - 1))); do
        MONGO_NODES="${MONGO_NODES}\n    - mas-mongo-ce-${i}.mas-mongo-ce-svc.${MONGODB_NAMESPACE}.svc.cluster.local"
    done
    MONGO_NODES=$(echo -ne "${MONGO_NODES}")
    
    COMMON_NAME="mas-mongo-ce-svc.${MONGODB_NAMESPACE}.svc.cluster.local"
    
cat <<EOF | oc apply -n ${MONGODB_NAMESPACE} -f -
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: mas-mongodb-cert
spec:
  secretName: mas-mongo-ce-cert-secret
  duration: 262800h
  renewBefore: 360h
  privateKey:
    rotationPolicy: Always
  issuerRef:
    name: mas-mongodb-issuer
    kind: Issuer
  subject:
    organizations:
      - MAS
  commonName: "${COMMON_NAME}"
  dnsNames: ${MONGO_NODES}
    - "localhost"
EOF
    
    rm -r ${WORK_DIR}
fi

echo "--- Install MongoDB Password Secret"
oldPassword=$(oc get secret mas-mongo-ce-admin-password -n ${MONGODB_NAMESPACE} --ignore-not-found)
if [ ${MONGODB_ALWAYS_GEN_PASSWORD} = 1 ] || [ -z "${oldPassword}" ]; then
cat <<EOF | oc apply -n ${MONGODB_NAMESPACE} -f -
---
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: mas-mongo-ce-admin-password
  namespace: ${MONGODB_NAMESPACE}
stringData:
  password: "${MONGODB_PASSWORD}"
EOF
fi

echo "--- Install MongoDB manager for Openshift"
cat <<EOF | oc apply -n ${MONGODB_NAMESPACE} -f -
---
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    email: support@mongodb.com
  labels:
    owner: mongodb
  name: mongodb-kubernetes-operator
  namespace: "${MONGODB_NAMESPACE}"
spec:
  replicas: 1
  selector:
    matchLabels:
      name: mongodb-kubernetes-operator
  strategy:
    rollingUpdate:
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: mongodb-kubernetes-operator
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: name
                operator: In
                values:
                - mongodb-kubernetes-operator
            topologyKey: kubernetes.io/hostname
      containers:
      - command:
        - /usr/local/bin/entrypoint
        env:
        - name: WATCH_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: MANAGED_SECURITY_CONTEXT
          value: 'true'
        - name: OPERATOR_NAME
          value: mongodb-kubernetes-operator
        - name: AGENT_IMAGE
          value: quay.io/mongodb/mongodb-agent:11.12.0.7388-1
        - name: READINESS_PROBE_IMAGE
          value: quay.io/mongodb/mongodb-kubernetes-readinessprobe:1.0.8
        - name: VERSION_UPGRADE_HOOK_IMAGE
          value: quay.io/mongodb/mongodb-kubernetes-operator-version-upgrade-post-start-hook:1.0.4
        - name: MONGODB_IMAGE
          value: mongo
        - name: MONGODB_REPO_URL
          value: docker.io
        image: quay.io/mongodb/mongodb-kubernetes-operator:0.7.3
        imagePullPolicy: Always
        name: mongodb-kubernetes-operator
        resources:
          limits:
            cpu: 1100m
            memory: 1Gi
          requests:
            cpu: 10m
            memory: 100Mi
      serviceAccountName: mongodb-kubernetes-operator
EOF

echo "--- Wait until MongoDB manager available"
cmd="oc get deployment mongodb-kubernetes-operator -n ${MONGODB_NAMESPACE} --ignore-not-found -o jsonpath={..status.conditions[?(@.type=='Available')].status}"
state="True"
waitUntil "${cmd}" "${state}"

echo "--- Install MongoDB Operator for Openshift"
cat <<EOF | oc apply -n ${MONGODB_NAMESPACE} -f -
---
apiVersion: mongodbcommunity.mongodb.com/v1
kind: MongoDBCommunity
metadata:
  name: mas-mongo-ce
spec:
  members: ${MONGODB_REPLICAS}
  type: ReplicaSet
  version: "4.2.6"
  security:
    tls:
      enabled: true
      certificateKeySecretRef:
        name: mas-mongo-ce-cert-secret
      caConfigMapRef:
        name: mas-mongo-ce-cert-map
    authentication:
      modes: ["SCRAM-SHA-1", "SCRAM-SHA-256"]
  users:
    - name: admin
      db: admin
      passwordSecretRef:
        name: mas-mongo-ce-admin-password
      roles:
        - name: clusterAdmin
          db: admin
        - name: userAdminAnyDatabase
          db: admin
        - name: dbAdminAnyDatabase
          db: admin
        - name: dbOwner
          db: admin
        - name: readWriteAnyDatabase
          db: admin
      scramCredentialsSecretName: mas-mongo-ce-scram
  additionalMongodConfig:
    storage.wiredTiger.engineConfig.journalCompressor: snappy
    net.tls.allowInvalidCertificates: true
    net.tls.allowInvalidHostnames: true
  statefulSet:
    spec:
      serviceName: mas-mongo-ce-svc
      selector: {}
      template:
        spec:
          containers:
          - name: mongod
            resources:
              requests:
                cpu: "${MONGODB_CPU_REQUEST}"
                memory: "${MONGODB_MEM_REQUEST}"
              limits:
                cpu: "${MONGODB_CPU_LIMIT}"
                memory: "${MONGODB_MEM_LIMIT}"
      volumeClaimTemplates:
        - metadata:
            name: data-volume
          spec:
            accessModes: [ "ReadWriteOnce" ]
            storageClassName: "${MONGODB_STORAGE_CLASS}"
            resources:
              requests:
                storage: "${MONGODB_STORAGE_SIZE}"
        - metadata:
            name: logs-volume
          spec:
            accessModes: [ "ReadWriteOnce" ]
            storageClassName: "${MONGODB_STORAGE_CLASS}"
            resources:
              requests:
                storage: "${MONGODB_STORAGE_LOG_SIZE}"
EOF

echo "--- Wait until MongoDB instance available"
cmd="oc get statefulset mas-mongo-ce -n ${MONGODB_NAMESPACE} --ignore-not-found -o jsonpath={..status.readyReplicas}"
state="${MONGODB_REPLICAS}"
waitUntil "${cmd}" "${state}"

echo "Done."
