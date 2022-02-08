#!/bin/bash
set -eo pipefail

if [ -z "$ACR_USER" ]; then
    ACR_USER=$(az acr credential show -n "$1" --query username)
    ACR_USER=${ACR_USER//\"/}
    ACR_PASSWORD=$(az acr credential show -n "$1" --query passwords[0].value)
    ACR_PASSWORD=${ACR_PASSWORD//\"/}
    ACR_ADDRESS=$(az acr show -n "$1" --query loginServer)
    ACR_ADDRESS=${ACR_ADDRESS//\"/};
fi
echo "##vso[task.setvariable variable=ACR_USER]${ACR_USER}"
echo "##vso[task.setvariable variable=ACR_PASSWORD]${ACR_PASSWORD}"
echo "##vso[task.setvariable variable=ACR_ADDRESS]${ACR_ADDRESS}"