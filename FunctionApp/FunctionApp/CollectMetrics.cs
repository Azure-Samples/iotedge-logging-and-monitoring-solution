using System;
using System.Linq;
using System.Threading.Tasks;
using System.Collections.Generic;
using Newtonsoft.Json;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using FunctionApp.Models;
using FunctionApp.MetricsCollector;

namespace FunctionApp
{
    public static class CollectMetrics
    {
        private static string _hubResourceId = Environment.GetEnvironmentVariable("HubResourceId");
        private static string _containerName = Environment.GetEnvironmentVariable("ContainerName");
        private static string _workspaceId = Environment.GetEnvironmentVariable("WorkspaceId");
        private static string _workspaceKey = Environment.GetEnvironmentVariable("WorkspaceKey");
        private static string _workspaceApiVersion = Environment.GetEnvironmentVariable("WorkspaceApiVersion");
        private static bool _compressForUpload = Convert.ToBoolean(Environment.GetEnvironmentVariable("CompressForUpload"));

        [FunctionName("CollectMetrics")]
        public static async Task Run(
            [EventHubTrigger("%EventHubName%", Connection = "EventHubConnectionString", ConsumerGroup = "%EventHubConsumerGroup%")] string eventHubMessages,
            ILogger log)
        {
            try
            {
                log.LogInformation("CollectMetrics function started.");

                IoTHubMetric[] iotHubMetrics = JsonConvert.DeserializeObject<IoTHubMetric[]>(eventHubMessages);
                IEnumerable<LaMetric> metricsToUpload = iotHubMetrics.Select(m => new LaMetric(m, string.Empty));
                LaMetricList metricList = new LaMetricList(metricsToUpload);

                // initialize log analytics class
                AzureLogAnalytics logAnalytics = new AzureLogAnalytics(
                    workspaceId: _workspaceId,
                    workspaceKey: _workspaceKey,
                    logger: log,
                    apiVersion: _workspaceApiVersion);

                bool success = false;
                for (int i = 0; i < Constants.UploadMaxRetries && (!success); i++)
                {
                    // TODO: split up metricList so that no individual post is greater than 1mb
                    success = await logAnalytics.PostToInsightsMetricsAsync(JsonConvert.SerializeObject(metricList), _hubResourceId, _compressForUpload);
                }

                if (success)
                    log.LogInformation($"Successfully sent {metricList.DataItems.Count()} metrics to fixed set table");
                else
                    log.LogError($"Failed to send {metricList.DataItems.Count()} metrics to fixed set table after {Constants.UploadMaxRetries} retries");
            }
            catch (Exception e)
            {
                log.LogError($"CollectMetrics failed with the following exception: {e}");
            }
        }
    }
}