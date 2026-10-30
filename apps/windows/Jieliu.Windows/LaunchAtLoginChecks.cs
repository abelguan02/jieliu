using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;

namespace Jieliu.Windows;

internal static class LaunchAtLoginChecks
{
    public static void Run()
    {
        static void Check(bool value, string reason) { if (!value) throw new Exception(reason); }
        var folder = Path.Combine(Path.GetTempPath(), "jieliu-login-" + Guid.NewGuid().ToString("N"), "含 空格");
        var keyPath = @"Software\Jieliu.Checks\" + Guid.NewGuid().ToString("N");
        Directory.CreateDirectory(folder);
        try
        {
            var executable = Path.Combine(folder, "Jieliu.exe"); File.WriteAllText(executable, "fixture only");
            var startup = new RunLaunchAtLogin(executable, keyPath);
            Check(!startup.IsEnabled, "Login startup must default to unregistered");
            using (var key = Registry.CurrentUser.OpenSubKey(keyPath))
                Check(key is null, "Reading startup state must not create a registration key");
            using (var key = Registry.CurrentUser.CreateSubKey(keyPath)) key.SetValue("Unrelated", "keep");
            startup.SetEnabled(true);
            using (var key = Registry.CurrentUser.OpenSubKey(keyPath)!)
            {
                Check((string?)key.GetValue(RunLaunchAtLogin.ValueName) == "\"" + executable + "\"", "Startup command must quote the full executable path without a shell");
                Check(key.GetValueKind(RunLaunchAtLogin.ValueName) == RegistryValueKind.String, "Startup command must be REG_SZ");
            }
            Check(new RunLaunchAtLogin(executable, keyPath).IsEnabled, "Startup registration did not survive a new service instance");
            var movedPath = Path.Combine(folder, "moved", "Jieliu.exe"); Directory.CreateDirectory(Path.GetDirectoryName(movedPath)!); File.Copy(executable, movedPath);
            var moved = new RunLaunchAtLogin(movedPath, keyPath);
            Check(!moved.IsEnabled, "Old portable path must not appear enabled for the current executable");
            moved.SetEnabled(true);
            Check(moved.IsEnabled && !startup.IsEnabled, "Enabling from a moved app must replace the old path");
            moved.SetEnabled(false); moved.SetEnabled(false);
            using (var key = Registry.CurrentUser.OpenSubKey(keyPath)!)
                Check(key.GetValue(RunLaunchAtLogin.ValueName) is null && (string?)key.GetValue("Unrelated") == "keep", "Disabling must delete only our startup value");
            var host = Path.Combine(folder, "dotnet.exe"); File.Copy(executable, host);
            try { new RunLaunchAtLogin(host, keyPath).SetEnabled(true); throw new Exception("Registered a development host"); }
            catch (InvalidOperationException) { }
            try
            {
                new RunLaunchAtLogin(Path.Combine(folder, new string('x', 261), "Jieliu.exe"), keyPath).SetEnabled(true);
                throw new Exception("Accepted an oversized Run command");
            }
            catch (InvalidOperationException ex) { Check(ex.Message.Contains("shorter"), "Long path needs actionable feedback"); }
            File.Delete(executable);
            try { startup.SetEnabled(true); throw new Exception("Registered a missing executable"); }
            catch (InvalidOperationException) { }

            foreach (var english in new[] { false, true })
            {
                var service = new FakeStartup();
                var control = new LaunchAtLoginControl(service, (zh, en) => english ? en : zh);
                void Click(bool enabled) { control.Toggle.IsChecked = enabled; control.Toggle.RaiseEvent(new RoutedEventArgs(CheckBox.ClickEvent)); }
                Check((string)control.Toggle.Content == (english ? "Launch at login" : "登录时启动"), "Mac/Windows login label differs");
                Check(control.Toggle.IsChecked == false && control.Toggle.IsEnabled, "Initial startup state is wrong");
                Click(true); Check(service.Enabled && control.Toggle.IsChecked == true, "Enable click did not register");
                service.WriteFailure = true;
                Click(false); Check(control.Toggle.IsChecked == true && control.Status.Text.Contains("denied"), "Failed disable must retain actual enabled state and report failure");
                service.WriteFailure = false; Click(false);
                Check(!service.Enabled && control.Toggle.IsChecked == false && control.Status.Text == "", "Successful disable must clear the startup error");
                service.WriteFailure = true; Click(true);
                Check(control.Toggle.IsChecked == false && control.Status.Text.Contains(english ? "Could not update launch at login:" : "登录启动设置失败："), "Failed enable must roll back with localized feedback");
                service.ReadFailure = true; control.Refresh();
                Check(control.Toggle.IsChecked is null && !control.Toggle.IsEnabled && control.Status.Text.Contains("unavailable"), "Unreadable startup state must not be reported as off");
                service.ReadFailure = false; service.Enabled = true; control.Refresh();
                Check(control.Toggle.IsChecked == true && control.Toggle.IsEnabled && control.Status.Text == "", "Refresh must observe externally changed registration and recover from read failure");
                var invalid = new LaunchAtLoginControl(new RunLaunchAtLogin(host, keyPath, (zh, en) => english ? en : zh), (zh, en) => english ? en : zh);
                invalid.Toggle.IsChecked = true; invalid.Toggle.RaiseEvent(new RoutedEventArgs(CheckBox.ClickEvent));
                Check(invalid.Toggle.IsChecked == false && invalid.Status.Text.Contains(english ? "extracted" : "解压"), "Invalid program location must have localized actionable feedback");
            }
            Console.WriteLine("PASS: login startup isolated registry quoting, relocation, disable, bilingual UI state and failure recovery (no real startup registration)");
        }
        finally
        {
            Registry.CurrentUser.DeleteSubKeyTree(keyPath, false);
            Directory.Delete(Directory.GetParent(folder)!.FullName, true);
        }
    }

    private sealed class FakeStartup : ILaunchAtLogin
    {
        public bool Enabled, ReadFailure, WriteFailure;
        public bool IsEnabled => ReadFailure ? throw new IOException("unavailable") : Enabled;
        public void SetEnabled(bool enabled)
        {
            if (WriteFailure) throw new UnauthorizedAccessException("denied");
            Enabled = enabled;
        }
    }
}
