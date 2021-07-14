# mas-standalone-installation

Prereq software installation scripts for Maximo Application Suite 8.4 on Red Hat CodeReady Containers

Detailed instructions here:
https://www.linkedin.com/pulse/running-maximo-manage-stand-alone-openshift-server-red-nishimura/

Usage:

```shell
$ sudo apt install jq git
$ crc setup
$ crc config set cpus 8
$ crc config set memory 24000
$ crc config set disk-size 130
$ crc config set disable-update-check true
$ crc start
$ eval $(crc oc-env)
$ oc login -u kubeadmin -p ************ https://api.crc.testing:6443
$ git clone --recursive https://github.com/nishi2go/mas-standalone-installation
$ cd mas-standalone-installation
$ export ENTITLEMENT_KEY=<Your Entitlement Key> # Get from https://myibm.ibm.com/products-services/containerlibrary
$ sh setup.sh
$ cd ..
$ mkdir work
$ gzip -dc mas-installer-8.4.0.tgz | tar zxvpf -
$ cd ibm-mas
$ ./install-mas.sh -i crc -d apps-crc.testing --accept-license
```
