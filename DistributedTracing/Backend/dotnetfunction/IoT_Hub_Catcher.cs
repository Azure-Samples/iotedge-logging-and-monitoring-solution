using System;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Collections.Generic;
using OpenTelemetry;
using OpenTelemetry.Trace;
using OpenTelemetry.Resources;
using Azure.Monitor.OpenTelemetry.Exporter;
using System.Diagnostics;
using System.Net.Http;
using System.Threading.Tasks;

namespace IoTSample
{

    public class IoTHubCatcher
    {
        private static readonly ActivitySource IoTHubCatcherSource = new ActivitySource("IoTSample.IoTHubCatcher");

        /*
        * Configuring ILogger to 
        *   - automatically create a logging scope for the current TraceId and SpanId 
        *     (the default Functions logger (e.g. context.GetLogger or dependency injected) can't do that)
        *     This feature is available for .Net5 and .Net6 only.
        *   - export logs to console
        *   - export logs to Application Insights. It exports TraceId and SpanId to customDimensions field 
        *     of "traces" (or exceptions) table in App Insights.
        */
        private ILogger GetLogger()
        {
            using var loggerFactory = LoggerFactory.Create(builder =>
            {
                builder
                    .AddFilter("Microsoft", LogLevel.Warning)
                    .AddFilter("System", LogLevel.Warning)
                    .AddSimpleConsole(options => options.IncludeScopes = true)
                    .AddApplicationInsights(GetEnvironmentVariable("INSTRUMENTATION_KEY"))
                    .Configure(c => c.ActivityTrackingOptions =
                        ActivityTrackingOptions.SpanId
                        | ActivityTrackingOptions.TraceId);
            });

            return loggerFactory.CreateLogger<IoTHubCatcher>();
        }

        /*
        * Configuring an OpenTelemetry TraceProvider to export spans (System.Diagnostics.Activity) to 
        * Application Insights tables ("Dependencies" and "Requests") 
        *  so that "Operation Id == TraceId, Id == SpanId, Parent Id == Parent SpanId"
        */
        private TracerProvider GetTracerProvider()
        {
            return Sdk.CreateTracerProviderBuilder()
                .SetSampler(new AlwaysOnSampler())
                .AddSource("IoTSample.IoTHubCatcher")
                .SetResourceBuilder(ResourceBuilder.CreateDefault()
                    .AddTelemetrySdk()
                    .AddService("iot-dotnet-backend"))
                .AddAzureMonitorTraceExporter(o =>
                {
                    o.ConnectionString = this.GetEnvironmentVariable("AI_CONNECTION_STRING");
                })
                .Build();

        }
        private string GetEnvironmentVariable(string name)
        {
            return System.Environment.GetEnvironmentVariable(name, EnvironmentVariableTarget.Process);
        }

        private void Init() {
            // By default .Net5/6 embeds into outgoing http calls a "buggy" traceparent header.
            // We don't want it as we want to provide correct traceparent header instead. 
            // See https://github.com/dotnet/aspnetcore/issues/27846
            // https://github.com/dotnet/runtime/issues/35337#issuecomment-864293752                    
            AppContext.SetSwitch("System.Net.Http.EnableActivityPropagation", false);
        }

        /*
        * The backend C# function is invoked when a new IoT meessage arrives from a device to Event Hub.
        * The function uses the message "traceparent" property to start a new OpenTelemetry span (Activity) in the same trace. 
        * It invokes via http call the next backend function (Java function) in the chain passing the new span as a traceparent 
        * in the header.   
        */
        [Function("IoTHubCatcher")]
        public async Task RunAsync([EventHubTrigger("messages/events", Connection = "IoTHubConnection", IsBatched = false)] string iotMessage,
             FunctionContext context,
             DateTime[] enqueuedTimeUtcArray,
             long[] sequenceNumberArray,
             string[] offsetArray,
             Dictionary<string, JsonElement> properties)
        {
            Init();            

            using (GetTracerProvider())
            using (var activity = IoTHubCatcherSource.StartActivity("ProcessedInFunction", ActivityKind.Server, properties["traceparent"].GetString()))
            {
                
                activity.SetTag("MessageString", iotMessage);

                var logger = this.GetLogger();
                logger.LogInformation("C# backend function has received the message: {iotMessage}", iotMessage);

                using (var java_activity = IoTHubCatcherSource.StartActivity("Invoke Java", ActivityKind.Client))
                using (var client = new HttpClient())
                {                    
                    var json = iotMessage;
                    using (var stringContent = new StringContent(json, System.Text.Encoding.UTF8, "application/json"))
                    {
                        string traceparent = java_activity.Id;
                        stringContent.Headers.Add("traceparent", traceparent);
                        HttpResponseMessage response = await client.PostAsync(GetEnvironmentVariable("JAVA_FUNCTION_URI"), stringContent);
                        response.EnsureSuccessStatusCode();
                    }
                }
            }



        }
    }
}
    

