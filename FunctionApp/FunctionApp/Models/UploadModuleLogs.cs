using Newtonsoft.Json;
using System.Collections.Generic;

namespace FunctionApp.Models
{
    public interface IMethodPayload { }

    public class UploadModuleLogs : IMethodPayload
    {
        [JsonProperty("schemaVersion")]
        public string SchemaVersion { get; set; }
        [JsonProperty("sasUrl")]
        public string SasUrl { get; set; }
        [JsonProperty("items")]
        public List<Item> Items { get; set; }
        [JsonProperty("encoding")]
        public string Encoding { get; set; }
        [JsonProperty("contentType")]
        public string ContentType { get; set; }

        public class Item
        {
            [JsonProperty("id")]
            public string Id { get; set; }
            [JsonProperty("filter")]
            public Filter Filter { get; set; }
        }

        public class Filter
        {
            [JsonProperty("tail")]
            public int? Tail { get; set; }
            [JsonProperty("since")]
            public string Since { get; set; }
            [JsonProperty("until")]
            public string Until { get; set; }
            [JsonProperty("loglevel")]
            public int? LogLevel { get; set; }
            [JsonProperty("regex")]
            public string Regex { get; set; }
        }
    }
}
