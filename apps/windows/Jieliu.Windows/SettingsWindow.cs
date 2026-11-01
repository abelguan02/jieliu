using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace Jieliu.Windows;

internal sealed class SettingsWindow : Window
{
    private readonly Model model;
    private TextBlock? error;
    private readonly Action about;
    public SettingsWindow(Model model, Action about)
    {
        this.model = model; this.about = about;
        Width = 550; Height = 560; MinWidth = 450; MinHeight = 400;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        model.Changed += UpdateError;
        Closed += (_, _) => model.Changed -= UpdateError;
        Render();
    }
    private void Render()
    {
        Title = model.Text("截留 · 设置", "Jieliu · Settings") + " · " + typeof(SettingsWindow).Assembly.GetName().Version?.ToString(3);
        var stack = new StackPanel { Margin = new Thickness(26) };
        Content = new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        void Label(string zh, string en) => stack.Children.Add(new TextBlock { Text = model.Text(zh, en), Margin = new Thickness(0, 18, 0, 7), FontWeight = FontWeights.SemiBold });
        Label("语言 / Language", "Language / 语言");
        var language = new ComboBox { ItemsSource = new[] { "中文", "English" }, SelectedIndex = model.Settings.English ? 1 : 0 };
        language.SelectionChanged += (_, _) => { model.Settings.English = language.SelectedIndex == 1; model.SavePreferences(); Render(); };
        stack.Children.Add(language);
        Label("收起入口", "Collapsed entry");
        var entry = new ComboBox { ItemsSource = new[] { model.Text("取景框胶囊", "Viewfinder capsule"), model.Text("仅系统托盘图标", "System tray icon only") }, SelectedIndex = model.Settings.MenuOnly ? 1 : 0 };
        entry.SelectionChanged += (_, _) => { model.Settings.MenuOnly = entry.SelectedIndex == 1; model.SavePreferences(); Render(); };
        stack.Children.Add(entry);
        Label("展开样式", "Expanded appearance");
        stack.Children.Add(Panels.Styles(model));
        var auto = new CheckBox { Content = model.Text("鼠标离开后自动收起", "Collapse after pointer leaves"), IsChecked = model.Settings.AutoHide || model.Settings.MenuOnly, IsEnabled = !model.Settings.MenuOnly, Margin = new Thickness(0, 16, 0, 0) };
        auto.Click += (_, _) => { model.Settings.AutoHide = auto.IsChecked == true; model.SavePreferences(); }; stack.Children.Add(auto);
        var animations = new CheckBox { Content = model.Text("界面动效", "Interface animations"), IsChecked = model.Settings.Animations, Margin = new Thickness(0, 14, 0, 0) };
        animations.Click += (_, _) => { model.Settings.Animations = animations.IsChecked == true; model.SavePreferences(); }; stack.Children.Add(animations);
        if (!SystemParameters.ClientAreaAnimation) stack.Children.Add(Panels.Dim(model.Text("Windows 已关闭动画效果。", "Windows animations are turned off.")));
        Label("截图接入文件夹", "Screenshot input folder");
        stack.Children.Add(Panels.Folder(model, model.Settings.Source, path => model.Settings.Source = path, Render));
        Label("保存文件夹", "Archive folder");
        stack.Children.Add(Panels.Folder(model, model.Settings.Destination, path => model.Settings.Destination = path, Render));
        error = new TextBlock { TextWrapping = TextWrapping.Wrap, Foreground = Brushes.DarkRed, Margin = new Thickness(0, 18, 0, 0) }; stack.Children.Add(error); UpdateError();
        var diagnostics = new Button { Content = model.Text("导出动效诊断…", "Export animation diagnostics…"), Margin = new Thickness(0, 16, 0, 0), Padding = new Thickness(8) };
        diagnostics.Click += (_, _) =>
        {
            var dialog = new Microsoft.Win32.SaveFileDialog { FileName = "Jieliu-visual-diagnostics.json", Filter = "JSON (*.json)|*.json" };
            if (dialog.ShowDialog(this) != true) return;
            try { VisualDiagnostics.Save(dialog.FileName, model); }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { model.Error(ex.Message); }
        };
        stack.Children.Add(diagnostics);
        var link = Panels.Link(model.Text("关于截留", "About Jieliu"), about); link.Margin = new Thickness(0, 20, 0, 0);
        stack.Children.Add(link);
    }
    private void UpdateError() { if (error is not null) error.Text = model.LastError; }
}
