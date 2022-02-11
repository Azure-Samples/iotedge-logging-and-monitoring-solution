// Copyright (c) Microsoft. All rights reserved.
namespace SimulatedTemperatureSensor
{
    using System;
    using System.IO;
    using System.Net;
    using System.Text;
    using System.Threading;
    using System.Threading.Tasks;
    using Microsoft.Azure.Devices.Client;
    using Microsoft.Azure.Devices.Client.Transport.Mqtt;
    using Microsoft.Azure.Devices.Edge.Util;
    using Microsoft.Azure.Devices.Edge.Util.Concurrency;
    using Microsoft.Azure.Devices.Edge.Util.TransientFaultHandling;
    using Microsoft.Azure.Devices.Shared;
    using Microsoft.Extensions.Configuration;
    using Newtonsoft.Json;
    using ExponentialBackoff = Microsoft.Azure.Devices.Edge.Util.TransientFaultHandling.ExponentialBackoff;
    using System.Diagnostics;
    using OpenTelemetry;
    using OpenTelemetry.Trace;
    using OpenTelemetry.Resources;
    using OpenTelemetry.Logs;
    using Microsoft.Extensions.Logging;
    using Microsoft.ApplicationInsights;
    using Microsoft.ApplicationInsights.Extensibility;
    using Microsoft.ApplicationInsights.DataContracts;
    using System.Collections.Generic;

    class Program
    {
        const string MessageCountConfigKey = "MessageCount";
        const string SendDataConfigKey = "SendData";
        const string SendIntervalConfigKey = "SendInterval";

        private static ILogger<Program> logger;

        static readonly ITransientErrorDetectionStrategy DefaultTimeoutErrorDetectionStrategy =
            new DelegateErrorDetectionStrategy(ex => ex.HasTimeoutException());

        static readonly RetryStrategy DefaultTransientRetryStrategy =
            new ExponentialBackoff(
                5,
                TimeSpan.FromSeconds(2),
                TimeSpan.FromSeconds(60),
                TimeSpan.FromSeconds(4));

        static readonly Guid BatchId = Guid.NewGuid();
        static readonly AtomicBoolean Reset = new AtomicBoolean(false);
        static readonly Random Rnd = new Random();
        static TimeSpan messageDelay;
        static bool sendData = true;

        static string deviceId;

        public enum ControlCommandEnum
        {
            Reset = 0,
            NoOperation = 1
        }

        public static int Main() => MainAsync().Result;

        private static readonly ActivitySource SimulatedTemperatureSensorActivitySource = new ActivitySource("IoTSample.SimulatedTemperatureSensor");


        static async Task<int> MainAsync()
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
            *   - export logs to OTLP
            */
            using var loggerFactory = LoggerFactory.Create(builder =>
            {
                builder
                    .SetMinimumLevel(
                        (LogLevel)Enum.Parse(typeof(LogLevel),
                                                 configuration.GetSection("LOGGING_LEVEL").Value,
                                                 true))
                    .AddOpenTelemetry(options =>
                    {
                        options.IncludeFormattedMessage = true;
                        options.IncludeScopes = true;
                        options.ParseStateValues = true;
                        options.AddConsoleExporter();
                        options.AddOtlpExporter(
                             opt =>
                                 {
                                     opt.Endpoint = new Uri(configuration.GetSection("OTLP_ENDPOINT").Value);
                                 });
                    }
                                );
            });

            logger = loggerFactory.CreateLogger<Program>();

            logger.LogInformation("SimulatedTemperatureSensor Main() started");

            //This switch is neededd to succesfuly export OpenTelemetry data to OTLP 
            AppContext.SetSwitch("System.Net.Http.SocketsHttpHandler.Http2UnencryptedSupport", true);

            /*
            * Configuring an OpenTelemetry TraceProvider to export spans (System.Diagnostics.Activity) to 
            * OTLP (to be caught by OpenTelemetry collector)
            */
            using var tracerProvider = Sdk.CreateTracerProviderBuilder()
                .SetSampler(new TraceIdRatioBasedSampler(Convert.ToDouble(configuration.GetSection("TRACE_SAMPLE_RAIO").Value)))
                .AddSource("IoTSample.SimulatedTemperatureSensor")
                .SetResourceBuilder(ResourceBuilder.CreateDefault()
                    .AddTelemetrySdk()
                    .AddService("TemperatureSensor"))
                .AddOtlpExporter(
                    opt =>
                {
                    opt.Endpoint = new Uri(configuration.GetSection("OTLP_ENDPOINT").Value);
                })
                .Build();


