using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using Jieliu.Core;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

namespace Jieliu.Windows;

internal sealed class Program : Application
{
    private readonly Model model = new();
    private readonly List<TrayWindow> panels = [];
    private Forms.NotifyIcon? icon;
    private CaptureWatcher? watcher;
    private SettingsWindow? settings;
    private readonly SemaphoreSlim watcherChange = new(1, 1);
    private string watchedSource = "", watchedDestination = "";
    private bool exiting;

    [STAThread]
    public static void Main(string[] args)
    {
        if (args.Contains("--self-check"))
        {
            _ = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            try { SelfChecks.Run(); }
            catch (Exception ex) { Console.Error.WriteLine(ex); Environment.ExitCode = 1; }
            return;
        }
        using var singleton = new Mutex(true, @"Local\Jieliu.Windows", out var first);
        if (!first) return;
        var app = new Program { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Run();
    }
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        icon = new Forms.NotifyIcon { Icon = TrayIcon.Create(), Text = "截留 · Jieliu", Visible = true };
        icon.MouseClick += (_, args) => { if (args.Button == Forms.MouseButtons.Left) Expand(); };
        model.PreferencesChanged += PreferencesChanged;
        model.Received += OnCapture;
        RebuildPanels(); BuildMenu();
        SystemEvents.DisplaySettingsChanged += DisplaysChanged;
        _ = RestartWatcher();
    }
    private void DisplaysChanged(object? sender, EventArgs e) => Dispatcher.BeginInvoke(RebuildPanels);
    private void RebuildPanels()
    {
        foreach (var panel in panels) panel.Close(); panels.Clear();
        foreach (var screen in Forms.Screen.AllScreens)
        {
            var panel = new TrayWindow(model, screen, ShowSettings); panels.Add(panel); panel.RefreshVisibility();
        }
    }
    private void PreferencesChanged()
    {
        BuildMenu(); foreach (var panel in panels) panel.RefreshVisibility();
        _ = RestartWatcher();
    }
    private async Task RestartWatcher()
    {
        await watcherChange.WaitAsync();
        try
        {
            if (exiting || (watcher is not null && watchedSource == model.Settings.Source && watchedDestination == model.Settings.Destination)) return;
            if (watcher is not null) await watcher.DisposeAsync();
            watcher = null;
            var next = new CaptureWatcher([model.Settings.Source], model.Settings.Destination, Model.Dimensions);
            next.Captured += capture => Dispatcher.BeginInvoke(() => { if (!exiting) model.Receive(capture); });
            next.Error += error => Dispatcher.BeginInvoke(() => model.Error(error));
            next.Start(); watcher = next;
            watchedSource = model.Settings.Source; watchedDestination = model.Settings.Destination;
        }
        catch (Exception ex) when (ex is IOException or ArgumentException or UnauthorizedAccessException) { model.Error(ex.Message); }
        finally { watcherChange.Release(); }
    }
    private void BuildMenu()
    {
        var old = icon!.ContextMenuStrip;
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add(model.Text("展开托盘", "Open tray"), null, (_, _) => Expand());
        menu.Items.Add(model.Text("设置…", "Settings…"), null, (_, _) => ShowSettings());
        menu.Items.Add(model.Text("打开截图文件夹", "Open screenshot folder"), null, (_, _) => OpenFolder());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(model.Text("退出截留", "Quit Jieliu"), null, async (_, _) => await Quit());
        icon.ContextMenuStrip = menu; old?.Dispose();
    }
    private void OnCapture(Capture capture)
    {
        // Saved files have no reliable source-monitor rectangle. Explicit mouse fallback.
        var screen = Forms.Screen.FromPoint(Forms.Cursor.Position);
        panels.FirstOrDefault(p => p.Screen.DeviceName == screen.DeviceName)?.Present(capture);
    }
    private void Expand()
    {
        var screen = Forms.Screen.FromPoint(Forms.Cursor.Position);
        panels.FirstOrDefault(p => p.Screen.DeviceName == screen.DeviceName)?.Expand(false);
    }
    private void ShowSettings()
    {
        if (settings is null) { settings = new SettingsWindow(model); settings.Closed += (_, _) => settings = null; }
        settings.Show(); settings.Activate();
    }
    private void OpenFolder()
    {
        try { Directory.CreateDirectory(model.Settings.Destination); Process.Start(new ProcessStartInfo(model.Settings.Destination) { UseShellExecute = true }); }
        catch (Exception ex) { model.Error(ex.Message); }
    }
    private async Task Quit()
    {
        if (exiting) return; exiting = true;
        SystemEvents.DisplaySettingsChanged -= DisplaysChanged;
        await watcherChange.WaitAsync();
        try { if (watcher is not null) await watcher.DisposeAsync(); }
        finally { watcherChange.Release(); }
        icon?.Dispose(); Shutdown();
    }
}
