using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;

namespace Jieliu.Windows;

internal sealed class OnboardingWindow : Window
{
    private readonly Model model;
    private readonly Action start, finish;
    public int Page { get; private set; }
    /// <summary>Collected total when collection started; a larger total means the trial capture arrived.</summary>
    public long? Baseline { get; private set; }
    private bool Received => Baseline is { } baseline && model.History.Total > baseline;
    public OnboardingWindow(Model model, Action start, Action finish, int page = 0, long? baseline = null)
    {
        this.model = model; this.start = start; this.finish = finish; Page = page; Baseline = baseline;
        Width = 540; Height = 440; ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        model.PreferencesChanged += Render; model.Changed += Render;
        Closed += (_, _) => { model.PreferencesChanged -= Render; model.Changed -= Render; };
        Render();
    }
    private void Render()
    {
        Title = model.Text("欢迎使用截留", "Welcome to Jieliu");
        var root = new DockPanel { Margin = new Thickness(28) };
        var footer = new DockPanel { Margin = new Thickness(0, 16, 0, 0) }; DockPanel.SetDock(footer, Dock.Bottom);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal }; DockPanel.SetDock(buttons, Dock.Right);
        if (Page is > 0 and < 3) buttons.Children.Add(Button(model.Text("上一步", "Back"), () => { Page--; Render(); }, false));
        if (Page == 3 && model.LastCaptureError.Length > 0)
            buttons.Children.Add(Button(model.Text("返回配置", "Back to setup"), () => { Page = 2; Render(); }, false));
        buttons.Children.Add(Page switch
        {
            < 2 => Button(model.Text("下一步", "Continue"), () => { Page++; Render(); }, true),
            2 => Button(model.Text("开始收纳", "Start collecting"), () => { Baseline = model.History.Total; Page = 3; start(); Render(); }, true),
            _ => Received && model.LastCaptureError.Length == 0 ? Button(model.Text("完成", "Done"), finish, true) : Button(model.Text("跳过", "Skip"), finish, false)
        });
        footer.Children.Add(buttons);
        var dots = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        for (var i = 0; i < 4; i++) dots.Children.Add(new Ellipse { Width = 6, Height = 6, Margin = new Thickness(0, 0, 6, 0), Fill = i == Page ? Panels.Accent : Brushes.LightGray });
        footer.Children.Add(dots);
        root.Children.Add(footer);
        root.Children.Add(Page switch { 0 => Welcome(), 1 => Usage(), 2 => Setup(), _ => Trial() });
        Content = root;
    }
    private Button Button(string text, Action click, bool primary)
    {
        var button = new Button { Content = text, IsDefault = primary, MinWidth = 88, Padding = new Thickness(12, 5, 12, 5), Margin = new Thickness(8, 0, 0, 0) };
        button.Click += (_, _) => click();
        return button;
    }
    private StackPanel Welcome()
    {
        var stack = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 24, 0, 0) };
        stack.Children.Add(new Image { Source = Panels.AppIcon(), Width = 72, Height = 72 });
        stack.Children.Add(new TextBlock { Text = model.Text("欢迎使用截留", "Welcome to Jieliu"), FontSize = 26, FontWeight = FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 14, 0, 6) });
        stack.Children.Add(new TextBlock { Text = model.Text("截下的每一张，都有落点。", "A home for every screenshot."), Foreground = Brushes.DimGray, HorizontalAlignment = HorizontalAlignment.Center });
        var language = new ComboBox { ItemsSource = new[] { "中文", "English" }, SelectedIndex = model.Settings.English ? 1 : 0, Width = 180, Margin = new Thickness(0, 24, 0, 0) };
        language.SelectionChanged += (_, _) => { model.Settings.English = language.SelectedIndex == 1; model.SavePreferences(); };
        stack.Children.Add(language);
        return stack;
    }
    private StackPanel Trial()
    {
        var failed = model.LastCaptureError.Length > 0;
        var stack = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 48, 0, 0) };
        // Warning, camera and check mark from the Windows icon fonts.
        var icon = failed ? "\uE7BA" : Received ? "\uE73E" : "\uE722";
        var title = failed ? model.Text("截图收纳失败", "Could not collect the screenshot")
            : Received ? model.Text("已收进顶部托盘", "Collected in the tray") : model.Text("截一张试试", "Take a screenshot");
        stack.Children.Add(new TextBlock { Text = icon, FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"), FontSize = 48, Foreground = failed ? Brushes.DarkRed : Received ? Brushes.SeaGreen : Panels.Accent, HorizontalAlignment = HorizontalAlignment.Center });
        stack.Children.Add(new TextBlock { Text = title, FontSize = 24, FontWeight = FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 12, 0, 6) });
        if (failed)
        {
            var error = Panels.Dim(model.LastCaptureError, 14);
            error.Foreground = Brushes.DarkRed;
            stack.Children.Add(new ScrollViewer { Content = error, MaxWidth = 460, MaxHeight = 94,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled });
        }
        else
        {
            var detail = Panels.Dim(Received ? model.Text("拖到其他应用即可使用", "Drag it into any app") : model.Text("按 Win + Shift + S，框选任意区域", "Press Win + Shift + S and select any area"));
            detail.HorizontalAlignment = HorizontalAlignment.Center; stack.Children.Add(detail);
        }
        return stack;
    }
    private StackPanel Usage()
    {
        var stack = new StackPanel();
        stack.Children.Add(Panels.Heading(model.Text("怎么用", "How it works"), 22, 0));
        Step(stack, model.Text("照常截图", "Capture as usual"), "Win + Shift + S · Print Screen");
        Step(stack, model.Text("自动收进顶部托盘", "Collected at the top of the screen"), model.Text("托盘保留最近 8 张，原图归档到文件夹", "The tray keeps the latest 8; originals are archived"));
        Step(stack, model.Text("拖到其他应用即可使用", "Drag into any app"), model.Text("空格预览 · Ctrl+C 复制 · Delete 移出（文件保留）", "Space preview · Ctrl+C copy · Delete removes (file kept)"));
        return stack;
    }
    private static void Step(StackPanel stack, string title, string detail)
    {
        stack.Children.Add(new TextBlock { Text = title, FontSize = 14, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 20, 0, 0) });
        stack.Children.Add(Panels.Dim(detail));
    }
    private StackPanel Setup()
    {
        var stack = new StackPanel();
        stack.Children.Add(Panels.Heading(model.Text("准备开始", "Get ready"), 22, 0));
        stack.Children.Add(Panels.Heading(model.Text("展开样式", "Expanded appearance")));
        stack.Children.Add(Panels.Styles(model));
        stack.Children.Add(Panels.Heading(model.Text("截图接入文件夹", "Screenshot input folder")));
        stack.Children.Add(Panels.Folder(model, model.Settings.Source, path => model.Settings.Source = path, () => { }));
        stack.Children.Add(Panels.Heading(model.Text("保存文件夹", "Archive folder")));
        stack.Children.Add(Panels.Folder(model, model.Settings.Destination, path => model.Settings.Destination = path, () => { }));
        stack.Children.Add(new LaunchAtLoginControl(new RunLaunchAtLogin(model.Text), model.Text));
        stack.Children.Add(Panels.Dim(model.Text("在截图工具设置中开启自动保存，并保存到接入文件夹。", "Turn on automatic saving in Snipping Tool and save to the input folder."), 16));
        return stack;
    }
}
