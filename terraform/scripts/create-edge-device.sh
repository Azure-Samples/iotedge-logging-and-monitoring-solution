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
sleep 10 # IoT Hub has swaping state just after creation. It is Active for a very short time period, and then it moves to Transitioning state. Waiting 10 seconds to get stable state.
$script_path/wait-for-iot-hub-active-status.sh $iothub_name

echo "Creating edge device"
az iot hub device-identity create --device-id $edge_device_name --hub-name $iothub_name --edge-enabled --output none