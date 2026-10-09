using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Jieliu.Core;
using Forms = System.Windows.Forms;

namespace Jieliu.Windows;

internal static class SelfChecks
{
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    private static void Check(bool condition, string reason) { if (!condition) throw new Exception(reason); }
    public static void Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "jieliu-gui-check-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var model = new Model(root);
            Check(!model.Settings.English && !model.Settings.MenuOnly && model.Settings.Style == "B", "Unexpected defaults");
            var pixels = new byte[64 * 32 * 4];
            for (var i = 0; i < pixels.Length; i += 4) { pixels[i] = 225; pixels[i + 1] = 120; pixels[i + 2] = 50; pixels[i + 3] = 255; }
            var fixture = BitmapSource.Create(64, 32, 96, 96, PixelFormats.Bgra32, null, pixels, 64 * 4);
            var path = Path.Combine(root, "fixture.png");
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(fixture));
            using (var file = File.Create(path)) encoder.Save(file);
            var capture = new Capture(Guid.NewGuid(), path, DateTime.Now, 64, 32);
            model.Receive(capture); model.Selection.Add(capture.Id);
            using (var surface = new TraySurface(model, () => { }, () => { }, () => { }) { Width = 1000, Height = 202, Expanded = true })
            {
                foreach (var style in new[] { "A", "B", "C" })
                {
                    model.Settings.Style = style;
                    surface.Measure(new Size(1000, 202)); surface.Arrange(new Rect(0, 0, 1000, 202)); surface.InvalidateVisual(); surface.UpdateLayout();
                    var output = new RenderTargetBitmap(1000, 202, 96, 96, PixelFormats.Pbgra32); output.Render(surface);
                    var bytes = new byte[1000 * 202 * 4]; output.CopyPixels(bytes, 4000, 0);
                    Check(Array.Exists(bytes, b => b != 0), "Empty render for " + style);
                }
            }
            model.Settings.English = true; model.Settings.MenuOnly = true; model.SavePreferences();
            var restored = new Model(root);
            Check(restored.Settings.English && restored.Settings.MenuOnly && restored.Settings.Style == "C", "Preferences did not persist independently");
            model.RemoveSelected(); Check(File.Exists(path) && model.History.Items.Count == 0, "Delete touched source file");
            var foreground = GetForegroundWindow();
            var panel = new TrayWindow(model, Forms.Screen.PrimaryScreen!, () => { });
            try
            {
                panel.RefreshVisibility(); Check(!panel.IsVisible, "Menu-only mode has an idle window");
                panel.Expand(true); Check(panel.IsVisible && GetForegroundWindow() == foreground, "Automatic panel steals focus");
            }
            finally { panel.Close(); }
            Console.WriteLine("PASS: WPF render A/B/C, default settings, persistence, deletion preserves file, hidden entry and nonactivating presentation");
        }
        finally { Directory.Delete(root, true); }
    }
}
