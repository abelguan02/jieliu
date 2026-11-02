using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using Jieliu.Core;

namespace Jieliu.Windows;

// Exercise the real controls and callbacks without showing a window or opening a picker.
internal static class OnboardingChecks
{
    public static void Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "jieliu-onboarding-" + Guid.NewGuid());
        try
        {
            foreach (var english in new[] { false, true })
            {
                var model = new Model(Path.Combine(root, english.ToString()));
                model.Settings.English = english;
                var starts = 0;
                var finished = false;
                var guide = new OnboardingWindow(model, () =>
                {
                    starts++;
                    model.Settings.Onboarded = true;
                    model.SavePreferences();
                    model.CaptureError(starts == 1 ? "Archive unavailable" : "");
                }, () => finished = true, page: 2);
                try
                {
                    Check(starts == 0 && model.Settings.Onboarded == false, "Setup started collection before consent");
                    Click(guide, model.Text("开始收纳", "Start collecting"));
                    Check(guide.Page == 3 && starts == 1 && Texts(guide).Contains("Archive unavailable"), "Trial did not display the startup error");
                    Check(Texts(guide).Contains(model.Text("截图收纳失败", "Could not collect the screenshot"))
                        && !Texts(guide).Contains(model.Text("截一张试试", "Take a screenshot")), "Trial startup failure still presents a waiting state");
                    Click(guide, model.Text("返回配置", "Back to setup"));
                    Check(guide.Page == 2, "Trial failure did not provide a way back to folder configuration");
                    Click(guide, model.Text("开始收纳", "Start collecting"));
                    Check(guide.Page == 3 && starts == 2 && !Texts(guide).Contains("Archive unavailable"), "Retry did not remove the recovered capture error");
                    model.Error("Settings save failure");
                    model.CaptureError("Image was incomplete");
                    model.Receive(new Capture(Guid.NewGuid(), Path.Combine(root, "recovered.png"), DateTime.Now, 640, 400));
                    Check(model.LastCaptureError == "" && model.LastError == "Settings save failure", "Capture recovery cleared an unrelated persistence error");
                    Check(Texts(guide).Contains(model.Text("已收进顶部托盘", "Collected in the tray")), "Successful capture did not finish the trial state");
                    var longError = string.Join("\n", Enumerable.Repeat(model.Text("无法访问保存文件夹，请检查文件夹权限。", "Cannot access the archive folder. Check the folder permissions."), 24));
                    model.CaptureError(longError);
                    Check(Texts(guide).Contains(model.Text("截图收纳失败", "Could not collect the screenshot"))
                        && !Texts(guide).Contains(model.Text("已收进顶部托盘", "Collected in the tray")), "A later capture failure is hidden behind the earlier success state");
                    Check(!Elements(guide).OfType<Button>().Any(button => button.Content as string == model.Text("完成", "Done")), "Failed trial still offers Done");
                    Check(Elements(guide).OfType<Button>().Any(button => button.Content as string == model.Text("跳过", "Skip")), "Failed trial does not offer Skip");
                    var content = (FrameworkElement)guide.Content;
                    content.Measure(new Size(524, 401)); content.Arrange(new Rect(0, 0, 524, 401)); content.UpdateLayout();
                    var errorArea = Elements(guide).OfType<ScrollViewer>().Single();
                    Check(content.DesiredSize.Height <= 401 && errorArea.ActualHeight <= 94 && errorArea.ScrollableHeight > 0,
                        "Long capture error is clipped instead of scrolling within the onboarding window");
                    foreach (var button in Elements(guide).OfType<Button>())
                    {
                        var origin = button.TranslatePoint(new Point(), content);
                        Check(origin.Y >= 0 && origin.Y + button.ActualHeight <= 401, "Long capture error pushes recovery buttons outside the window");
                    }
                    model.CaptureError("");
                    Click(guide, model.Text("完成", "Done"));
                    Check(finished, "Done did not invoke the finish action");
                }
                finally { guide.Close(); }
            }
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        Console.WriteLine("PASS: onboarding error priority before/after success, long-error scrolling, real Back/Start/Done buttons and error recovery (offscreen)");
    }

    private static IEnumerable<DependencyObject> Elements(DependencyObject root)
    {
        yield return root;
        foreach (var child in LogicalTreeHelper.GetChildren(root).OfType<DependencyObject>())
            foreach (var element in Elements(child)) yield return element;
    }
    private static string[] Texts(Window window) => Elements(window).OfType<TextBlock>().Select(text => text.Text).ToArray();
    private static void Click(Window window, string label) => Elements(window).OfType<Button>()
        .Single(button => button.Content as string == label).RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
    private static void Check(bool condition, string reason)
    {
        if (!condition) throw new Exception(reason);
    }
}
