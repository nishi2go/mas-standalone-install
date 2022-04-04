#!/usr/bin/env bash

function createProject() {
    existingns=$(oc get projects | grep -w "${projectName}" | awk '{print $1}')
    
    if [ "${existingns}" == "${projectName}" ]; then
        echo "Project ${existingns} already exists."
    else
        oc new-project "${projectName}"
        if [ $? -ne 0 ]; then
            echo "Project:${projectName} creation failed."
            exit 1
        fi
    fi
    
    oc project "${projectName}"
}

function waitUntil() {
    cmd="$1"
    target="$2"
    retryCount=1200
    retries=0
    
    until [[ $(${cmd}) = "${target}" ]]; do
        sleep 10
        retries=$((retries + 1))
        if [[ $retries -eq $retryCount ]]; then
            echo "Timed out." 1>&2
            exit 1
        fi
    done
}

function waitUntilAvailable() {
    cmd="$1"
    retryCount=600
    retries=0
    
    while [ -z "$(${cmd})" ]; do
        sleep 10
        retries=$((retries + 1))
        if [[ $retries -eq $retryCount ]]; then
            echo "Timed out." 1>&2
            exit 1
        fi
    done
}

function approvePlan() {
    installplan=$(oc get installplan -n ${projectName} | grep -i ${operatorName} | awk '{print $1}' | head -n 1)
    
    if [[ "${installplan}" != "" ]]; then
        oc patch installplan ${installplan} -n ${projectName} --type merge --patch '{"spec":{"approved":true}}'
    fi
}

