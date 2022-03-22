# deploy end-to-end
# proviisiion 9 devices
# update twin of the 0 device

# az iot hub module-twin update -n {iothub_name} -d {device_id} -m {module_id} --desired '{"condition":{"temperature":{"critical": null}}}'