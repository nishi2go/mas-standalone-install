#!/usr/bin/bash

# unattended full setup

./nfs-provisioner_setup.sh
./local-path_setup.sh
./sb_setup.sh
./mongo_setup.sh
./sb_setup.sh
./cert-manager_setup.sh
./bas_setup.sh
./sls_setup.sh

./get_setup_params.sh