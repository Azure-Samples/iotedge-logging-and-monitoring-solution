using System;
using System.IO;
using System.Text;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading.Tasks;
using System.Security.Cryptography;
using FunctionApp.MetricsCollector;
using FunctionApp.CertificateGenerator;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using ICSharpCode.SharpZipLib.Zip.Compression;
using ICSharpCode.SharpZipLib.Zip.Compression.Streams;
using System.Security.Cryptography.X509Certificates;

namespace FunctionApp
{
    public class AzureLogAnalytics
    {
        private HttpClient _client { get; set; }
        private string _workspaceId { get; set; }
        private string _workspaceKey { get; set; }
        private string _workspaceDomainSuffix { get; set; }
        private string _apiVersion { get; set; }
        private CertGenerator _certGenerator { get; set; }
        private ILogger _logger { get; set; }
        private X509Certificate2 cert;
        private int failurecount = 0;
        private DateTime lastFailureReportedTime = DateTime.UnixEpoch;

        public AzureLogAnalytics(IConfiguration configuration, HttpClient client, CertGenerator certGenerator, ILogger<AzureLogAnalytics> logger)
        {
            this._client = client;
            this._workspaceId = configuration["WorkspaceId"];
            this._workspaceKey = configuration["WorkspaceKey"];
            this._workspaceDomainSuffix = configuration["WorkspaceDomainSuffix"];
            this._apiVersion = configuration["WorkspaceApiVersion"];
            this._certGenerator = certGenerator;
            this._logger = logger;
        }

        /// <summary>
        /// Sends data to a custom logs table in Log Analytics
        /// <param name="content"> HTTP request content string </param>
        /// <param name="logType"> Custom log table name </param>
        /// <param name="armResourceId"> Azure ARM resource ID </param>
        /// <returns>
        /// True on success, false on failure.
        /// </returns>
        /// </summary>
        public bool PostToCustomTable(string content, string logType, string armResourceid)
        {
            try
            {
                string requestUriString = $"https://{this._workspaceId}.{Constants.DefaultLogAnalyticsWorkspaceDomainPrefixOds}.{this._workspaceDomainSuffix}/api/logs?api-version={this._apiVersion}";
                string dateString = DateTime.UtcNow.ToString("r");
                string signature = GetSignature("POST", content.Length, "application/json", dateString, "/api/logs");
                
                HttpWebRequest request = (HttpWebRequest)WebRequest.Create(requestUriString);
                
                request.ContentType = "application/json";
                request.Method = "POST";
                request.Headers["x-ms-date"] = dateString;
                request.Headers["x-ms-AzureResourceId"] = armResourceid;
                request.Headers["Authorization"] = signature;
                request.Headers["Log-Type"] = logType;

                byte[] contentBytes = Encoding.UTF8.GetBytes(content);
                using (Stream requestStreamAsync = request.GetRequestStream())
                {
                    requestStreamAsync.Write(contentBytes, 0, contentBytes.Length);
                }
                using (HttpWebResponse responseAsync = (HttpWebResponse)request.GetResponse())
                {
                    if (responseAsync.StatusCode != HttpStatusCode.OK && responseAsync.StatusCode != HttpStatusCode.Accepted)
                    {
                        Stream responseStream = responseAsync.GetResponseStream();
                        if (responseStream != null)
                        {
                            using (StreamReader streamReader = new StreamReader(responseStream))
                            {
                                throw new Exception(streamReader.ReadToEnd());
                            }
                        }
                    }
                }

                return true;
            }
            catch (Exception e)
            {
                this._logger.LogError(e.Message);
                if (e.InnerException != null)
                {
                    this._logger.LogError("InnerException - " + e.InnerException.Message);
                }
            }

            return false;
        }

