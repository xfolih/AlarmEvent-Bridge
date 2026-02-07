using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using MilestoneWebhookGui.Config;

namespace MilestoneWebhookGui
{
    public partial class MainWindow
    {
        private string _configDir = "";
        private string _configPath = "";
        private string _credentialsPath = "";
        private string _credentialsJsonPath = "";
        private Process? _bridgeProcess;
        private MilestoneData? _apiData;
        private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true, WriteIndented = true };

        public MainWindow()
        {
            InitializeComponent();
            _configDir = GetConfigDirectory();
            _configPath = Path.Combine(_configDir, "WebhookConfig.json");
            _credentialsPath = Path.Combine(_configDir, "Credentials.ps1");
            _credentialsJsonPath = Path.Combine(_configDir, "Credentials.json");
            LoadAll();
        }

        private static string GetConfigDirectory()
        {
            var baseDir = AppContext.BaseDirectory;
            var scriptPath = Path.Combine(baseDir, "Start-MilestoneWebhookBridge.ps1");
            if (File.Exists(scriptPath)) return baseDir;
            var current = Environment.CurrentDirectory;
            if (File.Exists(Path.Combine(current, "Start-MilestoneWebhookBridge.ps1"))) return current;
            return baseDir;
        }

        private void LoadAll()
        {
            LoadCredentials();
            LoadWebhookConfig();
        }

        private void LoadCredentials()
        {
            if (File.Exists(_credentialsJsonPath))
            {
                try
                {
                    var json = File.ReadAllText(_credentialsJsonPath);
                    var cred = JsonSerializer.Deserialize<CredentialsFile>(json, JsonOptions);
                    if (cred != null)
                    {
                        TbApiUrl.Text = cred.ApiBaseUrl;
                        TbUsername.Text = cred.Username;
                        TbPassword.Password = cred.Password ?? "";
                        return;
                    }
                }
                catch { }
            }
            if (File.Exists(_credentialsPath))
            {
                try
                {
                    var content = File.ReadAllText(_credentialsPath);
                    var url = ExtractRegex(content, @"\$MilestoneApiBaseUrl\s*=\s*""([^""]+)""");
                    var user = ExtractRegex(content, @"\$MilestoneUsername\s*=\s*""([^""]+)""");
                    if (url != null) TbApiUrl.Text = url;
                    if (user != null) TbUsername.Text = user;
                }
                catch { }
            }
        }

        private static string? ExtractRegex(string content, string pattern)
        {
            var m = System.Text.RegularExpressions.Regex.Match(content, pattern);
            return m.Success ? m.Groups[1].Value : null;
        }

        private void LoadWebhookConfig()
        {
            if (!File.Exists(_configPath))
            {
                DgCameras.ItemsSource = new List<CameraEntry>();
                return;
            }
            try
            {
                var json = File.ReadAllText(_configPath);
                var root = JsonSerializer.Deserialize<WebhookConfigRoot>(json, JsonOptions);
                if (root == null) return;
                TbApiUrl.Text = root.ApiBaseUrl;
                ChkRequireIoActive.IsChecked = root.RequireIoActive;
                DgCameras.ItemsSource = root.Cameras;
            }
            catch
            {
                DgCameras.ItemsSource = new List<CameraEntry>();
            }
        }


        private void SaveWebhookConfig()
        {
            var list = DgCameras.ItemsSource as List<CameraEntry>;
            if (list == null) list = new List<CameraEntry>();
            var root = new WebhookConfigRoot
            {
                ApiBaseUrl = TbApiUrl.Text.Trim(),
                Cameras = list,
                RequireIoActive = ChkRequireIoActive.IsChecked == true
            };
            File.WriteAllText(_configPath, JsonSerializer.Serialize(root, new JsonSerializerOptions { WriteIndented = true, PropertyNamingPolicy = JsonNamingPolicy.CamelCase }));
        }

        private void BtnSaveCredentials_Click(object sender, RoutedEventArgs e)
        {
            var url = TbApiUrl.Text.Trim();
            var user = TbUsername.Text;
            var pass = TbPassword.Password;
            if (string.IsNullOrEmpty(url)) { MessageBox.Show("Ange API-adress."); return; }
            var content = "# Skapad av Milestone Webhook Manager\r\n" +
                "$MilestoneApiBaseUrl = \"" + url.Replace("\"", "`\"") + "\"\r\n" +
                "$MilestoneUsername = \"" + (user ?? "").Replace("\"", "`\"") + "\"\r\n" +
                "$MilestonePassword = \"" + (pass ?? "").Replace("\"", "`\"") + "\"\r\n";
            File.WriteAllText(_credentialsPath, content);
            var credJson = new CredentialsFile { ApiBaseUrl = url, Username = user ?? "", Password = pass };
            File.WriteAllText(_credentialsJsonPath, JsonSerializer.Serialize(credJson, new JsonSerializerOptions { WriteIndented = true }));
            TbStatus.Text = "Uppgifter sparade. Du kan nu l\u00e4gga till kameror och starta bryggan.";
        }

