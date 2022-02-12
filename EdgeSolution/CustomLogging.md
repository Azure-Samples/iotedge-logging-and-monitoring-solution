# Custom Logging in IoT Edge Modules

This folder provides an IoT Edge solution with a .NET Core and and Python modules, both giving you an idea on how to do logging in a way that aligns with the [Syslog severity level](https://en.wikipedia.org/wiki/Syslog#Severity_level) standard.



## Python Logging Module

The [Python Sample Logs](modules/PythonSampleLogs/) module leverages the [CustomLogFormatter](modules/PythonSampleLogs/CustomLogger.py#L7) class, which is built on top of the [logging](https://docs.python.org/3/library/logging.html) Python module to make it easier to import and reference the logging object. The **CustomLogFormatter** class provides a formatter that does the following:

- Support for custom log formats. More info [here](https://docs.python.org/3/library/logging.html#formatter-objects).
- Change time format to match exactly what the edge agent module expects
- Switch the log level from Python [log levels](https://docs.python.org/3/library/logging.html#logging-levels) to [syslog severity codes](https://en.wikipedia.org/wiki/Syslog#Severity_level) standard
- Convert exceptions to single line logs



The [CustomLogger](modules/PythonSampleLogs/CustomLogger.py#L64) method facilitates the creation of a logger object with the right format. The sample code below demonstrates how to use it:

```python
from CustomLogger import CustomLogger

logger = CustomLogger("DEBUG")

# Implicit log level methods
logger.debug("this is a debug message")
logger.info("this is an info message")
logger.error("this is an error message")
logger.critical("this is a critical message")

# Explicit log level method
logger.log(logging.INFO, "another info message")
```



## .NET Core Logging Module

The [C# Sample Logs](modules/CsharpSampleLogs/) module leverages the [IoTEdgeLogger](../IoTEdgeLogger/) .solution, a .NET Standard library that is based and inspired by the official [Logger class in IoT Edge](https://github.com/Azure/iotedge/blob/master/edge-util/src/Microsoft.Azure.Devices.Edge.Util/Logger.cs). If you want to use the library, you can install the [NuGet](https://www.nuget.org/packages/IoTEdgeLogger/) package or develop your own version by forking this repository.

The sample code below demonstrates how to use the **IoTEdgeLogger** library:

```c#
using IoTEdgeLogger;
using Microsoft.Extensions.Logging;

Logger.SetLogLevel("debug");
log = Logger.Factory.CreateLogger<string>();

// Implicit log level methods
log.LogDebug("this is a debug message");
log.LogInformation("this is an info message");
log.LogWarning("this is a warning message");
log.LogError("this is an error message");

// Explicit log level method
log.Log(LogLevel.Information, "another info message");
```



## Create IoT edge deployment

If you want to test these logging modules on your IoT edge device, you can do it by using the [az iot edge deployment create](https://docs.microsoft.com/en-us/cli/azure/ext/azure-iot/iot/edge/deployment?view=azure-cli-latest#ext_azure_iot_az_iot_edge_deployment_create) command. Open a PowerShell console and run the following command:

```powershell
cd IoTEdgeLogger/

az iot edge deployment create `
	-g {resource_group_name} `
	--hub-name {iothub_name} `
	-d {deployment_name} `
	--tc {target_condition} `
	-k EdgeSolution/layered.manifest.json
```



> Note: You need the [Azure IoT CLI Extension](https://github.com/Azure/azure-iot-cli-extension) to run the command above.



After the deployment is successful, you will see two new modules called **csharpsamplelogs** and **pythonsamplelogs** running on your edge device, both logging random messages every 60 seconds.