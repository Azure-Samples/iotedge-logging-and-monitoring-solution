using System;
using System.Threading.Tasks;
using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Azure.Storage.Blobs;
using Microsoft.Azure.Devices;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using FunctionApp.Models;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace FunctionApp
{
    public static class InvokeUploadModuleLogs
    {
        private static ServiceClient _serviceClient;
        private static string _iotHubConnectionString = Environment.GetEnvironmentVariable("HubConnectionString");
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

        [FunctionName("InvokeUploadModuleLogs")]
        public static async Task<IActionResult> Run(
            [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req,
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
                    _logsEncoding = "none";

                if (string.IsNullOrEmpty(_logsContentType))
                    _logsContentType = "json";
                #endregion

                // get container SAS token URL
                BlobContainerClient container = new BlobContainerClient(_connectionString, _containerName);
                Azure.Storage.Sas.BlobContainerSasPermissions permissions = Azure.Storage.Sas.BlobContainerSasPermissions.All;
                DateTimeOffset expiresOn = new DateTimeOffset(DateTime.UtcNow.AddHours(12));
                Uri sasUri = container.GenerateSasUri(permissions, expiresOn);

                // query IoT devices
                var registryManager = RegistryManager.CreateFromConnectionString(_iotHubConnectionString);
                var query = registryManager.CreateQuery(_iotDeviceQuery);
                var devices = await query.GetNextAsJsonAsync();
                _serviceClient = ServiceClient.CreateFromConnectionString(_iotHubConnectionString);

                // invoke direct method on every device
                string moduleId = "$edgeAgent";
                string methodName = "UploadModuleLogs";

                foreach (var device in devices)
                {
                    JObject deviceJson = JsonConvert.DeserializeObject<JObject>(device);
                    string deviceId = deviceJson.GetValue("deviceId").ToString();

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

                    var result = await _serviceClient.InvokeDeviceMethodAsync(deviceId, moduleId, deviceMethod);
                    log.LogInformation($"InvokeUploadModuleLogs: Method '{methodName}' on module '{moduleId}' on device '{deviceId}': Status code: {result.Status}. Response: {result.GetPayloadAsJson()}");
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