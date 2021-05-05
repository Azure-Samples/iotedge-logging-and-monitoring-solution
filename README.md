# IoT ELMS

IoT **E**dge **L**ogging and **M**onitoring **S**olution (pronounced *Lm's*) is an architecture and a sample cloud workflow that enables secure and automated retrieval of workload logs and metrics from IoT Edge devices without any additional host-level components. It leverages IoT Edge Agent's [built-in functionality to retrieve logs](https://docs.microsoft.com/azure/iot-edge/how-to-retrieve-iot-edge-logs?view=iotedge-2020-11) and [IoT Edge metrics collector](https://aka.ms/edgemon-logs) for metrics.

ELMS also provides a sample cloud workflow to process logs uploaded by the device to a blob storage container, as well as metrics arriving as device-to-cloud messages in IoT Hub. The sample can be deployed either in a sandbox environment or integrated with existing resources using an intuitive CLI wizard.

