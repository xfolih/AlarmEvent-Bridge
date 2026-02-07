using System;
using System.IO;
using System.Windows;
using System.Windows.Threading;

namespace MilestoneWebhookGui
{
    public partial class App : Application
    {
        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);
            
            // Global exception handling
            AppDomain.CurrentDomain.UnhandledException += (sender, args) =>
            {
                var logPath = Path.Combine(AppContext.BaseDirectory, "error.log");
                File.WriteAllText(logPath, $"Unhandled Exception: {args.ExceptionObject}\n\nStack Trace:\n{Environment.StackTrace}");
                MessageBox.Show($"An error occurred. Check error.log for details.\n\n{args.ExceptionObject}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            };

            DispatcherUnhandledException += (sender, args) =>
            {
                var logPath = Path.Combine(AppContext.BaseDirectory, "error.log");
                File.WriteAllText(logPath, $"Dispatcher Exception: {args.Exception}\n\nStack Trace:\n{args.Exception.StackTrace}");
                MessageBox.Show($"An error occurred. Check error.log for details.\n\n{args.Exception.Message}", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
                args.Handled = true;
            };
        }
    }
}
