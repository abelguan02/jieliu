using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;

namespace Jieliu.Windows;

internal sealed class AboutWindow : Window
{
    private readonly Model model;
    private readonly Action guide;
    public AboutWindow(Model model, Action guide)
    {
        this.model = model; this.guide = guide;
        SizeToContent = SizeToContent.WidthAndHeight; ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        model.PreferencesChanged += Render;
        Closed += (_, _) => model.PreferencesChanged -= Render;
        Render();
    }
    private void Render()
    {
        Title = model.Text("关于截留", "About Jieliu");
        var stack = new StackPanel { Margin = new Thickness(28), Width = 380 };
        Content = stack;
        stack.Children.Add(new Image { Source = Panels.AppIcon(), Width = 56, Height = 56 });
        stack.Children.Add(new TextBlock { Text = model.Text("截留", "Jieliu"), FontSize = 22, FontWeight = FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 10, 0, 2) });
        stack.Children.Add(new TextBlock { Text = model.Text("版本 ", "Version ") + Panels.Version, FontFamily = new FontFamily("Consolas"), Foreground = Brushes.DimGray, HorizontalAlignment = HorizontalAlignment.Center });
        stack.Children.Add(Row(model.Text("开源仓库", "Source code"), "github.com/abelguan02/jieliu", Panels.Repository, 20));
        stack.Children.Add(Row(model.Text("反馈与建议", "Feedback"), "GitHub Issues", Panels.Feedback, 6));
        var support = Panels.Heading(model.Text("自愿打赏", "Support Jieliu"), 14, 22); support.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(support);
        var codes = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
        codes.Children.Add(Code("Jieliu.Donate.WeChat", model.Text("微信", "WeChat Pay")));
        codes.Children.Add(Code("Jieliu.Donate.Alipay", model.Text("支付宝", "Alipay")));
        stack.Children.Add(codes);
        var link = Panels.Link(model.Text("查看使用引导", "Show welcome guide"), guide);
        link.HorizontalAlignment = HorizontalAlignment.Center; link.Margin = new Thickness(0, 18, 0, 0);
        stack.Children.Add(link);
    }
    private Button Row(string title, string detail, string url, double top)
    {
        var row = new DockPanel();
        var right = new TextBlock { Text = detail + "  ↗", Foreground = Brushes.DimGray }; DockPanel.SetDock(right, Dock.Right);
        row.Children.Add(right); row.Children.Add(new TextBlock { Text = title });
        var button = new Button { Content = row, Padding = new Thickness(12, 9, 12, 9), Margin = new Thickness(0, top, 0, 0), HorizontalContentAlignment = HorizontalAlignment.Stretch };
        button.Click += (_, _) => Panels.Open(model, url);
        return button;
    }
    private static StackPanel Code(string resource, string title)
    {
        var panel = new StackPanel { Margin = new Thickness(12, 0, 12, 0) };
        if (Panels.Resource(resource) is { } image) panel.Children.Add(new Image { Source = image, Width = 140, Height = 140, Stretch = Stretch.Uniform });
        else panel.Children.Add(new Rectangle { Width = 140, Height = 140, RadiusX = 8, RadiusY = 8, Stroke = Brushes.Silver, StrokeDashArray = [4, 4] });
        panel.Children.Add(new TextBlock { Text = title, Foreground = Brushes.DimGray, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 8, 0, 0) });
        return panel;
    }
}
