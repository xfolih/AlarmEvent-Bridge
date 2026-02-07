using System.Text.Json.Serialization;

namespace MilestoneWebhookGui.Config
{
    /// <summary>För GUI: sparar URL och användarnamn (lösenord valfritt för att kunna visa vid laddning).</summary>
    public class CredentialsFile
    {
        [JsonPropertyName("apiBaseUrl")]
        public string ApiBaseUrl { get; set; } = "";

        [JsonPropertyName("username")]
        public string Username { get; set; } = "";

        [JsonPropertyName("password")]
        public string? Password { get; set; }
    }
}
