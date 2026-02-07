using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace MilestoneWebhookGui.Config
{
    public class WebhookConfigRoot
    {
        [JsonPropertyName("apiBaseUrl")]
        public string ApiBaseUrl { get; set; } = "";

        [JsonPropertyName("cameras")]
        public List<CameraEntry> Cameras { get; set; } = new();

        [JsonPropertyName("alarmActiveEventTypeId")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? AlarmActiveEventTypeId { get; set; }

        [JsonPropertyName("alarmInactiveEventTypeId")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? AlarmInactiveEventTypeId { get; set; }

        [JsonPropertyName("requireIoActive")]
        public bool RequireIoActive { get; set; } = true;
    }

    public class CameraEntry
    {
        [JsonPropertyName("cameraId")]
        public string CameraId { get; set; } = "";

        [JsonPropertyName("cameraName")]
        public string CameraName { get; set; } = "";

        [JsonPropertyName("eventTypeId")]
        public string EventTypeId { get; set; } = "";

        [JsonPropertyName("eventTypeName")]
        public string EventTypeName { get; set; } = "";

        [JsonPropertyName("ioSourceId")]
        public string IoSourceId { get; set; } = "";

        [JsonPropertyName("ioSourceName")]
        public string IoSourceName { get; set; } = "";

        [JsonPropertyName("ioType")]
        public string IoType { get; set; } = "";

        [JsonPropertyName("webhookUrl")]
        public string WebhookUrl { get; set; } = "";

        [JsonPropertyName("alarmActiveEventTypeId")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? AlarmActiveEventTypeId { get; set; }

        [JsonPropertyName("alarmInactiveEventTypeId")]
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? AlarmInactiveEventTypeId { get; set; }

        [JsonPropertyName("enabled")]
        public bool Enabled { get; set; } = true;
    }
}
