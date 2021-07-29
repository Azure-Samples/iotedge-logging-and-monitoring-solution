using System;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using FunctionApp.Models;

namespace FunctionApp
{
    public class MonitorAlerts
    {
        private readonly string _hostKey = Environment.GetEnvironmentVariable("HostKey");
        private readonly string _hostUrl = Environment.GetEnvironmentVariable("HostUrl");
        private readonly string _invokeModuleLogUploadFunction = Environment.GetEnvironmentVariable("HttpTriggerFunction");
        public HttpClient _httpClient;

        public MonitorAlerts(HttpClient httpClient)
        {
            this._httpClient = httpClient;
        }

        [FunctionName("MonitorAlerts")]
        public async Task<IActionResult> Run(
            [HttpTrigger(AuthorizationLevel.Function, "post", Route = null)] HttpRequest req,
            ILogger log)
        {
            try
            {
                log.LogInformation("MonitorAlerts function processed a request.");

                // Parse request body to read alert payload
                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                JObject alert = JsonConvert.DeserializeObject<JObject>(requestBody);
                JToken alertCondition = alert.SelectToken("data.alertContext.condition");
                JToken windowSize = alertCondition.SelectToken("windowSize");
                JArray allOfAlertConditions = (JArray)alertCondition.SelectToken("allOf");

                // Create object to send to direct method function
                AlertSummary alertSummary = new AlertSummary()
                {
                    WindowSize = windowSize.Value<string>(),
                    Dimensions = new AlertSummary.AlertDimension[allOfAlertConditions.Count()],
                };
                
                for (int i = 0; i < allOfAlertConditions.Count(); i++)
                {
                    JArray allOfAlertDimensions = (JArray)allOfAlertConditions[i].SelectToken("dimensions");
                    JToken device = allOfAlertDimensions.Where(x => x.Value<string>("name") == "device").FirstOrDefault();
                    JToken resourceId = allOfAlertDimensions.Where(x => x.Value<string>("name") == "_ResourceId").FirstOrDefault();

                    alertSummary.Dimensions[i] = new AlertSummary.AlertDimension()
                    {
                        Device = new AlertSummary.Device()
                        {
                            DeviceId = device.Value<string>("value"),
                        },
                        ResourceId = resourceId.Value<string>("value"),
                    };
                }

                // Make POST request
                string url = $"{this._hostUrl}/api/{this._invokeModuleLogUploadFunction}?code={this._hostKey}";
                log.LogInformation($"Calling endpoint {url} to invoke module logs upload method");
                var response = await this._httpClient.PostAsJsonAsync<AlertSummary>(url, alertSummary);

                if (response.StatusCode == System.Net.HttpStatusCode.OK)
                {
                    log.LogInformation($"HTTP request completed successfully");

                    return new OkResult();
                }
                else
                {
                    string responseMessage = await response.Content.ReadAsStringAsync();
                    log.LogError($"HTTP request failed with status code {response.StatusCode}. Message {responseMessage}");

                    return new BadRequestObjectResult(responseMessage);
                }

                ////Create a unique name for the container
                //string blobGuid = Guid.NewGuid().ToString();

                //// Write full alert
                //using (MemoryStream ms = new MemoryStream())
                //{
                //    var sw = new StreamWriter(ms, System.Text.Encoding.UTF8);
                //    try
                //    {
                //        sw.Write(requestBody);
                //        sw.Flush();  //otherwise you are risking empty stream
                //        ms.Seek(0, SeekOrigin.Begin);

                //        // Create a BlobServiceClient object which will be used to create a container client
                //        BlobServiceClient blobServiceClient = new BlobServiceClient(connectionString);
                //        BlobContainerClient containerClient = blobServiceClient.GetBlobContainerClient(containerName); // Open the file and upload its data
                //        BlobClient blobClient = containerClient.GetBlobClient($"{blobGuid}.json");

                //        // Create the container and return a container client object
                //        await blobClient.UploadAsync(ms, true);
                //    }
                //    finally
                //    {
                //        sw.Dispose();
                //    }
                //}

                //// Write just dimensions
                //using (MemoryStream ms = new MemoryStream())
                //{
                //    var sw = new StreamWriter(ms, System.Text.Encoding.UTF8);
                //    try
                //    {
                //        sw.Write(JsonConvert.SerializeObject(alertDimensions));
                //        sw.Flush();  //otherwise you are risking empty stream
                //        ms.Seek(0, SeekOrigin.Begin);

                //        // Create a BlobServiceClient object which will be used to create a container client
                //        BlobServiceClient blobServiceClient = new BlobServiceClient(connectionString);
                //        BlobContainerClient containerClient = blobServiceClient.GetBlobContainerClient(containerName); // Open the file and upload its data
                //        BlobClient blobClient = containerClient.GetBlobClient($"{blobGuid}-dimensions.json");

                //        // Create the container and return a container client object
                //        await blobClient.UploadAsync(ms, true);
                //    }
                //    finally
                //    {
                //        sw.Dispose();
                //    }
                //}
            }
            catch (Exception e)
            {
                log.LogError($"MonitorAlerts failed with exception {e.ToString()}");
                return new BadRequestObjectResult(e);
            }
        }
    }
}
