using System;
using System.IO;
using System.Linq;
using Newtonsoft.Json;
using FunctionApp.Models;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json.Linq;
using System.Text.RegularExpressions;
using Azure.Storage.Blobs;
using System.Threading.Tasks;
using System.Collections.Generic;
using Azure.Identity;
using Azure.Core;

namespace FunctionApp
{
    public class ProcessModuleLogs
    {
        private string _hubResourceId = Environment.GetEnvironmentVariable("HubResourceId");
        private string _storageAccountName = Environment.GetEnvironmentVariable("StorageAccountName");
        private string _containerName = Environment.GetEnvironmentVariable("ContainerName");
        private string _logsEncoding = Environment.GetEnvironmentVariable("LogsEncoding");
        private string _logType = Environment.GetEnvironmentVariable("LogType");
        private int _logMaxSizeMB = Convert.ToInt32(Environment.GetEnvironmentVariable("LogsMaxSizeMB"));
        private bool _compressForUpload = Convert.ToBoolean(Environment.GetEnvironmentVariable("CompressForUpload"));
        private ILogger _logger { get; set; }
        private AzureLogAnalytics _azureLogAnalytics { get; set; }
        
        public ProcessModuleLogs(AzureLogAnalytics azureLogAnalytics, ILogger<ProcessModuleLogs> logger)
        {
            this._logger = logger;
            this._azureLogAnalytics = azureLogAnalytics;
        }

        [FunctionName("ProcessModuleLogs")]
        public async Task Run(
            [QueueTrigger("%QueueName%", Connection = "StorageName")] string queueItem)
        {
            try
            {
                #region Queue trigger
                JObject storageEvent = JsonConvert.DeserializeObject<JObject>(queueItem);
                var match = Regex.Match(storageEvent["subject"].ToString(), "/blobServices/default/containers/(.*)/blobs/(.*)", RegexOptions.IgnoreCase);
                if (!match.Success)
                {
                    this._logger.LogWarning($"Unable to parse blob Url from {storageEvent["subject"]}");
                    return;
                }

                if (!string.Equals(match.Groups[1].Value, _containerName))
                {
                    this._logger.LogDebug($"Ignoring queue item because it is related to container '{match.Groups[1].Value}'");
                    return;
                }

                string blobName = match.Groups[2].Value;
                #endregion

                this._logger.LogInformation($"ProcessModuleLogs function received a new queue message from blob {blobName}");

                TokenCredential tokenCredential = new DefaultAzureCredential();

                // Create a BlobServiceClient object which will be used to create a container client
                BlobServiceClient blobServiceClient = new BlobServiceClient( new Uri($"https://{_storageAccountName}.blob.core.windows.net"), tokenCredential);

                // Create container client object
                BlobContainerClient containerClient = blobServiceClient.GetBlobContainerClient(_containerName);

                // Get blob client object
                BlobClient blobClient = containerClient.GetBlobClient(blobName);

                // Read the blob's contents
                Stream blobStream = await blobClient.OpenReadAsync();

                // Decompress if encoding is gzip
                string logsString = string.Empty;
                if (string.Equals(_logsEncoding, "gzip", StringComparison.OrdinalIgnoreCase))
                    logsString = GZipCompression.Decompress(blobStream);
                else
                {
                    StreamReader reader = new StreamReader(blobStream);
                    logsString = reader.ReadToEnd();
                }

                IoTEdgeLog[] iotEdgeLogs = JsonConvert.DeserializeObject<IoTEdgeLog[]>(logsString);

                // Convert to logs their final log analytics format
                LogAnalyticsLog[] logAnalyticsLogs = iotEdgeLogs.Select(x => new LogAnalyticsLog(x)).ToArray();

                if (logAnalyticsLogs.Length == 0)
                    return;

                // because log analytics supports messages up to 30MB,
                // we have to break logs in chunks to fit in on each request
                List<List<LogAnalyticsLog>> logsChunks = this._azureLogAnalytics.CreateContentChunks<LogAnalyticsLog>(logAnalyticsLogs, _logMaxSizeMB * 1024f * 1024f);

                this._logger.LogInformation($"Separated {logAnalyticsLogs.Length} logs in {logsChunks.Count} chunks of {_logMaxSizeMB} mb");

                for (int i = 0; i < logsChunks.Count; i++)
                {
                    this._logger.LogInformation($"Submitting chunk {i + 1} out of {logsChunks.Count} with {logsChunks[i].Count} logs");

                    bool success = this._azureLogAnalytics.PostToCustomTable(JsonConvert.SerializeObject(logsChunks[i]), _logType, _hubResourceId);
                    if (success)
                        this._logger.LogInformation("ProcessModuleLogs request to log analytics completed successfully");
                    else
                        this._logger.LogError("ProcessModuleLogs request to log analytics failed");
                }

                // Delete blob after being processed
                await blobClient.DeleteIfExistsAsync(Azure.Storage.Blobs.Models.DeleteSnapshotsOption.IncludeSnapshots);
            }
            catch (Exception e)
            {
                this._logger.LogError($"ProcessModuleLogs failed with the following exception: {e}");
            }
        }
    }
}