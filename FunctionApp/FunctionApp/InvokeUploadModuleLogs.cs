using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Azure.Storage.Blobs;
using Microsoft.Azure.Devices;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using FunctionApp.Models;
using Azure.Identity;
using Azure.Core;

namespace FunctionApp
{
    public static class InvokeUploadModuleLogs
    {
        private static string _iotDeviceQuery = Environment.GetEnvironmentVariable("DeviceQuery");
        private static string _logsIdRegex = Environment.GetEnvironmentVariable("LogsIdRegex");
        private static string _logsSince = Environment.GetEnvironmentVariable("LogsSince");
        private static string _logsRegex = Environment.GetEnvironmentVariable("LogsRegex");
        private static string _logsLogLevel = Environment.GetEnvironmentVariable("LogsLogLevel");
        private static string _logsTail = Environment.GetEnvironmentVariable("LogsTail");
        private static string _logsEncoding = Environment.GetEnvironmentVariable("LogsEncoding");
        private static string _logsContentType = Environment.GetEnvironmentVariable("LogsContentType");
        private static string _connectionString = Environment.GetEnvironmentVariable("StorageConnectionString");
        private static string _containerName = Environment.GetEnvironmentVariable("ContainerName");
        private static string _iotHubAddress = Environment.GetEnvironmentVariable("HubHostName");        

        [FunctionName("InvokeUploadModuleLogs")]
        public static async Task<IActionResult> Run(
            [HttpTrigger(AuthorizationLevel.Function, "post", Route = null)] HttpRequest req,
            ILogger log)
        {
            try
            {
                log.LogInformation("InvokeUploadModuleLogs function started.");

                /// It is important to set as null the values that won't be used
                /// so the serialization done later in this code ignores them
                #region cast and fix payload property types
                int? logLevel = null;
                if (!string.IsNullOrEmpty(_logsLogLevel))
                    logLevel = Convert.ToInt32(_logsLogLevel);

                int? logsTail = null;
                if (!string.IsNullOrEmpty(_logsTail))
                    logsTail = Convert.ToInt32(_logsTail);

                if (string.IsNullOrEmpty(_logsRegex))
                    _logsRegex = null;

                if (string.IsNullOrEmpty(_logsEncoding))
                    _logsEncoding = "gzip";

                if (string.IsNullOrEmpty(_logsContentType))
                    _logsContentType = "json";
                #endregion

                TokenCredential tokenCredential = new DefaultAzureCredential();

                // Check payload to see if a specific resource is requested
                string[] deviceIds = null;

                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                dynamic dynamicData = JsonConvert.DeserializeObject(requestBody);
                string windowSize = dynamicData?.windowSize;
                if (!string.IsNullOrEmpty(windowSize))
                {
                    AlertSummary alertSummary = JsonConvert.DeserializeObject<AlertSummary>(requestBody);

                    // create devices list with the device that triggered the alert
                    deviceIds = alertSummary.Dimensions.Select(x => x.Device.DeviceId).ToArray();

                    // verify if window size was provided in the alert
                    if (!string.IsNullOrEmpty(alertSummary.WindowSize))
                        _logsSince = $"{System.Xml.XmlConvert.ToTimeSpan(alertSummary.WindowSize).Minutes}m";
                    else
                        _logsSince = "1h";

                    // overwrite direct method parameters to retrieve the most information possible
                    _logsIdRegex = ".*";
                    _logsRegex = ".*";
                    logLevel = null;
                    logsTail = null;
                }
                else
                {
                    // query IoT edge devices                    
                    using  (var registryManager = RegistryManager.Create(_iotHubAddress, tokenCredential))
                    {
                        var query = registryManager.CreateQuery(_iotDeviceQuery);
                        var devices = (await query.GetNextAsJsonAsync()).ToArray();
                        deviceIds = devices.Select(x => JsonConvert.DeserializeObject<JObject>(x).GetValue("deviceId").ToString()).ToArray();
                    }
                }

                // get container SAS token URL
                BlobContainerClient container = new BlobContainerClient(_connectionString, _containerName);
                Azure.Storage.Sas.BlobContainerSasPermissions permissions = Azure.Storage.Sas.BlobContainerSasPermissions.All;
                DateTimeOffset expiresOn = new DateTimeOffset(DateTime.UtcNow.AddHours(12));
                Uri sasUri = container.GenerateSasUri(permissions, expiresOn);

                // invoke direct method on every device
                string moduleId = "$edgeAgent";
                string methodName = "UploadModuleLogs";

                using ServiceClient _serviceClient = ServiceClient.Create(_iotHubAddress, tokenCredential);

                foreach (string deviceId in deviceIds)
                {
                    //JObject deviceJson = JsonConvert.DeserializeObject<JObject>(device);
                    //string deviceId = deviceJson.GetValue("deviceId").ToString();

                    var data = new UploadModuleLogs()
                    {
                        SchemaVersion = "1.0",
                        SasUrl = sasUri.AbsoluteUri,
                        Encoding = _logsEncoding,
                        ContentType = _logsContentType,
                        Items = new List<UploadModuleLogs.Item>()
                            {
                                new UploadModuleLogs.Item()
                                {
                                    Id = _logsIdRegex,
                                    Filter = new UploadModuleLogs.Filter()
                                    {
                                        Since = _logsSince,
                                        Regex = _logsRegex,
                                        LogLevel = logLevel,
                                        Tail = logsTail,
                                    }
                                }
                            }
                    };

                    string serializedData = JsonConvert.SerializeObject(
                        data,
                        Formatting.None,
                        new JsonSerializerSettings
                        {
                            NullValueHandling = NullValueHandling.Ignore,
                        });

                    var deviceMethod = new CloudToDeviceMethod(methodName);
                    deviceMethod.SetPayloadJson(serializedData);

                    try
                    {
                        var result = await _serviceClient.InvokeDeviceMethodAsync(deviceId, moduleId, deviceMethod);
                        log.LogInformation($"InvokeUploadModuleLogs: Method '{methodName}' on module '{moduleId}' on device '{deviceId}': Status code: {result.Status}. Response: {result.GetPayloadAsJson()}");
                    }
                    catch (Exception e)
                    {
                        log.LogInformation($"InvokeUploadModuleLogs: Method '{methodName}' on module '{moduleId}' on device '{deviceId}' failed with exception: {e.Message}");
                    }
                }

                return new OkResult();
            }
            catch (Exception e)
            {
                log.LogError($"InvokeUploadModuleLogs failed with the following exception: {e}");
                return new BadRequestObjectResult(e.ToString());
            }
        }
    }
}