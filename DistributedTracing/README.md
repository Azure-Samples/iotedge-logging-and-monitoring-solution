# IoT Edge Distributed Tracing sample

The sample demonstrates implementation of end-to-end distributed tracing with [OpenTelemetry](https://opentelemetry.io).  

Please see the [Overview of Distributed Tracing with IoT Edge](./../docs/iot-edge-distributed-tracing.md) to understand the concept and different architecture patterns. 

At this point, the sample implements the "online" scenario when an IoT Edge device is normally online and has a stable access to an Application Insights instance.  

The topology of the sample is represented on the following diagram:

![distr-tarcing-sampple](./../docs/iot-distr-tracing-sample.png)


There is an IoT Edge device with `Temperature Sensor` custom module (C#) that generates some temperature value and sends it upstream with a telemetry message. This message is routed to another custom module `Filter` (C#). This module checks the received temperature against a threshold (25 degrees) and if it exceeds the threshold, the FilterModule sends the telemetry message to the cloud.

In the cloud the message is processed by the backend. The backend consists of a chain of two Azure Functions and a Storage Account. 
Azure .Net Function picks up the telemetry message from the IoT Hub events endpoint, processes it and sends it to Azure Java Function. The Java function saves the message to the storage account container. 

The C# components of the sample, such as device modules and backend Azure .Net Function use [OpenTelemetry for .Net](https://github.com/open-telemetry/opentelemetry-dotnet/blob/main/src/OpenTelemetry.Api/README.md#introduction-to-opentelemetry-net-tracing-api) to produce tracing data. They send the tracing data to Application Insights with [Azure Monitor Open Telemetry direct exporter](https://docs.microsoft.com/en-us/azure/azure-monitor/app/opentelemetry-enable?tabs=net). They also send correlated logs directly to Application Insights with a configured ILogger instance.

The Java function uses [OpenTelemetry auto-instrumentation Java agent](https://docs.microsoft.com/en-us/azure/azure-monitor/app/java-in-process-agent) to produce and export tracing data and correlated logs to the Application Insights instance.  

The IoT Edge module `Tempperature Sensor` starts the whole process and therefore it starts an OpenTelemetry trace. It puts a [W3C traceparent](https://www.w3.org/TR/trace-context/#relationship-between-the-headers) value into the outgoing message property. The `Filter` receives the message on the device, extracts the `traceparent` property and uses it to continue the trace with a new span. The module puts a new value of the `traceparent` (with the new parent_id) into the outgoing message. The .Net Azure Function retrieves the message from the IoT Hub endpoint, extracts the `traceparent` property, continues the same trace with a new span and sends the new `traceparent` value in the header of the HTTP request to the Azure Java Function. The Azure Java Function is auto-instrumented with OpenTelemetry, so the framework "understands" the `traceparent` header, starts a new span in the same trace and creates the following spans while communicating to Azure Blob Storage and Managed Identity service. 
  
## Result
As a result, the entire end-to-end process from the sensor to the storage can be monitored with Application Map in Application Insights:

![application-map](./../docs/application-map.png)

Blobs in Azure Storage with the IoT messages are tagged with the `trace_id` (`Operation Id` in Application Insights) value. We can find and investigate in details end-to-end transaction for every message.   

![transaction](./../docs/iot-distr-tracing-transaction.png)

We can go deeper and drill down and explore correlated logs for a specific trace or a specific span. In Application Insights terminology `Operation Id` corresponds to `TraceId` and `Id` corresponds to `SpanId`:

![logs](./../docs/iot-distr-tracing-logs.png)

## OpenTelemetry Collector
Besides Application Insights, `Tempperature Sensor` and `Filter` IoT Edge modules export the tracing data via OTLP protocol to the `OpenTelemetryCollector` module, running on the same edge device. The collector module can be configured to export the tracing data to alternative observability backends, working on the factory floor (for example [Jaeger](https://www.jaegertracing.io) or [Zipkin](https://zipkin.io)). 
_Note_: Jaeger/Zipkin installation is not included in this sample. If you have a Jaeger installation that you want to work with this sample, provide a value of the `JAEGER_ENDPOINT` environment variable
(e.g. http://myjaeger:14268/api/traces) in the device deployment template.

![jaeger](./../docs/iot-distr-tracing-jaeger.png)

## Deployment
To deploy the sample run the PowerShell script `./Scripts/deploy.ps1` and select the `Distributed Tracing` option when asked. 

  


 

