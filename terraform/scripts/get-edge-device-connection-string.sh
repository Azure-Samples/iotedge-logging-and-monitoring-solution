set -euxo pipefail

eval "$(jq -r '@sh "edge_device_name=\(.edge_device_name) iothub_name=\(.iothub_name) script_path=\(.script_path)"')"

az config set extension.use_dynamic_install=yes_without_prompt

$script_path/wait-for-iot-hub-active-status.sh $iothub_name

az iot hub device-identity connection-string show --device-id $edge_device_name --hub-name $iothub_name