; Inno Setup Script for AlarmEvent Bridge
; Build with: Inno Setup Compiler (free download from jrsoftware.org)
; Repository: https://github.com/xfolih/AlarmEvent-Bridge

#define AppName "AlarmEvent Bridge"
#define AppVersion "1.0.0"
#define AppPublisher "AlarmEvent Bridge"
#define AppURL "https://github.com/xfolih/AlarmEvent-Bridge"
#define AppExeName "AlarmEventBridge.exe"

[Setup]
AppId={{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
DefaultDirName={autopf}\AlarmEventBridge
DefaultGroupName={#AppName}
AllowNoIcons=yes
LicenseFile=
OutputDir=installer
OutputBaseFilename=AlarmEventBridge-Setup-v{#AppVersion}
SetupIconFile=MilestoneWebhookGui\icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=no
DisableReadyPage=no
DisableFinishedPage=no

[Languages]
Name: "swedish"; MessagesFile: "compiler:Languages\Swedish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "installservice"; Description: "Install as Windows Service (recommended for production)"; GroupDescription: "Service"

[Files]
; Main executable and dependencies (EXCLUDE user config files)
Source: "MilestoneWebhookGui\bin\Release\net6.0-windows\*.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "MilestoneWebhookGui\bin\Release\net6.0-windows\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "MilestoneWebhookGui\bin\Release\net6.0-windows\*.deps.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "MilestoneWebhookGui\bin\Release\net6.0-windows\*.runtimeconfig.json"; DestDir: "{app}"; Flags: ignoreversion
; Ensure icon and manifest are included
Source: "MilestoneWebhookGui\icon.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "MilestoneWebhookGui\app.manifest"; DestDir: "{app}"; Flags: ignoreversion

; PowerShell scripts (REQUIRED for functionality)
Source: "Start-MilestoneWebhookBridge.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "MilestoneApi.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "Get-MilestoneConfigData.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "Test-MilestoneConnection.ps1"; DestDir: "{app}"; Flags: ignoreversion

; Optional service/watchdog scripts (included if service installation is selected)
Source: "Run-MilestoneWebhookBridgeWatchdog.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "Install-MilestoneWebhookService.ps1"; DestDir: "{app}"; Flags: ignoreversion

; DO NOT include user config files:
; - Credentials.json
; - Credentials.ps1
; - WebhookConfig.json
; - error.log
; - Any .md files

; Create Logs directory
[Dirs]
Name: "{app}\Logs"; Permissions: users-modify

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\Install-MilestoneWebhookService.ps1"""; StatusMsg: "Installing Windows Service..."; Flags: waituntilterminated; Tasks: installservice
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""Stop-Service -Name AlarmEventBridge -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2; sc.exe delete AlarmEventBridge"""; Flags: waituntilterminated; RunOnceId: "UninstallService"

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
