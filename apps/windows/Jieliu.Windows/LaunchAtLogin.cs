using System;
using System.IO;
using Microsoft.Win32;

namespace Jieliu.Windows;

internal interface ILaunchAtLogin
{
    bool IsEnabled { get; }
    void SetEnabled(bool enabled);
}

// Read the OS registration, rather than duplicating it in settings.json.
// Windows Settings can separately disable a registered startup entry.
internal sealed class RunLaunchAtLogin : ILaunchAtLogin
{
    internal const string ValueName = "Jieliu";
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private readonly string executablePath;
    private readonly string keyPath;
    private string Command => "\"" + executablePath + "\"";

    public RunLaunchAtLogin() : this(Environment.ProcessPath ?? "") { }

    // Checks supply an isolated, non-startup registry key; never edit real login
    // registration from --render-check.
    internal RunLaunchAtLogin(string executablePath, string keyPath = RunKey)
    {
        this.executablePath = executablePath;
        this.keyPath = keyPath;
    }

    public bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(keyPath);
            return string.Equals(key?.GetValue(ValueName, null, RegistryValueOptions.DoNotExpandEnvironmentNames) as string,
                Command, StringComparison.OrdinalIgnoreCase);
        }
    }

    public void SetEnabled(bool enabled)
    {
        if (enabled)
        {
            if (!Path.IsPathFullyQualified(executablePath) || !File.Exists(executablePath)
                || !string.Equals(Path.GetFileName(executablePath), "Jieliu.exe", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Launch the extracted Jieliu.exe before enabling launch at login.");
            // Run command lines are limited to 260 characters by Windows.
            if (Command.Length > 260)
                throw new InvalidOperationException("Move Jieliu to a shorter folder path before enabling launch at login.");
            using var key = Registry.CurrentUser.CreateSubKey(keyPath);
            key.SetValue(ValueName, Command, RegistryValueKind.String);
        }
        else
        {
            using var key = Registry.CurrentUser.OpenSubKey(keyPath, writable: true);
            key?.DeleteValue(ValueName, throwOnMissingValue: false);
        }
        if (IsEnabled != enabled)
            throw new IOException("Windows did not retain the requested launch at login registration.");
    }
}
