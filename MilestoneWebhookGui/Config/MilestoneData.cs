using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace MilestoneWebhookGui.Config
{
    /// <summary>JSON från Get-MilestoneConfigData.ps1</summary>
    public class MilestoneData
    {
        [JsonPropertyName("cameras")]
        public List<IdName> Cameras { get; set; } = new();

        [JsonPropertyName("eventTypes")]
        public List<IdName> EventTypes { get; set; } = new();

        [JsonPropertyName("ioList")]
        public List<IoItem> IoList { get; set; } = new();
    }

    public class IdName
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = "";

        [JsonPropertyName("name")]
        public string Name { get; set; } = "";
    }

    public class IoItem
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = "";

        [JsonPropertyName("name")]
        public string Name { get; set; } = "";

        [JsonPropertyName("type")]
        public string Type { get; set; } = "";
    }
}