        private void BtnTestConnection_Click(object sender, RoutedEventArgs e)
        {
            BtnSaveCredentials_Click(sender, e);
            TbStatus.Text = "Testar anslutning...";
            UpdateLayout();
            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + Path.Combine(_configDir, "Test-MilestoneConnection.ps1") + "\"",
                WorkingDirectory = _configDir,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };
            try
            {
                using var p = Process.Start(psi);
                if (p == null)
                {
                    TbStatus.Text = "Kunde inte starta test-process.";
                    return;
                }
                var stdout = p.StandardOutput.ReadToEnd();
                var stderr = p.StandardError.ReadToEnd();
                p.WaitForExit(30000); // Max 30 sekunder
                var allOutput = stdout + (string.IsNullOrEmpty(stderr) ? "" : "\n" + stderr);
                if (p.ExitCode == 0)
                {
                    TbStatus.Text = "Anslutning lyckades! " + (stdout.Contains("Klart") ? "Milestone API fungerar." : "");
                }
                else
                {
                    var errorMsg = string.IsNullOrEmpty(stderr) ? stdout : stderr;
                    if (string.IsNullOrEmpty(errorMsg)) errorMsg = "Okänt fel (exit code: " + p.ExitCode + ")";
                    TbStatus.Text = "Anslutning misslyckades: " + errorMsg;
                    MessageBox.Show("Anslutning misslyckades:\n\n" + errorMsg, "Testa anslutning", MessageBoxButton.OK, MessageBoxImage.Error);
                }
            }
            catch (Exception ex)
            {
                TbStatus.Text = "Fel vid test: " + ex.Message;
                MessageBox.Show("Kunde inte starta test: " + ex.Message, "Fel", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void BtnDiscover_Click(object sender, RoutedEventArgs e)
        {
            var urls = new[] { "https://localhost", "https://127.0.0.1", "http://localhost", "http://127.0.0.1" };
            foreach (var u in urls)
            {
                TbApiUrl.Text = u;
                TbStatus.Text = "Testar " + u + " ...";
                UpdateLayout();
                if (FetchApiData()) { TbStatus.Text = "Anslutning hittad: " + u; return; }
            }
            TbStatus.Text = "Ingen vanlig adress svarade. Kontrollera att Milestone Management Server k\u00f6r och att adressen \u00e4r r\u00e4tt.";
        }

        private bool FetchApiData()
        {
            if (!File.Exists(_credentialsPath)) return false;
            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + Path.Combine(_configDir, "Get-MilestoneConfigData.ps1") + "\"",
                WorkingDirectory = _configDir,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };
            try
            {
                using var p = Process.Start(psi);
                if (p == null) return false;
                var stdout = p.StandardOutput.ReadToEnd();
                var stderr = p.StandardError.ReadToEnd();
                p.WaitForExit(15000);
                if (p.ExitCode != 0) return false;
                _apiData = JsonSerializer.Deserialize<MilestoneData>(stdout, JsonOptions);
                return _apiData != null;
            }
            catch { return false; }
        }

        private void BtnRefreshFromApi_Click(object sender, RoutedEventArgs e)
        {
            BtnSaveCredentials_Click(sender, e);
            TbStatus.Text = "H\u00e4mtar listor från Milestone...";
            UpdateLayout();
            if (FetchApiData())
                TbStatus.Text = "Listor h\u00e4mtade. Du kan nu l\u00e4gga till kameror.";
            else
                MessageBox.Show("Kunde inte h\u00e4mta data. Kontrollera anslutning och att uppgifterna \u00e4r sparade.");
        }

        private void BtnAddCamera_Click(object sender, RoutedEventArgs e)
        {
            if (_apiData == null) { MessageBox.Show("Klicka f\u00f6rst p\u00e5 \"H\u00e4mta lista från Milestone\"."); return; }
            var dlg = new CameraEditWindow(_apiData, null, _configDir);
            if (dlg.ShowDialog() != true) return;
            var list = (DgCameras.ItemsSource as List<CameraEntry>) ?? new List<CameraEntry>();
            list.Add(dlg.Result!);
            DgCameras.ItemsSource = null;
            DgCameras.ItemsSource = list;
            SaveWebhookConfig();
        }

        private void BtnEditCamera_Click(object sender, RoutedEventArgs e)
        {
            if (_apiData == null || sender is not Button btn || btn.Tag is not CameraEntry entry) return;
            var list = DgCameras.ItemsSource as List<CameraEntry>;
            var dlg = new CameraEditWindow(_apiData, entry, _configDir);
            if (dlg.ShowDialog() != true) return;
            var idx = list?.IndexOf(entry) ?? -1;
            if (idx >= 0 && list != null) list[idx] = dlg.Result!;
            DgCameras.ItemsSource = null;
            DgCameras.ItemsSource = list;
            SaveWebhookConfig();
        }

        private void BtnRemoveCamera_Click(object sender, RoutedEventArgs e)
        {
            if (sender is not Button btn || btn.Tag is not CameraEntry entry) return;
            var list = DgCameras.ItemsSource as List<CameraEntry>;
            if (list == null) return;
            list.Remove(entry);
            DgCameras.ItemsSource = null;
            DgCameras.ItemsSource = list;
            SaveWebhookConfig();
        }

        private void DgCameras_SelectionChanged(object sender, SelectionChangedEventArgs e) { }

        private void BtnSaveConfig_Click(object sender, RoutedEventArgs e)
        {
            SaveWebhookConfig();
            TbStatus.Text = "Konfiguration sparad.";
        }

        private void BtnStartBridge_Click(object sender, RoutedEventArgs e)
        {
            SaveWebhookConfig();
            var scriptPath = Path.Combine(_configDir, "Start-MilestoneWebhookBridge.ps1");
            if (!File.Exists(scriptPath)) { MessageBox.Show("Start-MilestoneWebhookBridge.ps1 hittades inte i mappen."); return; }
            var list = DgCameras.ItemsSource as List<CameraEntry>;
            var enabledCount = list?.FindAll(c => c.Enabled).Count ?? 0;
            if (enabledCount == 0) { MessageBox.Show("Aktivera minst en kamera eller l\u00e4gg till en."); return; }
            
            AppendLog("=== Brygga startar ===");
            AppendLog($"Kör skript: {scriptPath}");
            AppendLog("");
            
            _bridgeProcess = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + scriptPath + "\"",
                    WorkingDirectory = _configDir,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                    StandardOutputEncoding = Encoding.UTF8,
                    StandardErrorEncoding = Encoding.UTF8
                }
            };
            _bridgeProcess.EnableRaisingEvents = true;
            _bridgeProcess.OutputDataReceived += (s, args) => {
                if (!string.IsNullOrEmpty(args.Data))
                    Dispatcher.Invoke(() => AppendLog(args.Data));
            };
            _bridgeProcess.ErrorDataReceived += (s, args) => {
                if (!string.IsNullOrEmpty(args.Data))
                    Dispatcher.Invoke(() => AppendLog($"[FEL] {args.Data}"));
            };
            _bridgeProcess.Exited += (_, _) => Dispatcher.Invoke(() => {
                BtnStartBridge.IsEnabled = true;
                BtnStopBridge.IsEnabled = false;
                TbStatus.Text = "Bryggan avslutad.";
                AppendLog("");
                AppendLog("=== Brygga avslutad ===");
            });
            