        /// <summary>
        /// Sends data to the InsightsMetrics table in Log Analytics
        /// <returns>
        /// True on success, false on failure.
        /// </returns>
        /// </summary>
        public async Task<bool> PostToInsightsMetricsAsync(string content, string armResourceId, bool compressForUpload)
        {
            try
            {
                // Lazily generate and register certificate.
                if (cert == null)
                {
                    (X509Certificate2 tempCert, (string certString, byte[] certBuf), string keyString) = this._certGenerator.RegisterAgentWithOMS(Constants.DefaultLogAnalyticsWorkspaceDomainPrefixOms);
                    cert = tempCert;
                }
                using (var handler = new HttpClientHandler())
                {
                    handler.ClientCertificates.Add(cert);
                    handler.SslProtocols = System.Security.Authentication.SslProtocols.Tls12;
                    handler.PreAuthenticate = true;
                    handler.ClientCertificateOptions = ClientCertificateOption.Manual;

                    Uri requestUri = new Uri("https://" + this._workspaceId + Constants.DefaultLogAnalyticsWorkspaceDomainPrefixOds + this._workspaceDomainSuffix + "/OperationalData.svc/PostJsonDataItems");

                    using (HttpClient client = new HttpClient(handler))
                    {
                        client.DefaultRequestHeaders.Add("x-ms-date", DateTime.Now.ToString("YYYY-MM-DD'T'HH:mm:ssZ"));  // should be RFC3339 format;
                        client.DefaultRequestHeaders.Add("X-Request-ID", Guid.NewGuid().ToString("B"));  // This is host byte order instead of network byte order, but it doesn't mater here
                        client.DefaultRequestHeaders.Add("User-Agent", "IotEdgeContainerAgent/" + Constants.VersionNumber);
                        client.DefaultRequestHeaders.Add("x-ms-AzureResourceId", armResourceId);

                        // TODO: replace with actual version number
                        client.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("IotEdgeContainerAgent", Constants.VersionNumber));

                        // optionally compress content before sending
                        int contentLength;
                        HttpContent contentMsg;
                        if (compressForUpload)
                        {
                            byte[] withHeader = ZlibDeflate(Encoding.UTF8.GetBytes(content));
                            contentLength = withHeader.Length;

                            contentMsg = new ByteArrayContent(withHeader);
                            contentMsg.Headers.Add("Content-Encoding", "deflate");
                        }
                        else
                        {
                            contentMsg = new StringContent(content, Encoding.UTF8);
                            contentLength = ASCIIEncoding.Unicode.GetByteCount(content);
                        }

                        if (contentLength > 1024 * 1024)
                        {
                            this._logger.LogDebug(
                                "HTTP post content greater than 1mb" + " " +
                                "Length - " + contentLength.ToString());
                        }

                        contentMsg.Headers.ContentType = new MediaTypeHeaderValue("application/json");

                        var response = await client.PostAsync(requestUri, contentMsg).ConfigureAwait(false);
                        var responseMsg = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                        this._logger.LogDebug(
                            ((int)response.StatusCode).ToString() + " " +
                            response.ReasonPhrase + " " +
                            responseMsg);

                        if ((int)response.StatusCode != 200)
                        {
                            failurecount += 1;

                            if (DateTime.Now - lastFailureReportedTime > TimeSpan.FromMinutes(1))
                            {
                                this._logger.LogError(
                                    "abnormal HTTP response code - " +
                                    "responsecode: " + ((int)response.StatusCode).ToString() + " " +
                                    "reasonphrase: " + response.ReasonPhrase + " " +
                                    "responsemsg: " + responseMsg + " " +
                                    "count: " + failurecount);
                                failurecount = 0;
                                lastFailureReportedTime = DateTime.Now;
                            }

                            // It's possible that the generated certificate is bad, maybe the module has been running for a over a month? (in which case a topology request would be needed to refresh the cert).
                            // Regen the cert on next run just to be safe.
                            cert = null;
                        }
                        return ((int)response.StatusCode) == 200;
                    }
                }
            }
            catch (Exception e)
            {
                this._logger.LogError(e.Message);
                if (e.InnerException != null)
                {
                    this._logger.LogError("InnerException - " + e.InnerException.Message);
                }
            }

            return false;
        }

        public async Task<bool> PostAsync(string content, string armResourceId)
        {
            try
            {
                string dateString = DateTime.UtcNow.ToString("r");
                Uri requestUri = new Uri($"https://{this._workspaceId}.{Constants.DefaultLogAnalyticsWorkspaceDomainPrefixOds}.{this._workspaceDomainSuffix}/api/logs?api-version={this._apiVersion}");
                string signature = this.GetSignature("POST", content.Length, "application/json", dateString, "/api/logs");

                this._client.DefaultRequestHeaders.Add("Authorization", signature);
                this._client.DefaultRequestHeaders.Add("Accept", "application/json");
                this._client.DefaultRequestHeaders.Add("Log-Type", Constants.LogAnalyticsLogType);
                this._client.DefaultRequestHeaders.Add("x-ms-date", dateString);
                this._client.DefaultRequestHeaders.Add("x-ms-AzureResourceId", armResourceId);

                var contentMsg = new StringContent(content, Encoding.UTF8);
                contentMsg.Headers.ContentType = new MediaTypeHeaderValue("application/json");
                this._logger.LogDebug(
                    this._client.DefaultRequestHeaders.ToString() +
                    contentMsg.Headers +
                    contentMsg.ReadAsStringAsync().Result);

                var response = await this._client.PostAsync(requestUri, contentMsg).ConfigureAwait(false);
                var responseMsg = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                this._logger.LogDebug(
                    ((int)response.StatusCode).ToString() + " " +
                    response.ReasonPhrase + " " +
                    responseMsg);

                return true;
            }
            catch (Exception e)
            {
                this._logger.LogError(e.Message);
                return false;
            }
        }

        /// <summary>
        /// Returns authorization HMAC-SHA256 signature.
        /// More info at https://docs.microsoft.com/en-us/azure/azure-monitor/logs/data-collector-api
        /// <param name="method"> HTTP request method </param>
        /// <param name="contentLength"> Content string length </param>
        /// <param name="contentType"> HTTP request content type </param>
        /// <param name="date"> Date string </param>
        /// <param name="resource"> HTP request path </param>
        /// </summary>
        private string GetSignature(string method, int contentLength, string contentType, string date, string resource)
        {
            string message = $"{method}\n{contentLength}\n{contentType}\nx-ms-date:{date}\n{resource}";
            byte[] bytes = Encoding.UTF8.GetBytes(message);
            using (HMACSHA256 encryptor = new HMACSHA256(Convert.FromBase64String(_workspaceKey)))
            {
                return $"SharedKey {this._workspaceId}:{Convert.ToBase64String(encryptor.ComputeHash(bytes))}";
            }
        }

        /// <summary>
        /// Compresses a byte array using the Zlib format
        /// <param name="input"> Byte array to compress </param>
        /// </summary>
        private static byte[] ZlibDeflate(byte[] input)
        {
            // "Deflate" compression often instead refers to a Zlib format which requies a 2 byte header and checksum (RFC 1950). 
            // The C# built in deflate stream doesn't support this, so use an external library.
            // Hopefully a built-in Zlib stream will be included in .net 5 (https://github.com/dotnet/runtime/issues/2236)
            var deflater = new Deflater(5, false);
            using (var memoryStream = new MemoryStream())
            using (DeflaterOutputStream outStream = new DeflaterOutputStream(memoryStream, deflater))
            {
                outStream.IsStreamOwner = false;
                outStream.Write(input, 0, input.Length);
                outStream.Flush();
                outStream.Finish();
                return memoryStream.ToArray();
            }
        }
    }
}
