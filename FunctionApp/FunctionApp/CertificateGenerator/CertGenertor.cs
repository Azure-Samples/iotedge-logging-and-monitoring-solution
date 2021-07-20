namespace FunctionApp.CertificateGenerator
{
    using System;
    using System.IO;
    using System.Net;
    using System.Text;
    using System.Net.Http;
    using System.Net.Http.Headers;
    using System.Threading.Tasks;
    using System.Security.Cryptography;
    using System.Security.Cryptography.X509Certificates;
    using Org.BouncyCastle.Crypto;
    using Org.BouncyCastle.Crypto.Generators;
    using Org.BouncyCastle.Crypto.Operators;
    using Org.BouncyCastle.Math;
    using Org.BouncyCastle.Pkcs;
    using Org.BouncyCastle.X509;
    using Org.BouncyCastle.OpenSsl;
    using Org.BouncyCastle.Security;
    using Org.BouncyCastle.Utilities;
    using Org.BouncyCastle.Asn1.X509;
    using Microsoft.Extensions.Logging;
    using Microsoft.Extensions.Configuration;

    public class CertGenerator
    {
        private string _workspaceId { get; set; }
        private string _workspaceKey { get; set; }
        private string _workspaceDomainSuffix { get; set; }
        private string _apiVersion { get; set; }
        private ILogger _logger { get; set; }

        public CertGenerator(IConfiguration configuration, ILogger<CertGenerator> logger)
        {
            this._workspaceId = configuration["WorkspaceId"];
            this._workspaceKey = configuration["WorkspaceKey"];
            this._workspaceDomainSuffix = configuration["WorkspaceDomainSuffix"];
            this._apiVersion = configuration["WorkspaceApiVersion"];
            this._logger = logger;
        }

        internal class Constants
        {
            /// <summary>
            /// constants related to masking the secrets in container environment variable
            /// </summary>
            public const string DEFAULT_LOG_ANALYTICS_WORKSPACE_DOMAIN = "opinsights.azure.com";

            public const string DEFAULT_SIGNATURE_ALOGIRTHM = "SHA256WithRSA";
        }

        private (X509Certificate2, (string, byte[]), string) CreateSelfSignedCertificate(string agentGuid)
        {
            var random = new SecureRandom();

            var certificateGenerator = new X509V3CertificateGenerator();

            var serialNumber = BigIntegers.CreateRandomInRange(BigInteger.One, BigInteger.ValueOf(Int64.MaxValue), random);

            certificateGenerator.SetSerialNumber(serialNumber);

            var dirName = string.Format("CN={0}, CN={1}, OU=Microsoft Monitoring Agent, O=Microsoft", this._workspaceId, agentGuid);

            X509Name certName = new X509Name(dirName);

            certificateGenerator.SetIssuerDN(certName);

            certificateGenerator.SetSubjectDN(certName);

            certificateGenerator.SetNotBefore(DateTime.UtcNow.Date);

            certificateGenerator.SetNotAfter(DateTime.UtcNow.Date.AddYears(1));

            const int strength = 2048;

            var keyGenerationParameters = new KeyGenerationParameters(random, strength);

            var keyPairGenerator = new RsaKeyPairGenerator();

            keyPairGenerator.Init(keyGenerationParameters);

            var subjectKeyPair = keyPairGenerator.GenerateKeyPair();

            certificateGenerator.SetPublicKey(subjectKeyPair.Public);

            // Get Private key for the Certificate
            TextWriter textWriter = new StringWriter();
            PemWriter pemWriter = new PemWriter(textWriter);
            pemWriter.WriteObject(subjectKeyPair.Private);
            pemWriter.Writer.Flush();

            string privateKeyString = textWriter.ToString();

            var issuerKeyPair = subjectKeyPair;
            var signatureFactory = new Asn1SignatureFactory(Constants.DEFAULT_SIGNATURE_ALOGIRTHM, issuerKeyPair.Private);
            var bouncyCert = certificateGenerator.Generate(signatureFactory);

            // Lets convert it to X509Certificate2
            X509Certificate2 certificate;

            Pkcs12Store store = new Pkcs12StoreBuilder().Build();

            store.SetKeyEntry($"{agentGuid}_key", new AsymmetricKeyEntry(subjectKeyPair.Private), new[] { new X509CertificateEntry(bouncyCert) });

            string exportpw = Guid.NewGuid().ToString("x");

            using (var ms = new MemoryStream())
            {
                store.Save(ms, exportpw.ToCharArray(), random);
                certificate = new X509Certificate2(ms.ToArray(), exportpw, X509KeyStorageFlags.Exportable);
            }

            // // Get the value.
            // string resultsTrue = certificate.ToString(true);

            //Get Certificate in PEM format
            StringBuilder builder = new StringBuilder();
            builder.AppendLine("-----BEGIN CERTIFICATE-----");
            builder.AppendLine(
                Convert.ToBase64String(certificate.RawData, Base64FormattingOptions.InsertLineBreaks));
            builder.AppendLine("-----END CERTIFICATE-----");
            string certString = builder.ToString();

            return (certificate, (certString, certificate.RawData), privateKeyString);
        }

        // Delete the certificate and key files
        private void DeleteCertificateAndKeyFile()
        {
            File.Delete(Environment.GetEnvironmentVariable("CI_CERT_LOCATION"));
            File.Delete(Environment.GetEnvironmentVariable("CI_KEY_LOCATION"));
        }

        private string Sign(string requestdate, string contenthash, string key)
        {
            var signatureBuilder = new StringBuilder();
            signatureBuilder.Append(requestdate);
            signatureBuilder.Append("\n");
            signatureBuilder.Append(contenthash);
            signatureBuilder.Append("\n");
            string rawsignature = signatureBuilder.ToString();

            //string rawsignature = contenthash;

            HMACSHA256 hKey = new HMACSHA256(Convert.FromBase64String(key));
            return Convert.ToBase64String(hKey.ComputeHash(Encoding.UTF8.GetBytes(rawsignature)));
        }

        public void RegisterWithOms(X509Certificate2 cert, string AgentGuid, string logAnalyticsWorkspaceDomainPrefixOms)
        {

            string rawCert = Convert.ToBase64String(cert.GetRawCertData()); //base64 binary
            string hostName = Dns.GetHostName();

            string date = DateTime.Now.ToString("O");

            string xmlContent = "<?xml version=\"1.0\"?>" +
                "<AgentTopologyRequest xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" xmlns=\"http://schemas.microsoft.com/WorkloadMonitoring/HealthServiceProtocol/2014/09/\">" +
                "<FullyQualfiedDomainName>"
                 + hostName
                + "</FullyQualfiedDomainName>" +
                "<EntityTypeId>"
                    + AgentGuid
                + "</EntityTypeId>" +
                "<AuthenticationCertificate>"
                  + rawCert
                + "</AuthenticationCertificate>" +
                "</AgentTopologyRequest>";

            SHA256 sha256 = SHA256.Create();

            string contentHash = Convert.ToBase64String(sha256.ComputeHash(Encoding.ASCII.GetBytes(xmlContent)));

            string authKey = string.Format("{0}; {1}", this._workspaceId, Sign(date, contentHash, this._workspaceKey));


            HttpClientHandler clientHandler = new HttpClientHandler();

            clientHandler.ClientCertificates.Add(cert);

            var client = new HttpClient(clientHandler);

            string url = "https://" + this._workspaceId + logAnalyticsWorkspaceDomainPrefixOms + this._workspaceDomainSuffix + "/AgentService.svc/AgentTopologyRequest";

            this._logger.LogInformation("OMS endpoint Url : {0}", url);

            client.DefaultRequestHeaders.Add("x-ms-Date", date);
            client.DefaultRequestHeaders.Add("x-ms-version", "August, 2014");
            client.DefaultRequestHeaders.Add("x-ms-SHA256_Content", contentHash);
            client.DefaultRequestHeaders.TryAddWithoutValidation("Authorization", authKey);
            client.DefaultRequestHeaders.Add("user-agent", "MonitoringAgent/OneAgent");
            client.DefaultRequestHeaders.Add("Accept-Language", "en-US");

            HttpContent httpContent = new StringContent(xmlContent, Encoding.UTF8);
            httpContent.Headers.ContentType = new MediaTypeHeaderValue("application/xml");

            this._logger.LogDebug("sent registration request");
            Task<HttpResponseMessage> response = client.PostAsync(new Uri(url), httpContent);
            this._logger.LogInformation("waiting response for registration request : {0}", response.Result.StatusCode);
            response.Wait();
            this._logger.LogDebug("registration request processed");
            this._logger.LogInformation("Response result status code : {0}", response.Result.StatusCode);
            HttpContent responseContent = response.Result.Content;
            string result = responseContent.ReadAsStringAsync().Result;
            this._logger.LogDebug("Return Result: " + result);
            this._logger.LogDebug(response.Result.ToString());
            if (response.Result.StatusCode != HttpStatusCode.OK)
            {
                DeleteCertificateAndKeyFile();
            }
        }

        public void RegisterWithOmsWithBasicRetryAsync(X509Certificate2 cert, string AgentGuid, string logAnalyticsWorkspaceDomainPrefixOms)
        {
            int currentRetry = 0;

            for (; ; )
            {
                try
                {
                    RegisterWithOms(cert, AgentGuid, logAnalyticsWorkspaceDomainPrefixOms);

                    // Return or break.
                    break;
                }
                catch (Exception ex)
                {
                    currentRetry++;

                    // Check if the exception thrown was a transient exception
                    // based on the logic in the error detection strategy.
                    // Determine whether to retry the operation, as well as how
                    // long to wait, based on the retry strategy.
                    if (currentRetry > 3)
                    {
                        // If this isn't a transient error or we shouldn't retry,
                        // rethrow the exception.
                        this._logger.LogError($"exception occurred : {ex}");
                        throw;
                    }
                }

                // Wait to retry the operation.
                // Consider calculating an exponential delay here and
                // using a strategy best suited for the operation and fault.
                Task.Delay(1000);
            }
        }

        public (X509Certificate2 tempCert, (string, byte[]), string) RegisterAgentWithOMS(string logAnalyticsWorkspaceDomainPrefixOms)
        {
            X509Certificate2 agentCert = null;
            string certString;
            byte[] certBuf;
            string keyString;

            var agentGuid = Guid.NewGuid().ToString("B");

            try
            {
                Environment.SetEnvironmentVariable("CI_AGENT_GUID", agentGuid);
            }
            catch (Exception ex)
            {
                this._logger.LogError("Failed to set env variable (CI_AGENT_GUID)" + ex.Message);
            }

            try
            {
                (agentCert, (certString, certBuf), keyString) = CreateSelfSignedCertificate(agentGuid);

                if (agentCert == null)
                {
                    throw new Exception($"creating self-signed certificate failed for agentGuid : {agentGuid} and workspace: {this._workspaceId}");
                }

                this._logger.LogInformation($"Successfully created self-signed certificate  for agentGuid : {agentGuid} and workspace: {this._workspaceId}");

                RegisterWithOmsWithBasicRetryAsync(agentCert, agentGuid, logAnalyticsWorkspaceDomainPrefixOms);
            }
            catch (Exception ex)
            {
                this._logger.LogError("Registering agent with OMS failed (are the Log Analytics Workspace ID and Key correct?) : {0}", ex.Message);

                //Log.LogCritical(ex.ToString());
                Environment.Exit(1);

                // to make the code analyzer happy
                throw new Exception();
            }

            return (agentCert, (certString, certBuf), keyString);
        }
    }
}
