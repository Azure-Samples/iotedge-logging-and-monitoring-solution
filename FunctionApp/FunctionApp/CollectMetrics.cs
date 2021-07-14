using System;
using System.Text;
using System.Linq;
using System.Threading.Tasks;
using System.Collections.Generic;
using Newtonsoft.Json;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.EventHubs;
using Microsoft.Extensions.Logging;
using FunctionApp.Models;
using FunctionApp.MetricsCollector;

namespace FunctionApp
{
    public class CollectMetrics
    {
        private string _hubResourceId = Environment.GetEnvironmentVariable("HubResourceId");
        private string _containerName = Environment.GetEnvironmentVariable("ContainerName");
        private string _workspaceId = Environment.GetEnvironmentVariable("WorkspaceId");
        private string _workspaceKey = Environment.GetEnvironmentVariable("WorkspaceKey");
        private string _workspaceDomain = Environment.GetEnvironmentVariable("WorkspaceDomain");
        private string _workspaceApiVersion = Environment.GetEnvironmentVariable("WorkspaceApiVersion");
        private bool _compressForUpload = Convert.ToBoolean(Environment.GetEnvironmentVariable("CompressForUpload"));
        private string _metricsEncoding = Environment.GetEnvironmentVariable("MetricsEncoding");
        private AzureLogAnalytics _azureLogAnalytics { get; set; }

        public CollectMetrics(AzureLogAnalytics azureLogAnalytics)
        {
            this._azureLogAnalytics = azureLogAnalytics;
        }

        [FunctionName("CollectMetrics")]
        public async Task Run(
            [EventHubTrigger("%EventHubName%", Connection = "EventHubConnectionString", ConsumerGroup = "%EventHubConsumerGroup%")] EventData eventHubMessages,
            ILogger log)
        {
            try
            {
                log.LogInformation("CollectMetrics function started.");

                if (eventHubMessages.Body.Count == 0)
                {
                    log.LogInformation("CollectMetrics method ended because event body is empty");
                    return;
                }

                // Decompress if encoding is gzip
                string metricsString = string.Empty;
                if (string.Equals(_metricsEncoding, "gzip", StringComparison.OrdinalIgnoreCase))
                    metricsString = GZipCompression.Decompress(eventHubMessages.Body.ToArray());
                else
                    metricsString = Encoding.UTF8.GetString(eventHubMessages.Body);

                // Cast metric events
                IoTHubMetric[] iotHubMetrics = JsonConvert.DeserializeObject<IoTHubMetric[]>(metricsString);

                // Post metrics to Log Analytics
                bool success = await PublishToFixedTableAsync(this._azureLogAnalytics, iotHubMetrics, log);
                //bool success = await PublishToCustomTableAsync(logAnalytics, iotHubMetrics, log);
            }
            catch (Exception e)
            {
                log.LogError($"CollectMetrics failed with the following exception: {e}");
            }
        }

        private async Task<bool> PublishToCustomTableAsync(AzureLogAnalytics azureLogAnalytics, IoTHubMetric[] metrics, ILogger log)
        {
            try
            {
                IEnumerable<UploadMetric> metricsToUpload = metrics.Select(m => new UploadMetric(m));

                bool success = false;
                for (int i = 0; i < Constants.UploadMaxRetries && (!success); i++)
                {
                    // TODO: split up metricList so that no individual post is greater than 1mb
                    success = await azureLogAnalytics.PostAsync(JsonConvert.SerializeObject(metricsToUpload), _hubResourceId);
                }

                if (success)
                {
                    log.LogInformation($"Successfully sent {metricsToUpload.Count()} metrics to fixed set table");
                    return true;
                }
                else
                {
                    log.LogError($"Failed to send {metricsToUpload.Count()} metrics to fixed set table after {Constants.UploadMaxRetries} retries");
                    return false;
                }
            }
            catch (Exception e)
            {
                log.LogError($"PublishAsCustomTableAsync failed with the following exception: {e}");
                return false;
            }
        }

        private async Task<bool> PublishToFixedTableAsync(AzureLogAnalytics azureLogAnalytics, IoTHubMetric[] metrics, ILogger log)
        {
            try
            {
                IEnumerable<LaMetric> metricsToUpload = metrics.Select(m => new LaMetric(m, string.Empty));
                LaMetricList metricList = new LaMetricList(metricsToUpload);

                bool success = false;
                for (int i = 0; i < Constants.UploadMaxRetries && (!success); i++)
                {
                    // TODO: split up metricList so that no individual post is greater than 1mb
                    success = await azureLogAnalytics.PostToInsightsMetricsAsync(JsonConvert.SerializeObject(metricList), _hubResourceId, _compressForUpload);
                }

                if (success)
                {
                    log.LogInformation($"Successfully sent {metricsToUpload.Count()} metrics to fixed set table");
                    return true;
                }
                else
                {
                    log.LogError($"Failed to send {metricsToUpload.Count()} metrics to fixed set table after {Constants.UploadMaxRetries} retries");
                    return false;
                }
            }
            catch (Exception e)
            {
                log.LogError($"PublishToFixedTableAsync failed with the following exception: {e}");
                return false;
            }
        }
    }
}