            try
            {
                _bridgeProcess.Start();
                _bridgeProcess.BeginOutputReadLine();
                _bridgeProcess.BeginErrorReadLine();
                BtnStartBridge.IsEnabled = false;
                BtnStopBridge.IsEnabled = true;
                TbStatus.Text = "Bryggan kör. Se loggen för status.";
            }
            catch (Exception ex)
            {
                AppendLog($"[FEL] Kunde inte starta bryggan: {ex.Message}");
                MessageBox.Show($"Kunde inte starta bryggan: {ex.Message}", "Fel", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void BtnStopBridge_Click(object sender, RoutedEventArgs e)
        {
            if (_bridgeProcess != null && !_bridgeProcess.HasExited)
            {
                AppendLog("");
                AppendLog("=== Stoppar brygga ===");
                _bridgeProcess.Kill();
                _bridgeProcess = null;
            }
            BtnStartBridge.IsEnabled = true;
            BtnStopBridge.IsEnabled = false;
            TbStatus.Text = "Bryggan stoppad.";
        }

        private void BtnClearLog_Click(object sender, RoutedEventArgs e)
        {
            TbBridgeLog.Clear();
        }

        private void BtnToggleLog_Click(object sender, RoutedEventArgs e)
        {
            if (LogColumn.Width.Value > 50)
            {
                // Minimera - gör den smal men synlig (bara knapp)
                LogColumn.Width = new GridLength(35);
                LogSplitter.Visibility = Visibility.Collapsed;
                LogScrollViewer.Visibility = Visibility.Collapsed;
                BtnClearLog.Visibility = Visibility.Collapsed;
                TbLogHeader.Visibility = Visibility.Collapsed;
                TbToggleIcon.Text = "▶";
                BtnToggleLog.ToolTip = "Maximera konsoll";
            }
            else
            {
                // Maximera
                LogColumn.Width = new GridLength(400);
                LogSplitter.Visibility = Visibility.Visible;
                LogScrollViewer.Visibility = Visibility.Visible;
                BtnClearLog.Visibility = Visibility.Visible;
                TbLogHeader.Visibility = Visibility.Visible;
                TbToggleIcon.Text = "◀";
                BtnToggleLog.ToolTip = "Minimera konsoll";
            }
        }

        private void AppendLog(string message)
        {
            if (string.IsNullOrEmpty(message)) return;
            var timestamp = DateTime.Now.ToString("HH:mm:ss");
            TbBridgeLog.AppendText($"[{timestamp}] {message}\r\n");
            TbBridgeLog.ScrollToEnd();
        }

        protected override void OnClosed(EventArgs e)
        {
            if (_bridgeProcess != null && !_bridgeProcess.HasExited)
                _bridgeProcess.Kill();
            base.OnClosed(e);
        }
    }
}