            messageDelay = configuration.GetValue("MessageDelay", TimeSpan.FromSeconds(5));
            int messageCount = configuration.GetValue(MessageCountConfigKey, 10000);
            var simulatorParameters = new SimulatorParameters
            {
                MachineTempMin = configuration.GetValue<double>("machineTempMin", 0),
                MachineTempMax = configuration.GetValue<double>("machineTempMax", 100),
                MachinePressureMin = configuration.GetValue<double>("machinePressureMin", 1),
                MachinePressureMax = configuration.GetValue<double>("machinePressureMax", 10),
                AmbientTemp = configuration.GetValue<double>("ambientTemp", 21),
                HumidityPercent = configuration.GetValue("ambientHumidity", 25)
            };

            logger.LogInformation(
                $"Initializing simulated temperature sensor to send {(SendUnlimitedMessages(messageCount) ? "unlimited" : messageCount.ToString())} "
                + $"messages, at an interval of {messageDelay.TotalSeconds} seconds.\n"
                + $"To change this, set the environment variable {MessageCountConfigKey} to the number of messages that should be sent (set it to -1 to send unlimited messages).");

            TransportType transportType = configuration.GetValue("ClientTransportType", TransportType.Amqp_Tcp_Only);

            ModuleClient moduleClient = await CreateModuleClientAsync(
                transportType,
                DefaultTimeoutErrorDetectionStrategy,
                DefaultTransientRetryStrategy);
            await moduleClient.OpenAsync();
            await moduleClient.SetMethodHandlerAsync("reset", ResetMethod, null);

            (CancellationTokenSource cts, ManualResetEventSlim completed, Option<object> handler) = ShutdownHandler.Init(TimeSpan.FromSeconds(5), null);

            Twin currentTwinProperties = await moduleClient.GetTwinAsync();
            if (currentTwinProperties.Properties.Desired.Contains(SendIntervalConfigKey))
            {
                messageDelay = TimeSpan.FromSeconds((int)currentTwinProperties.Properties.Desired[SendIntervalConfigKey]);
            }

            if (currentTwinProperties.Properties.Desired.Contains(SendDataConfigKey))
            {
                sendData = (bool)currentTwinProperties.Properties.Desired[SendDataConfigKey];
                if (!sendData)
                {
                    logger.LogInformation("Sending data disabled. Change twin configuration to start sending again.");
                }
            }
            
            deviceId = configuration.GetSection("IOTEDGE_DEVICEID").Value;
            
            

            ModuleClient userContext = moduleClient;
            await moduleClient.SetDesiredPropertyUpdateCallbackAsync(OnDesiredPropertiesUpdated, userContext);
            await moduleClient.SetInputMessageHandlerAsync("control", ControlMessageHandle, userContext);
            await SendEvents(moduleClient, messageCount, simulatorParameters, cts);
            await cts.Token.WhenCanceled();

            completed.Set();
            handler.ForEach(h => GC.KeepAlive(h));
            logger.LogInformation("SimulatedTemperatureSensor Main() finished.");
            return 0;
        }

        static bool SendUnlimitedMessages(int maximumNumberOfMessages) => maximumNumberOfMessages < 0;

