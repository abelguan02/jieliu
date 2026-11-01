using System;
using System.IO;
using System.Security;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Jieliu.Windows;

internal sealed class LaunchAtLoginControl : StackPanel
{
    private readonly ILaunchAtLogin startup;
    private readonly Func<string, string, string> text;
    internal CheckBox Toggle { get; }
    internal TextBlock Status { get; }

    public LaunchAtLoginControl(ILaunchAtLogin startup, Func<string, string, string> text)
    {
        this.startup = startup;
        this.text = text;
        Margin = new Thickness(0, 14, 0, 0);
        Toggle = new CheckBox { Content = text("登录时启动", "Launch at login") };
        Toggle.Click += (_, _) => UpdateRegistration();
        Children.Add(Toggle);
        Toggle.ToolTip = text("移动程序后需重新开启；若在 Windows 启动设置中禁用，请在那里启用。",
            "Enable again after moving the app. If disabled in Windows Startup settings, re-enable it there.");
        Status = new TextBlock { TextWrapping = TextWrapping.Wrap, Foreground = Brushes.DarkRed, Margin = new Thickness(0, 6, 0, 0) };
        Children.Add(Status);
        Refresh();
    }

    private string ErrorPrefix => text("登录启动设置失败：", "Could not update launch at login: ");
    private static bool IsStartupError(Exception error) => error is IOException or UnauthorizedAccessException
        or SecurityException or InvalidOperationException or ArgumentException;

    internal void Refresh()
    {
        try
        {
            Toggle.IsChecked = startup.IsEnabled;
            Toggle.IsEnabled = true;
            Status.Text = "";
        }
        catch (Exception ex) when (IsStartupError(ex))
        {
            Toggle.IsChecked = null;
            Toggle.IsEnabled = false;
            Status.Text = ErrorPrefix + ex.Message;
        }
    }

    private void UpdateRegistration()
    {
        try { startup.SetEnabled(Toggle.IsChecked == true); Refresh(); }
        catch (Exception ex) when (IsStartupError(ex))
        {
            Refresh();
            Status.Text = ErrorPrefix + ex.Message + (Status.Text.Length > 0 ? "\n" + Status.Text : "");
        }
    }
}
