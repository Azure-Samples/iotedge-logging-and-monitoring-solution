#!/bin/bash

set -euxo pipefail

if [ "$#" -ne 3 ]
then
	echo "Script requires 3 parameters: edge_device_name, iothub_name, script_path"
	exit 1
fi

edge_device_name=$1
iothub_name=$2
script_path=$3

az config set extension.use_dynamic_install=yes_without_prompt

$script_path/wait-for-iot-hub-active-status.sh $iothub_name

echo "Creating edge device twin tag"
az iot hub device-twin update --device-id $edge_device_name --hub-name $iothub_name --tags '{"logPullEnabled": "true"}' --output none
