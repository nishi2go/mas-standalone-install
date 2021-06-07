# mas-standalone-installation

Installation scripts for Maximo Application Suite 8.4 on Red Hat CodeReady Containers

Usage:

```shell
$ sudo apt install jq git
$ eval $(crc oc-env)
$ oc login -u kubeadmin -p ************ https://api.crc.testing:6443
$ git clone --recursive https://github.com/nishi2go/mas-standalone-installation
$ cd mas-standalone-installation
$ export ENTITLEMENT_KEY=<Your Entitlement Key> # Get from https://myibm.ibm.com/products-services/containerlibrary
$ sh setup.sh
```
