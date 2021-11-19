#!/bin/bash

set -euxo pipefail

if [ "$#" -ne 1 ]
then
	echo "Script requires 1 parameter: iothub_name"
	exit 1
fi

iothub_name=$1

az config set extension.use_dynamic_install=yes_without_prompt

wait_period=0
timout_seconds=120

# The script waits for the IoT Hub Active state until specified timeout 
while [ $(az iot hub show --name $iothub_name --query properties.state -o tsv) != "Active" ]
do
    wait_period=$(($wait_period+10))
    if [ $wait_period -gt $timout_seconds ];then
        echo "Timeout reached. IoT Hub is not in Active state"
        exit 1
    else
        echo "Sleeping for 10 seconds"
        sleep 10
    fi
done

exit 0