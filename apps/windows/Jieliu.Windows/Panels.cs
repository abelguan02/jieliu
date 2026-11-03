using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Forms = System.Windows.Forms;

namespace Jieliu.Windows;

/// <summary>Shared pieces of the settings, about and onboarding windows.</summary>
internal static class Panels
{
    public const string Repository = "https://github.com/abelguan02/jieliu";
    public const string Feedback = Repository + "/issues/new";
    public static readonly Brush Accent = new SolidColorBrush(Color.FromRgb(0, 150, 200));
    public static string Version => typeof(Panels).Assembly.GetName().Version?.ToString(3) ?? "";

    public static void Open(Model model, string target)
    {
        try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); }
        catch (Exception ex) { model.Error(ex.Message); }
    }
    public static ImageSource AppIcon()
    {
        using var icon = TrayIcon.Create();
        var source = Imaging.CreateBitmapSourceFromHIcon(icon.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
        source.Freeze(); return source;
    }
    /// <summary>Optional images embedded from apps/macos/Resources; absent until the files are added.</summary>
    public static BitmapImage? Resource(string name)
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name);
        if (stream is null) return null;
        var image = new BitmapImage(); image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad;
        image.StreamSource = stream; image.EndInit(); image.Freeze(); return image;
    }
    public static TextBlock Heading(string text, double size = 13, double top = 18) =>
        new() { Text = text, FontSize = size, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, top, 0, 7) };
    public static TextBlock Dim(string text, double top = 4) =>
        new() { Text = text, Foreground = Brushes.DimGray, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, top, 0, 0) };
    public static TextBlock Link(string text, Action click)
    {
        var link = new System.Windows.Documents.Hyperlink(new System.Windows.Documents.Run(text));
        link.Click += (_, _) => click();
        return new TextBlock(link);
    }
    public static ComboBox Styles(Model model)
    {
        var style = new ComboBox { ItemsSource = new[] { model.Text("A · 标尺", "A · Ruler"), model.Text("B · 帧缓冲", "B · Buffer"), model.Text("C · 图层", "C · Layers") }, SelectedIndex = model.Settings.Style[0] - 'A' };
        style.SelectionChanged += (_, _) => { model.Settings.Style = ((char)('A' + style.SelectedIndex)).ToString(); model.SavePreferences(); };
        return style;
    }
    public static Button Folder(Model model, string path, Action<string> set, Action changed)
    {
        var button = new Button { Content = path, Padding = new Thickness(8), HorizontalContentAlignment = HorizontalAlignment.Left };
        button.Click += (_, _) =>
        {
            using var picker = new Forms.FolderBrowserDialog { SelectedPath = path, UseDescriptionForTitle = true, Description = model.Text("选择文件夹", "Choose folder") };
            if (picker.ShowDialog() != Forms.DialogResult.OK) return;
            try { Directory.CreateDirectory(picker.SelectedPath); set(picker.SelectedPath); model.SavePreferences(); changed(); }
            catch (Exception ex) { model.Error(ex.Message); }
        };
        return button;
    }
}
