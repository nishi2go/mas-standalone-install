#!/usr/bin/bash

# unattended full setup

if [ -z "${ENTITLEMENT_KEY}" ]; then
  echo "Missing entitlement key in environemnt variable ENTITLEMENT_KEY."
  exit 1
fi

mkdir -p logs
rm -rf work/*

./nfs-provisioner_setup.sh
./local-path_setup.sh
./sb_setup.sh
./mongo_setup.sh
./sb_setup.sh
./cert-manager_setup.sh
./bas_setup.sh
./sls_setup.sh

./get_setup_params.sh