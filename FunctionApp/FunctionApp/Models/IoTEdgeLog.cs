using System;
using Newtonsoft.Json;

namespace FunctionApp.Models
{
    public class IoTEdgeLog
    {
        [JsonProperty("iothub")]
        public string IoTHub { get; set; }
        [JsonProperty("device")]
        public string DeviceId { get; set; }
        [JsonProperty("id")]
        public string ModuleId { get; set; }
        [JsonProperty("stream")]
        public string Stream { get; set; }
        [JsonProperty("loglevel")]
        public int LogLevel { get; set; }
        [JsonProperty("text")]
        public string Text { get; set; }
        [JsonProperty("timestamp")]
        public DateTime Timestamp { get; set; }
    }
}
