using System;
using System.Text;
using System.Linq;
using System.Threading.Tasks;
using System.Collections.Generic;
using Newtonsoft.Json;
using Azure.Messaging.EventHubs;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using FunctionApp.Models;
using FunctionApp.MetricsCollector;

namespace FunctionApp
{
    public class CollectMetrics
    {
        private string _hubResourceId = Environment.GetEnvironmentVariable("HubResourceId");
        private bool _compressForUpload = Convert.ToBoolean(Environment.GetEnvironmentVariable("CompressForUpload"));
        private string _metricsEncoding = Environment.GetEnvironmentVariable("MetricsEncoding");
        private int _postSizeInMB = 1;
        private ILogger _logger { get; set; }
        private AzureLogAnalytics _azureLogAnalytics { get; set; }

        public CollectMetrics(AzureLogAnalytics azureLogAnalytics, ILogger<CollectMetrics> logger)
        {
            this._logger = logger;
            this._azureLogAnalytics = azureLogAnalytics;
        }

        [FunctionName("CollectMetrics")]
        public async Task Run(
            [EventHubTrigger("%EventHubName%", Connection = "EventHub", ConsumerGroup = "%EventHubConsumerGroup%")] EventData[] eventHubMessages)
        {
            try
            {
                if (eventHubMessages.Length == 0)
                {
                    this._logger.LogInformation("CollectMetrics method ended because there are no messages");
                    return;
                }

                List<IoTHubMetric> iotHubMetricsList = new List<IoTHubMetric>() { };
                foreach (EventData eventHubMessage in eventHubMessages)
                {
                    // Decompress if encoding is gzip
                    string metricsString = string.Empty;
                    if (string.Equals(_metricsEncoding, "gzip", StringComparison.OrdinalIgnoreCase))
                        metricsString = GZipCompression.Decompress(eventHubMessage.Body.ToArray());
                    else
                        metricsString = Encoding.UTF8.GetString(eventHubMessage.Body.ToArray());

                    // Cast metric events
                    iotHubMetricsList.AddRange(JsonConvert.DeserializeObject<IoTHubMetric[]>(metricsString));
                }

                // Post metrics to Log Analytics
                await PublishToFixedTableAsync(iotHubMetricsList);
                //bool success = await PublishToCustomTableAsync(logAnalytics, iotHubMetrics, log);
            }
            catch (Exception e)
            {
                this._logger.LogError($"CollectMetrics failed with the following exception: {e}");
            }
        }

        // This method is disabled until a way to send data to InsightMetrics
        // table without SSL certificate is found
        /*
        private async Task<bool> PublishToCustomTableAsync(IEnumerable<IoTHubMetric> metrics)
        {
            try
            {
                IEnumerable<UploadMetric> metricsToUpload = metrics.Select(m => new UploadMetric(m));

                bool success = false;
                for (int i = 0; i < Constants.UploadMaxRetries && (!success); i++)
                {
                    // TODO: split up metricList so that no individual post is greater than 1mb
                    success = await this._azureLogAnalytics.PostAsync(JsonConvert.SerializeObject(metricsToUpload), _hubResourceId);
                }

                if (success)
                {
                    this._logger.LogInformation($"Successfully sent {metricsToUpload.Count()} metrics to fixed set table");
                    return true;
                }
                else
                {
                    this._logger.LogError($"Failed to send {metricsToUpload.Count()} metrics to fixed set table after {Constants.UploadMaxRetries} retries");
                    return false;
                }
            }
            catch (Exception e)
            {
                this._logger.LogError($"PublishAsCustomTableAsync failed with the following exception: {e}");
                return false;
            }
        }
        */

        private async Task PublishToFixedTableAsync(IEnumerable<IoTHubMetric> metrics)
        {
            try
            {
                IEnumerable<LaMetric> metricsToUpload = metrics.Select(m => new LaMetric(m, string.Empty));
                List<List<LaMetric>> metricsChunks = this._azureLogAnalytics.CreateContentChunks<LaMetric>(metricsToUpload, this._postSizeInMB * 1024f * 1024f);

                this._logger.LogInformation($"Separated {metricsToUpload.Count()} metrics in {metricsChunks.Count()} chunks of {_postSizeInMB} mb");

                bool success = false;
                for (int i = 0; i < metricsChunks.Count; i++)
                {
                    this._logger.LogInformation($"Submitting chunk {i + 1} out of {metricsChunks.Count} with {metricsChunks[i].Count} metrics");

                    // retry loop
                    LaMetricList metricList = new LaMetricList(metricsChunks[i]);
                    for (int r = 0; r < Constants.UploadMaxRetries && (!success); r++)
                        success = await this._azureLogAnalytics.PostToInsightsMetricsAsync(JsonConvert.SerializeObject(metricList), _hubResourceId, _compressForUpload);
                    
                    if (success)
                        this._logger.LogInformation($"Successfully sent {metricList.DataItems.Count()} metrics to fixed set table");
                    else
                        this._logger.LogError($"Failed to sent {metricList.DataItems.Count()} metrics to fixed set table after {Constants.UploadMaxRetries} retries");
                }
            }
            catch (Exception e)
            {
                this._logger.LogError($"PublishToFixedTableAsync failed with the following exception: {e}");
            }
        }
    }
}