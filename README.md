# AlarmEvent Bridge

Advanced camera event → webhook forwarding for Milestone XProtect

## Description

AlarmEvent Bridge connects to Milestone XProtect via their API and forwards camera analysis events as webhooks to your alarm center when alarms are active.

## Features

- GUI configuration tool (WPF, C#)
- Real-time event monitoring via WebSocket
- Configurable webhook conditions (IO/User-defined events)
- Windows Service support for production deployment
- Automatic token refresh
- Watchdog service for reliability

## Requirements

- Windows Server 2016+ or Windows 10/11
- .NET 6.0 Runtime
- Milestone XProtect Management Server
- Administrator rights for installation

## Installation

1. Download and run `AlarmEventBridge-Setup-v1.0.0.exe`
2. Follow the installation wizard
3. Optionally install as Windows Service (recommended for production)

## Building from Source

1. Install .NET 6.0 SDK
2. Install Inno Setup (for creating installer)
3. Build the project:
   ```bash
   cd MilestoneWebhookGui
   dotnet build -c Release
   ```
4. Create installer:
   - Open `AlarmEventBridge.iss` in Inno Setup Compiler
   - Build → Compile (F9)

## License

GPL-3.0

## Repository

https://github.com/xfolih/AlarmEvent-Bridge
