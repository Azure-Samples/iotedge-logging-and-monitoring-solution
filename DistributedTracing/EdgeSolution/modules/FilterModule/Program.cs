namespace FilterModule
{
    using Microsoft.Azure.Devices.Client;
    using Microsoft.Azure.Devices.Client.Transport.Mqtt;
    using Microsoft.Azure.Devices.Shared;
    using Newtonsoft.Json;
    using System;
    using System.Collections.Generic;
    using System.Runtime.Loader;
    using System.Text;
    using System.Threading;
    using System.Threading.Tasks;
    using System.Diagnostics;
    using OpenTelemetry;
    using OpenTelemetry.Trace;
    using OpenTelemetry.Resources;
    using Azure.Monitor.OpenTelemetry.Exporter;
    using Microsoft.Extensions.Configuration;
    using System.IO;
    using Microsoft.Extensions.Logging;
    using Microsoft.Extensions.Logging.ApplicationInsights;
    using Microsoft.ApplicationInsights;
    using Microsoft.ApplicationInsights.Extensibility;
    using Microsoft.ApplicationInsights.DataContracts;


    public class MessageBody
    {
        public Machine machine { get; set; }
        public Ambient ambient { get; set; }
        public string timeCreated { get; set; }
    }

    public class Machine
    {
        public double temperature { get; set; }
        public double pressure { get; set; }
    }

    public class Ambient
    {
        public double temperature { get; set; }
        public int humidity { get; set; }
    }

    public class Program
    {
        private const string healthCheck = "healthcheck";
        private static int counter;
        private static ModuleClient ioTHubModuleClient;
        private static int temperatureThreshold = 25;
        private static ILogger<Program> logger;

        private static readonly ActivitySource FilterModuleActivitySource = new ActivitySource(
        "IoTSample.FilterModule");

        static void Main(string[] args)
        {
            IConfiguration configuration = new ConfigurationBuilder()
                .SetBasePath(Directory.GetCurrentDirectory())
                .AddJsonFile("config/appsettings.json", optional: true)
                .AddEnvironmentVariables()
                .Build();


            /*
            * Configuring ILogger to 
            *   - automatically create a logging scope for the current TraceId and SpanId 
                This feature is available for .Net5 and .Net6 only.
            *   - export logs to console
            *   - export logs to Application Insights. It exports TraceId and SpanId to customDimensions field 
            *     of "traces" (or exceptions) table in App Insights.
            */
            using var loggerFactory = LoggerFactory.Create(builder =>
            {
                builder
                    .AddFilter("Microsoft", LogLevel.Warning)
                    .AddFilter("System", LogLevel.Warning)
                    .AddSimpleConsole(options => options.IncludeScopes = true)
                    .AddApplicationInsights(configuration.GetSection("INSTRUMENTATION_KEY").Value)
                    .Configure(c => c.ActivityTrackingOptions =
                        ActivityTrackingOptions.SpanId
                        | ActivityTrackingOptions.TraceId);
            });

            logger = loggerFactory.CreateLogger<Program>();

            //This switch is neededd to succesfuly export OpenTelemetry data to OTLP 
            AppContext.SetSwitch("System.Net.Http.SocketsHttpHandler.Http2UnencryptedSupport", true);
            
            /*
            * Configuring an OpenTelemetry TraceProvider to export spans (System.Diagnostics.Activity) to 
            * OTLP (to be caught by OpenTelemetry collector) and to Application Insights tables ("Dependencies" and "Requests") 
            * so that "Operation Id == TraceId, Id == SpanId, Parent Id == Parent SpanId"
            */            
            using var tracerProvider = Sdk.CreateTracerProviderBuilder()
                .SetSampler(new AlwaysOnSampler())
                .AddSource("IoTSample.FilterModule")
                .SetResourceBuilder(ResourceBuilder.CreateDefault()
                    .AddTelemetrySdk()
                    .AddService("FilterModule"))
                .AddOtlpExporter(
                    opt =>
                {
                    opt.Endpoint = new Uri(configuration.GetSection("OTLP_ENDPOINT").Value);
                })
                .AddAzureMonitorTraceExporter(o =>
                {
                    o.ConnectionString = configuration.GetSection("AI_CONNECTION_STRING").Value;
                })
                .Build();

            Init().Wait();

            // Wait until the app unloads or is cancelled
            var cts = new CancellationTokenSource();
            AssemblyLoadContext.Default.Unloading += (ctx) => cts.Cancel();
            Console.CancelKeyPress += (sender, cpe) => cts.Cancel();
            WhenCancelled(cts.Token).Wait();
        }

        /// <summary>
        /// Handles cleanup operations when app is cancelled or unloads
        /// </summary>
        public static Task WhenCancelled(CancellationToken cancellationToken)
        {
            var tcs = new TaskCompletionSource<bool>();
            cancellationToken.Register(s => ((TaskCompletionSource<bool>)s).SetResult(true), tcs);
            return tcs.Task;
        }

        /// <summary>
        /// Initializes the ModuleClient and sets up the callback to receive
        /// messages containing temperature information
        /// </summary>
        static async Task Init()
        {
            MqttTransportSettings mqttSetting = new MqttTransportSettings(TransportType.Mqtt_Tcp_Only);
            ITransportSettings[] settings = { mqttSetting };

            // Open a connection to the Edge runtime
            ioTHubModuleClient = await ModuleClient.CreateFromEnvironmentAsync(settings).ConfigureAwait(false);
            await ioTHubModuleClient.OpenAsync().ConfigureAwait(false);
            logger.LogInformation("IoT Hub module client initialized.");

            // Read the TemperatureThreshold value from the module twin's desired properties
            var moduleTwin = await ioTHubModuleClient.GetTwinAsync().ConfigureAwait(false);
            await OnDesiredPropertiesUpdate(moduleTwin.Properties.Desired, ioTHubModuleClient);

            // Attach a callback for updates to the module twin's desired properties.
            await ioTHubModuleClient.SetDesiredPropertyUpdateCallbackAsync(OnDesiredPropertiesUpdate, null).ConfigureAwait(false);

            // Register a callback for messages that are received by the module.
            await ioTHubModuleClient.SetInputMessageHandlerAsync("input1", FilterMessagesAsync, ioTHubModuleClient).ConfigureAwait(false);

            await ioTHubModuleClient.SetMethodHandlerAsync(healthCheck, HealthCheckAsync, ioTHubModuleClient).ConfigureAwait(false);
            logger.LogInformation("Set Healthcheck Method Handler:HealthCheckAsync.");
        }

        static Task OnDesiredPropertiesUpdate(TwinCollection desiredProperties, object userContext)
        {
            const string tempThresholdProperty = "TemperatureThreshold";
            try
            {
                logger.LogInformation("Desired property change:");
                logger.LogInformation(JsonConvert.SerializeObject(desiredProperties));

                if (desiredProperties[tempThresholdProperty] != null)
                    temperatureThreshold = desiredProperties[tempThresholdProperty];

            }
            catch (AggregateException ex)
            {
                foreach (Exception exception in ex.InnerExceptions)
                {
                    logger.LogError(exception, "Error receiving desired property");
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error receiving desired property");
            }

            return Task.CompletedTask;
        }

        public static async Task<MessageResponse> FilterMessagesAsync(Message message, object userContext)
        {
            // Use "traceparent" property of the incoming message to start an OpenTelemery span (Activity) 
            // in the same trace
            using (var activity = FilterModuleActivitySource.StartActivity("FilterTemperature", ActivityKind.Server, message.Properties["traceparent"]))
            {
                try
                {                    
                    ModuleClient moduleClient = (ModuleClient)userContext;

                    var filteredMessage = Filter(message);

                    if (filteredMessage != null)
                    {
                        using (var iot_hub_activity = FilterModuleActivitySource.StartActivity("Upstream", ActivityKind.Client))
                        {
                            // start a new child span and send it in the message "traceparent" property
                            // to be caught by the following components
                            filteredMessage.Properties["traceparent"] = iot_hub_activity.Id;
                            await moduleClient.SendEventAsync("output1", filteredMessage).ConfigureAwait(false);                                                        
                       }
                    }

                    // Indicate that the message treatment is completed.
                    return MessageResponse.Completed;
                }
                catch (AggregateException ex)
                {
                    foreach (Exception exception in ex.InnerExceptions)
                    {
                        logger.LogError(exception, "Error in sample");
                    }

                    // Indicate that the message treatment is not completed.
                    return MessageResponse.Abandoned;
                }
                catch (Exception ex)
                {
                    logger.LogError(ex, "Error in sample");

                    // Indicate that the message treatment is not completed.
                    return MessageResponse.Abandoned;
                }
            }

        }

        public static Message Filter(Message message)
        {
            var activity = Activity.Current;
            var counterValue = Interlocked.Increment(ref counter);
            var messageBytes = message.GetBytes();
            var messageString = Encoding.UTF8.GetString(messageBytes);
            logger.LogInformation("Received message {counterValue}: [{messageString}]", counterValue, messageString);
            activity?.SetTag("MessageString", messageString);

            // Get message body
            var messageBody = JsonConvert.DeserializeObject<MessageBody>(messageString);

            if (messageBody != null)
            {
                activity?.SetTag("MachineTemperature", messageBody.machine.temperature);
                activity?.SetTag("TemperatureThreshhold", temperatureThreshold);

                if (messageBody.machine.temperature > temperatureThreshold)
                {
                    logger.LogInformation("Machine temperature {messageBody.machine.temperature} exceeds threshold {temperatureThreshold}", messageBody.machine.temperature, temperatureThreshold);

                    //Event is same as a log record. It's totally ignored by Azure Monitor exporter,
                    //but is picked up by OTLP exporter, so it can be received by Otel collector and sent to Jaeger, for example.
                    activity?.AddEvent(new ActivityEvent($"Machine temperature {messageBody.machine.temperature} exceeds threshold {temperatureThreshold}"));

                    var filteredMessage = new Message(messageBytes)
                    {
                        ContentType = message.ContentType ?? "application/json",
                        ContentEncoding = message.ContentEncoding ?? "utf-8",
                    };

                    foreach (KeyValuePair<string, string> prop in message.Properties)
                    {
                        filteredMessage.Properties.Add(prop.Key, prop.Value);
                    }

                    filteredMessage.Properties.Add("MessageType", "Alert");
                    logger.LogTrace("Message passed threshold");
                    activity?.AddEvent(new ActivityEvent($"Message passed threshold"));

                    return filteredMessage;
                }
                else
                {
                    logger.LogTrace("Message didn't pass threshold");
                    activity?.AddEvent(new ActivityEvent($"Message didn't pass threshold"));
                }
            }
            else
            {
                logger.LogTrace("Empty message body");
            }



            return null;
        }

        private static async Task<MethodResponse> HealthCheckAsync(MethodRequest methodRequest, object userContext)
        {
            logger.LogInformation("Received method [{methodRequest.Name}]", methodRequest.Name);
            var request = JsonConvert.DeserializeObject<HealthCheckRequestPayload>(methodRequest.DataAsJson);

            var messageBody = Encoding.UTF8.GetBytes($"Device [{Environment.GetEnvironmentVariable("IOTEDGE_DEVICEID")}], Module [FilterModule] Running");

            var healthCheckMessage = new Message(messageBody);
            healthCheckMessage.Properties.Add("MessageType", healthCheck);
            if (!string.IsNullOrEmpty(request.CorrelationId))
                healthCheckMessage.Properties.Add("correlationId", request.CorrelationId);

            await ioTHubModuleClient.SendEventAsync(healthCheck, healthCheckMessage).ConfigureAwait(false);
            logger.LogInformation("Sent method response via event [{healthCheck}]", healthCheck);

            var responseMsg = JsonConvert.SerializeObject(new HealthCheckResponsePayload() { ModuleResponse = string.IsNullOrEmpty(request.CorrelationId) ? "" : $"Invoked with correlationId:{request.CorrelationId}" });
            return new MethodResponse(Encoding.UTF8.GetBytes(responseMsg), 200);
        }
    }

    class HealthCheckRequestPayload
    {
        public string CorrelationId { get; set; }
        public string Text { get; set; }
    }

    class HealthCheckResponsePayload
    {
        public string ModuleResponse { get; set; } = null;
    }

}