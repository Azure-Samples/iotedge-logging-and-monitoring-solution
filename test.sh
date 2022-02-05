az deployment group create \
  --resource-group iot-e2e-rg1 \
  --template-file MonitoringInstruments/alerts.json \
  --parameters iotHubName=iothub-a766ea18