#!/bin/bash

SUFFIX=$1
N=$2
RESOURCE_GROUP=$3
IOTHUB_NAME=$4

az extension add --name azure-iot -y

for i in `seq 2 $N`
do
    DEVICE_ID=iotedgevm$i-$SUFFIX    
    az iot hub device-identity create --hub-name $IOTHUB_NAME --device-id $DEVICE_ID --edge-enabled --output none
    echo "Created Edge device"
    sleep 5
    az iot hub device-twin update --device-id $DEVICE_ID --hub-name $IOTHUB_NAME --set tags=''{\"logPullEnabled\":\"true\"}''
    echo "Set tag for device" && CS_OUTPUT="$(az iot hub device-identity connection-string show --device-id $DEVICE_ID --hub-name $IOTHUB_NAME -o tsv)"
    echo "Got device connection string"
    echo $CS_OUTPUT


    az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-uri https://raw.githubusercontent.com/Azure/iotedge-vm-deploy/1.2.0/edgeDeploy.json \
    --parameters deviceConnectionString=$CS_OUTPUT dnsLabelPrefix=$DEVICE_ID authenticationType=password adminUsername=adminuser adminPasswordOrKey=AdminPasssword1! vmSize=Standard_DS1_v2
done