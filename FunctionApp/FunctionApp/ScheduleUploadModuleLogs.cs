using System;
using System.Net.Http;
using System.Threading.Tasks;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;

namespace FunctionApp
{
    public class ScheduleUploadModuleLogs
    {
        private readonly string _hostKey = Environment.GetEnvironmentVariable("HostKey");
        private readonly string _hostUrl = Environment.GetEnvironmentVariable("HostUrl");
        private readonly string _invokeModuleLogUploadFunction = Environment.GetEnvironmentVariable("HttpTriggerFunction");
        private HttpClient _httpClient;

        public ScheduleUploadModuleLogs(HttpClient httpClient)
        {
            this._httpClient = httpClient;
        }

        [FunctionName("ScheduleUploadModuleLogs")]
        public async Task Run([TimerTrigger("0 */15 * * * *")] TimerInfo myTimer, ILogger log)
        {
            try
            {
                log.LogInformation($"ScheduleUploadModuleLogs function executed at: {DateTime.Now}");

                string url = $"{this._hostUrl}/api/{this._invokeModuleLogUploadFunction}?code={this._hostKey}";
                log.LogInformation($"Calling endpoint {url} to invoke module logs upload method");
                var response = await this._httpClient.PostAsJsonAsync<object>(url, new { });

                if (response.StatusCode == System.Net.HttpStatusCode.OK)
                {
                    log.LogInformation($"HTTP request completed successfully");
                }
                else
                {
                    string responseMessage = await response.Content.ReadAsStringAsync();
                    log.LogError($"HTTP request failed with status code {response.StatusCode}. Message {responseMessage}");
                }
            }
            catch (Exception e)
            {
                log.LogError($"ScheduleUploadModuleLogs failed with the following exception: {e}");
            }
        }
    }
}