        // Control Message expected to be:
        // {
        //     "command" : "reset"
        // }
        static Task<MessageResponse> ControlMessageHandle(Message message, object userContext)
        {
            byte[] messageBytes = message.GetBytes();
            string messageString = Encoding.UTF8.GetString(messageBytes);

            logger.LogInformation("Received message Body: [{messageString}]", messageString);

            try
            {
                var messages = JsonConvert.DeserializeObject<ControlCommand[]>(messageString);

                foreach (ControlCommand messageBody in messages)
                {
                    if (messageBody.Command == ControlCommandEnum.Reset)
                    {
                        logger.LogInformation("Resetting temperature sensor..");
                        Reset.Set(true);
                    }
                }
            }
            catch (JsonSerializationException)
            {
                var messageBody = JsonConvert.DeserializeObject<ControlCommand>(messageString);

                if (messageBody.Command == ControlCommandEnum.Reset)
                {
                    logger.LogInformation("Resetting temperature sensor..");
                    Reset.Set(true);
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error: Failed to deserialize control command with exception.");
            }

            return Task.FromResult(MessageResponse.Completed);
        }

        static Task<MethodResponse> ResetMethod(MethodRequest methodRequest, object userContext)
        {
            logger.LogInformation("Received direct method call to reset temperature sensor...");
            Reset.Set(true);
            var response = new MethodResponse((int)HttpStatusCode.OK);
            return Task.FromResult(response);
        }

        /// <summary>
        /// Module behavior:
        ///        Sends data periodically (with default frequency of 5 seconds).
        ///        Data trend:
        ///         - Machine Temperature regularly rises from 21C to 100C in regularly with jitter
        ///         - Machine Pressure correlates with Temperature 1 to 10psi
        ///         - Ambient temperature stable around 21C
        ///         - Humidity is stable with tiny jitter around 25%
        ///                Method for resetting the data stream.
        /// </summary>
        static async Task SendEvents(
            ModuleClient moduleClient,
            int messageCount,
            SimulatorParameters sim,
            CancellationTokenSource cts)
        {
            int count = 1;
            double currentTemp = sim.MachineTempMin;
            double normal = (sim.MachinePressureMax - sim.MachinePressureMin) / (sim.MachineTempMax - sim.MachineTempMin);

            while (!cts.Token.IsCancellationRequested && (SendUnlimitedMessages(messageCount) || messageCount >= count))
            {
                if (Reset)
                {
                    currentTemp = sim.MachineTempMin;
                    Reset.Set(false);
                }

                // if (currentTemp > sim.MachineTempMax)
                // {
                //     currentTemp += Rnd.NextDouble() - 0.5; // add value between [-0.5..0.5]
                // }
                // else
                // {
                //     currentTemp += -0.25 + (Rnd.NextDouble() * 1.5); // add value between [-0.25..1.25] - average +0.5
                // }

                currentTemp = Rnd.NextDouble()*(sim.MachineTempMax - sim.MachineTempMin) + sim.MachineTempMin;

                if (sendData)
                {
                    //Start a new OpenTelemetry tracing span (Activity)                   
                    using (var activity = SimulatedTemperatureSensorActivitySource.StartActivity("SendTemerature", ActivityKind.Client))
                    {
                        var tempData = new MessageBody
                        {
                            Machine = new Machine
                            {
                                Temperature = currentTemp,
                                Pressure = sim.MachinePressureMin + ((currentTemp - sim.MachineTempMin) * normal),
                            },
                            Ambient = new Ambient
                            {
                                Temperature = sim.AmbientTemp + Rnd.NextDouble() - 0.5,
                                Humidity = Rnd.Next(24, 27)
                            },
                            TimeCreated = DateTime.UtcNow
                        };

                        var dataBuffer = JsonConvert.SerializeObject(tempData);
                        var encodedMessage = Encoding.UTF8.GetBytes(dataBuffer);
                        var eventMessage = new Message(encodedMessage);

                        //Add custom tags to the span (Activity) 
                        activity?.SetTag("MessageString", Encoding.UTF8.GetString(encodedMessage));
                        activity?.SetTag("MachineTemperature", currentTemp);
                        activity?.SetTag("DeviceId", deviceId);

                        eventMessage.ContentEncoding = "utf-8";
                        eventMessage.ContentType = "application/json";
                        eventMessage.Properties.Add("sequenceNumber", count.ToString());
                        eventMessage.Properties.Add("batchId", BatchId.ToString());



                        if (activity != null)
                        {
                            // To support W3C convention
                            // See https://www.w3.org/TR/trace-context/#trace-context-http-headers-format
                            // This message property will be exracted by the following components (modules and backends) to 
                            // continiue the trace
                            eventMessage.Properties.Add("traceparent", activity.Id);

                            //To support EvenHub + App Insights integration
                            //See https://medium.com/swlh/correlated-logs-deep-dive-for-eventhub-triggered-azure-function-in-app-insights-ac69c7c70285
                            //
                            //This is broken for at least .Net Azure Functions due to https://github.com/Azure/azure-functions-eventhubs-extension/issues/55
                            //eventMessage.Properties.Add("Diagnostic-Id", activity.Id);                                                        
                        }

                        logger.LogInformation($"\t{DateTime.Now.ToLocalTime()}> Sending message: {count}, Body: [{dataBuffer}]");

                        //Event is same as a log record. It's totally ignored by Azure Monitor exporter,
                        //but is picked up by OTLP exporter, so it can be received by Otel collector and sent to Jaeger, for example.
                        activity?.AddEvent(new ActivityEvent($"\t{DateTime.Now.ToLocalTime()}> Sending message: {count}, Body: [{dataBuffer}]"));


                        try
                        {
                            await moduleClient.SendEventAsync("temperatureOutput", eventMessage);
                            //throw new InvalidOperationException("This is a test exception");
                        }
                        catch (Exception ex)
                        {
                            //An exception is exported to Application Insighs "exceptions" table.
                            //It also contains TraceId and SpanId in customDimenssions field 
                            logger.LogError(ex, "That's bad");
                        }

                        logger.LogDebug($"\t{DateTime.Now.ToLocalTime()}> Sent message: {count}, Body: [{dataBuffer}]");
                        count++;
                    }

                }

                await Task.Delay(messageDelay, cts.Token);
            }

            if (messageCount < count)
            {
                logger.LogInformation("Done sending {messageCount} messages", messageCount);
            }
        }

        static async Task OnDesiredPropertiesUpdated(TwinCollection desiredPropertiesPatch, object userContext)
        {
            // At this point just update the configure configuration.
            if (desiredPropertiesPatch.Contains(SendIntervalConfigKey))
            {
                messageDelay = TimeSpan.FromSeconds((int)desiredPropertiesPatch[SendIntervalConfigKey]);
            }

            if (desiredPropertiesPatch.Contains(SendDataConfigKey))
            {
                bool desiredSendDataValue = (bool)desiredPropertiesPatch[SendDataConfigKey];
                if (desiredSendDataValue != sendData && !desiredSendDataValue)
                {
                    logger.LogInformation("Sending data disabled. Change twin configuration to start sending again.");
                }

                sendData = desiredSendDataValue;
            }

            var moduleClient = (ModuleClient)userContext;
            var patch = new TwinCollection($"{{ \"SendData\":{sendData.ToString().ToLower()}, \"SendInterval\": {messageDelay.TotalSeconds}}}");
            await moduleClient.UpdateReportedPropertiesAsync(patch); // Just report back last desired property.
        }

        static async Task<ModuleClient> CreateModuleClientAsync(
            TransportType transportType,
            ITransientErrorDetectionStrategy transientErrorDetectionStrategy = null,
            RetryStrategy retryStrategy = null)
        {
            var retryPolicy = new RetryPolicy(transientErrorDetectionStrategy, retryStrategy);
            retryPolicy.Retrying += (_, args) => { logger.LogInformation($"[Error] Retry {args.CurrentRetryCount} times to create module client and failed with exception:{Environment.NewLine}{args.LastException}"); };

            ModuleClient client = await retryPolicy.ExecuteAsync(
                async () =>
                {
                    ITransportSettings[] GetTransportSettings()
                    {
                        switch (transportType)
                        {
                            case TransportType.Mqtt:
                            case TransportType.Mqtt_Tcp_Only:
                                return new ITransportSettings[] { new MqttTransportSettings(TransportType.Mqtt_Tcp_Only) };
                            case TransportType.Mqtt_WebSocket_Only:
                                return new ITransportSettings[] { new MqttTransportSettings(TransportType.Mqtt_WebSocket_Only) };
                            case TransportType.Amqp_WebSocket_Only:
                                return new ITransportSettings[] { new AmqpTransportSettings(TransportType.Amqp_WebSocket_Only) };
                            default:
                                return new ITransportSettings[] { new AmqpTransportSettings(TransportType.Amqp_Tcp_Only) };
                        }
                    }

                    ITransportSettings[] settings = GetTransportSettings();
                    logger.LogInformation("[Information]: Trying to initialize module client using transport type [{transportType}].", transportType);
                    ModuleClient moduleClient = await ModuleClient.CreateFromEnvironmentAsync(settings);
                    await moduleClient.OpenAsync();

                    logger.LogInformation("[Information]: Successfully initialized module client of transport type [{transportType}].", transportType);
                    return moduleClient;
                });

            return client;
        }

        class ControlCommand
        {
            [JsonProperty("command")]
            public ControlCommandEnum Command { get; set; }
        }

        class SimulatorParameters
        {
            public double MachineTempMin { get; set; }

            public double MachineTempMax { get; set; }

            public double MachinePressureMin { get; set; }

            public double MachinePressureMax { get; set; }

            public double AmbientTemp { get; set; }

            public int HumidityPercent { get; set; }
        }
    }
}
