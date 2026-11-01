using System;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Jieliu.Core;

namespace Jieliu.Windows;

// Offscreen WPF checks: no Window.Show, keyboard, mouse, clipboard or user files.
internal static class VisualRenderChecks
{
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    internal static byte[] Render(Action<DrawingContext> draw)
    {
        var visual = new DrawingVisual(); using (var dc = visual.RenderOpen()) draw(dc);
        var bitmap = new RenderTargetBitmap(1000, 202, 96, 96, PixelFormats.Pbgra32); bitmap.Render(visual);
        var result = new byte[1000 * 202 * 4]; bitmap.CopyPixels(result, 4000, 0); return result;
    }
    public static void Run()
    {
        LaunchAtLoginChecks.Run();
        ImageRegressionChecks.Run();
        TraySurface.RunPinChecks();
        var data = new byte[120 * 80 * 4];
        for (var y = 0; y < 80; y++) for (var x = 0; x < 120; x++)
        {
            var offset = (y * 120 + x) * 4; data[offset + (x < 60 ? 2 : 0)] = 255; data[offset + 3] = 255;
        }
        var image = BitmapSource.Create(120, 80, 96, 96, PixelFormats.Bgra32, null, data, 480); image.Freeze();
        var pose = new LayerPose(500, 108, 120, 80);
        var rendered = Render(dc => LayerDrawing.Draw(dc, pose, image, false, 0));
        foreach (var (x, channel) in new[] { (30, 2), (90, 0) })
        {
            var point = pose.Project(x, 40); var offset = ((int)point.Y * 1000 + (int)point.X) * 4;
            Check(rendered[offset + channel] > 240 && rendered[offset + 3] == 255, "WPF projected texture orientation is wrong");
        }
        var geometry = LayerDrawing.Shape(pose);
        for (var y = 40; y < 175; y += 7) for (var x = 420; x < 580; x += 7)
            Check(geometry.FillContains(new Point(x, y), .001, ToleranceType.Absolute) == pose.Contains(new(x, y)), "WPF hit region differs from projected card");
        var flat = pose with { RotateX = 0, RotateY = 0, Scale = 1.12 };
        Check(!rendered.SequenceEqual(Render(dc => LayerDrawing.Draw(dc, flat, image, false, 0))), "Hover frame is still tilted");
        var source = pose with { RotateX = 0, RotateY = 0, Scale = 1.5 };
        var lift = Render(dc => LayerDrawing.Draw(dc, HtmlMotion.Land(source, pose, .345), image, false, 0));
        Check(!lift.SequenceEqual(rendered), "C lift frame equals settled frame");
        var capture = new Capture(Guid.Parse("00000000-0000-0000-0000-000000000007"), "synthetic", DateTime.UnixEpoch, 120, 80);
        var slot = new Rect(26, 42, 108, 68);
        var arrival = new BufferArrival(capture, image, slot, 0);
        var scan = Render(dc => arrival.Draw(dc, .16));
        var flight = Render(dc => arrival.Draw(dc, .7));
        var write = Render(dc => arrival.Draw(dc, arrival.Plan.ReadEnd + .24));
        var settled = Render(dc => arrival.Draw(dc, arrival.End));
        Check(!scan.SequenceEqual(flight) && !flight.SequenceEqual(write) && !write.SequenceEqual(settled), "READ/WRITE phases did not change pixels");
        Check(settled.SequenceEqual(Render(dc => dc.DrawImage(image, BufferArrival.Fit(120, 80, slot)))), "Particle settling must restore the full image with no residue");
        var eviction = new BufferEviction(capture, image, slot);
        Check(Render(dc => eviction.Draw(dc, eviction.End)).All(b => b == 0), "Eviction particles did not terminate");
        Console.WriteLine("PASS: offscreen WPF C texture/hit geometry/hover/lift and B READ/WRITE/settling/eviction pixels");
        TraySurface.RunRegressionChecks();
    }
}
