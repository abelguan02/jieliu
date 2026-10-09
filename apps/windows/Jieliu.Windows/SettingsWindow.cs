using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Forms = System.Windows.Forms;

namespace Jieliu.Windows;

internal sealed class SettingsWindow : Window
{
    private readonly Model model;
    private TextBlock? error;
    public SettingsWindow(Model model)
    {
        this.model = model;
        Width = 550; Height = 640; MinWidth = 450; MinHeight = 400;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        model.Changed += UpdateError;
        Closed += (_, _) => model.Changed -= UpdateError;
        Render();
    }
    private void Render()
    {
        Title = model.Text("截留 · 设置", "Jieliu · Settings");
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
        var style = new ComboBox { ItemsSource = new[] { model.Text("A · 标尺", "A · Ruler"), model.Text("B · 帧缓冲", "B · Buffer"), model.Text("C · 图层", "C · Layers") }, SelectedIndex = model.Settings.Style[0] - 'A' };
        style.SelectionChanged += (_, _) => { model.Settings.Style = ((char)('A' + style.SelectedIndex)).ToString(); model.SavePreferences(); };
        stack.Children.Add(style);
        var auto = new CheckBox { Content = model.Text("鼠标离开后自动收起", "Collapse after pointer leaves"), IsChecked = model.Settings.AutoHide || model.Settings.MenuOnly, IsEnabled = !model.Settings.MenuOnly, Margin = new Thickness(0, 16, 0, 0) };
        auto.Click += (_, _) => { model.Settings.AutoHide = auto.IsChecked == true; model.SavePreferences(); }; stack.Children.Add(auto);
        Label("截图接入文件夹", "Screenshot input folder");
        Folder(stack, model.Settings.Source, path => model.Settings.Source = path);
        Label("保存文件夹", "Archive folder");
        Folder(stack, model.Settings.Destination, path => model.Settings.Destination = path);
        stack.Children.Add(new TextBlock
        {
            Text = model.Text("只接入启动后新增或修改的图片。请将截图工具的自动保存目录设为接入文件夹；复制进去的普通图片也会被接入。仅在剪贴板中的截图不收集。移出托盘始终保留文件。\n\n落盘图片无法可靠提供来源屏幕，新截图在鼠标所在屏幕展开。",
                "Collects new or changed images after launch. Set Snipping Tool to automatically save into the input folder; other images copied there are also collected. Clipboard-only captures are excluded. Removing an item always keeps its file.\n\nSaved images do not reliably identify their source display. New captures open on the pointer's display."),
            TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 20, 0, 0), Foreground = Brushes.DimGray
        });
        error = new TextBlock { TextWrapping = TextWrapping.Wrap, Foreground = Brushes.DarkRed, Margin = new Thickness(0, 18, 0, 0) }; stack.Children.Add(error); UpdateError();
    }
    private void Folder(StackPanel stack, string path, Action<string> set)
    {
        var button = new Button { Content = path, Padding = new Thickness(8), HorizontalContentAlignment = HorizontalAlignment.Left };
        button.Click += (_, _) =>
        {
            using var picker = new Forms.FolderBrowserDialog { SelectedPath = path, UseDescriptionForTitle = true, Description = model.Text("选择文件夹", "Choose folder") };
            if (picker.ShowDialog() != Forms.DialogResult.OK) return;
            try { Directory.CreateDirectory(picker.SelectedPath); set(picker.SelectedPath); model.SavePreferences(); Render(); }
            catch (Exception ex) { model.Error(ex.Message); }
        };
        stack.Children.Add(button);
    }
    private void UpdateError() { if (error is not null) error.Text = model.LastError; }
}
