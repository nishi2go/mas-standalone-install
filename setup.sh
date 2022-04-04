#!/usr/bin/env bash

# unattended full setup

while getopts p OPT
do
    case $OPT in
        "p" ) PROD="1" ;;
    esac
done

SCRIPT_DIR=$(
    cd $(dirname $0)
    pwd
)

if [ -z "${ENTITLEMENT_KEY}" ]; then
    echo "Missing entitlement key in environemnt variable ENTITLEMENT_KEY."
    exit 1
fi

if [ -n "${PROD}" ]; then
    if [ -z "${SLS_STORAGE_CLASS}" ]; then
        echo "Missing SLS Storage Class environemnt variable SLS_STORAGE_CLASS."
        exit 1
    fi
    
    if [ -z "${SLS_DOMAIN_NAME}" ]; then
        echo "Missing SLS base domain name environemnt variable SLS_DOMAIN_NAME."
        exit 1
    fi
    
    if [ -z "${UDS_STORAGE_CLASS}" ]; then
        echo "Missing UDS Storage Class environemnt variable UDS_STORAGE_CLASS."
        exit 1
    fi
    
    if [ -z "${MONGODB_STORAGE_CLASS}" ]; then
        echo "Missing MongoDB Storage Class environemnt variable MONGODB_STORAGE_CLASS."
        exit 1
    fi
    
    if [ -z ${MAS_INSTANCE_ID} ]; then
        echo "Missing MAS Instance ID in environemnt variable MAS_INSTANCE_ID."
        exit 1
    fi
    
    if [ -z "${MAS_DOMAIN_NAME}" ]; then
        echo "Missing Maximo base domain name environemnt variable MAS_DOMAIN_NAME."
        exit 1
    fi
    
    if [ -z "${MONGODB_CPU_LIMIT}" ]; then
        export MONGODB_CPU_LIMIT="2"
    fi
    
    if [ -z "${MONGODB_MEM_LIMIT}" ]; then
        export MONGODB_MEM_LIMIT="2Gi"
    fi
fi

if [[ -d "${SCRIPT_DIR}/work" ]]; then
    rm -r ${SCRIPT_DIR}/work/*
fi

if [ -z "${PROD}" ]; then
    ${SCRIPT_DIR}/local-path_setup.sh || exit 1
fi

${SCRIPT_DIR}/ibm-common-services_setup.sh || exit 1
${SCRIPT_DIR}/cert-manager_setup.sh || exit 1
${SCRIPT_DIR}/sbo_setup.sh || exit 1
${SCRIPT_DIR}/uds_setup.sh || exit 1
${SCRIPT_DIR}/mongodb_setup.sh || exit 1
${SCRIPT_DIR}/sls_setup.sh || exit 1
${SCRIPT_DIR}/mas_setup.sh || exit 1

${SCRIPT_DIR}/get_setup_params.sh
