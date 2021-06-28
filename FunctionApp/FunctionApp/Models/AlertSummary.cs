using Newtonsoft.Json;

namespace FunctionApp.Models
{
    public class AlertSummary
    {
        [JsonProperty("windowSize")]
        public string WindowSize { get; set; }
        [JsonProperty("dimensions")]
        public AlertDimension[] Dimensions { get; set; }
        
        public class Device
        {
            [JsonProperty("deviceId")]
            public string DeviceId { get; set; }
        }

        public class AlertDimension
        {
            [JsonProperty("deviceId")]
            public Device Device { get; set; }
            [JsonProperty("resourceId")]
            public string ResourceId { get; set; }
        }
    }
}
