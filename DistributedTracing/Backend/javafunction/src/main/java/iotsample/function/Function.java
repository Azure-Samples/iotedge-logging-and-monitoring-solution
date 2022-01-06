package iotsample.function;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

import com.microsoft.azure.functions.ExecutionContext;
import com.microsoft.azure.functions.HttpMethod;
import com.microsoft.azure.functions.HttpRequestMessage;
import com.microsoft.azure.functions.HttpResponseMessage;
import com.microsoft.azure.functions.HttpStatus;
import com.microsoft.azure.functions.annotation.AuthorizationLevel;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.HttpTrigger;

import org.apache.logging.log4j.ThreadContext;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import io.opentelemetry.api.trace.Span;

import com.azure.storage.blob.*;
import com.azure.core.util.BinaryData;
import com.azure.identity.*;


/**
 * Azure Functions with HTTP Trigger.
 */
public class Function {
    
   /**
    * Using Log4j2 implementation for SLFJ
    * Could use Log4j2 directly too
   */ 
   private static final Logger logger = LoggerFactory.getLogger(Function.class.getName());

   private BlobServiceClient blobServiceClient;
   
   /*
   * Connecting to blob strage with a managed identity
   */
   public Function() {
      blobServiceClient = new BlobServiceClientBuilder()
        .endpoint(System.getenv("STORAGE_ENDPOINT"))
        .credential(new ManagedIdentityCredentialBuilder().build())
        .buildClient();
   }


   /*
   * The Java Agent (either Azure applicationinsights-agent-3.2.3 or the native one opentelemetry-javaagent.jar)
   * injects into the logging context (former MDC) "trace_id" and "span_id" values. See resources/log4j2.xml.
   * The C# ILogger injects these values as "TraceId" and "SpanId". These values are exported to customDimensions field 
   * of "traces" (or "exceptions") table in App Insights.
   * To be consistent, so we can hit same query against any span in the trace, we're setting values of TraceId and SpanId in the logger context.
   */
   private void initLoggerContext() {
        ThreadContext.put("TraceId", Span.current().getSpanContext().getTraceId());
        ThreadContext.put("SpanId", Span.current().getSpanContext().getSpanId());
    }

    
    /*
    * Saving a message into a iot_message_[TRACE_ID] blob with TRACE_ID tag in the blob's metadata.
    */
    private void saveMessagetoStorage(String iot_message) {
        String containerName = System.getenv("STORAGE_CONTAINER_NAME");
        BlobContainerClient containerClient = blobServiceClient.getBlobContainerClient(containerName);
        if (!containerClient.exists()) {
            containerClient.create();
        }
        String trace_id = Span.current().getSpanContext().getTraceId();
        BlobClient blobClient = containerClient.getBlobClient(String.format("iot_message_%s", trace_id));
        
        blobClient.upload(BinaryData.fromString(iot_message));

        Map<String, String> tags = new HashMap<String, String>();        
        tags.put("trace_id", trace_id);
        blobClient.setMetadata(tags); 
    }
    
    
    /*
    * This function is invoked by C# function to finish IoT message precessing. It saves the message to the blob storage.
    * The function is "auto-instrumented" with OpenTelemetry by applicationinsights-agent-3.2.3 Java agent. 
    * Locally the java agent is configured in local.settings.json as "JAVA_OPTS": "-javaagent:PATH_TO_applicationinsights-agent-3.2.3) (see https://docs.microsoft.com/en-us/azure/azure-monitor/app/java-in-process-agent#point-the-jvm-to-the-jar-file)
    * In the cloud the funcions app is configured as described here https://docs.microsoft.com/en-us/azure/azure-monitor/app/monitor-functions#how-to-enable-distributed-tracing-for-java-function-apps
    *
    * The Java agent performs the following:
    *   - automatically creates OpenTelemetry spans while interacting with the outer world
    *     - e.g. in this sample it catches "traceparent" header in the incoming request and creates a span for the function execution, 
    *      it also creates spans while interacting with the blobcontainer and managed identity service.  
    *   - injects trace_id and span_id in the logging (MDC) context so it can be used in the output
    *   - exports spans and logs (including MDC) to Application insights tables (dependencies, requests, traces, exceptions).    
    *      so that "Operation Id == TraceId, Id == SpanId, Parent Id == Parent SpanId"
    *
    * Instead of Azure specific Java agent (e.g. while running as a microservice on a K8s cluster), an OpenTelelmtry agent can be used.
    * See https://github.com/open-telemetry/opentelemetry-java-instrumentation.
    * It performs same as the Azure Java agent but it exports data using one of the standard exporters (https://github.com/open-telemetry/opentelemetry-java/tree/main/exporters)
    * rather than exporting data to Applicaion Insights.
    *
    * For "manual" instrumentation (createing your own spans) you need to define a tracer and use one of the exporters explicictly 
    * (https://docs.microsoft.com/en-us/java/api/overview/azure/monitor-opentelemetry-exporter-readme?view=azure-java-preview to expoort to App Insights or 
       https://github.com/open-telemetry/opentelemetry-java/tree/main/exporters to export to standard channels).
    *
    * See https://opentelemetry.io/docs/instrumentation/java/manual_instrumentation/ for manual instrumentation details. 
    */
    @FunctionName("process-by-java")
    public HttpResponseMessage run(
            @HttpTrigger(
                name = "req",
                methods = {HttpMethod.POST},
                authLevel = AuthorizationLevel.ANONYMOUS)
                HttpRequestMessage<Optional<String>> request,
            final ExecutionContext context) {
                initLoggerContext();    

            final String iotMessage = request.getBody().orElse(null);

            // The Java Agent (either Azure applicationinsights-agent-3.2.3 or the native one opentelemetry-javaagent.jar)
            // injects into the logging context (former MDC) "trace_id" and "span_id" values. See resources/log4j2.xml.
            logger.info("Java function received IoT Message: {}", iotMessage);
            
            //Custom attributes are not exported by Azure applications insights java agent (applicationinsights-agent-3.2.3)            
            //So it's not visible in Application Insights in this sample.
            //However, it might be picked up by OpenTelemetry exporters such as azure-monitor-opentelemetry-exporter or OtlpGrpcSpanExporter that 
            //are used for manual instrumentation.
            Span.current().setAttribute("MessageString", iotMessage);

            saveMessagetoStorage(iotMessage);

            return request.createResponseBuilder(HttpStatus.OK).build();

    }
}
