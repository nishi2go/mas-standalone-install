#!/bin/bash

function checkOperatorInstallationSucceeded() {
  retryCount=120
  retries=0
  check_for_csv_success=$(oc get csv -n "$projectName" --ignore-not-found | grep --color=never "${operatorName}" | awk -F' ' '{print $NF}')
  until [[ $retries -eq $retryCount || $check_for_csv_success = "Succeeded" ]]; do
    sleep 5
    check_for_csv_success=$(oc get csv -n "$projectName" --ignore-not-found | grep --color=never "${operatorName}" | awk -F' ' '{print $NF}')
    retries=$((retries + 1))
  done
  echo "$check_for_csv_success"
}

function createProject() {
  existingns=$(oc get projects | grep -w "${projectName}" | awk '{print $1}')

  if [ "${existingns}" == "${projectName}" ]; then
    echoYellow "Project ${existingns} already exists."
  else
    oc new-project "${projectName}" &>>"${logFile}"
    if [ $? -ne 0 ]; then
      echoRed "FAILED: Project:${projectName} creation failed"
      exit 1
    fi
  fi
}
