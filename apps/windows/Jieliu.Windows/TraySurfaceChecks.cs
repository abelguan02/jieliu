using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Jieliu.Core;

namespace Jieliu.Windows;

// Real surface state and drawing offscreen: no Window.Show or input injection.
internal sealed partial class TraySurface
{
    internal static void RunRegressionChecks()
    {
        static void Check(bool value, string reason) { if (!value) throw new Exception(reason); }
        var root = Path.Combine(Path.GetTempPath(), "jieliu-transitions-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var model = new Model(root);
            var pixels = Enumerable.Repeat((byte)255, 40 * 30 * 4).ToArray();
            var bitmap = BitmapSource.Create(40, 30, 96, 96, PixelFormats.Bgra32, null, pixels, 160);
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
            var time = 100.0; var systemEnabled = true; var sequence = 0;
            using var surface = new TraySurface(model, () => { }, () => { }, () => { }, () => systemEnabled, () => time)
                { Width = 1000, Height = 202, Expanded = true, Reveal = 1 };
            byte[] Frame() => VisualRenderChecks.Render(surface.OnRender);
            Capture Receive()
            {
                var path = Path.Combine(root, $"{sequence++}.png");
                using (var file = File.Create(path)) encoder.Save(file);
                var capture = new Capture(Guid.NewGuid(), path, DateTime.UnixEpoch.AddSeconds(sequence), 40, 30);
                model.Receive(capture); surface.Arrive(capture); return capture;
            }
            void ClearEffects(string reason)
            {
                Check(surface.arrivals.Count == 0 && surface.bufferArrivals.Count == 0 && surface.bufferEvictions.Count == 0 && surface.ghosts.Count == 0 && surface.incomingOverlay.Count == 0, reason);
            }
            model.Settings.Style = "C"; model.SavePreferences();
            Receive(); time += 3; Frame();
            var incoming = Receive(); Frame();
            Check(surface.Hit(new Point(500, 112))?.Id == incoming.Id, "C flying card click passed through to older card");
            while (model.History.Items.Count < 8) Receive();
            time += 3; Frame();
            var oldest = model.History.Items.Last(); var survivor = model.History.Items.First();
            model.Selection.UnionWith(new[] { oldest.Id, survivor.Id }); surface.anchor = survivor.Id;
            surface.pressed = true; surface.pressedCapture = oldest.Id; surface.selectOnRelease = oldest;
            Receive();
            Check(!surface.pressed && surface.pressedCapture is null && surface.selectOnRelease is null, "Eviction did not cancel pending mouse release/drag");
            surface.Select(oldest);
            Check(model.Selection.SetEquals(new[] { survivor.Id }), "Stale selection changed surviving selection");
            foreach (var style in new[] { "B", "C", "A", "B", "C" })
            {
                surface.pressed = true;
                surface.pressedCapture = model.History.Items.First().Id;
                surface.selectOnRelease = model.History.Items.First();
                systemEnabled = true; model.Settings.Animations = true;
                model.Settings.Style = style; model.SavePreferences();
                Check(!surface.pressed && surface.selectOnRelease is null, "Style switch retained pending release");
                ClearEffects("Style change retained effects");
                Frame(); Receive(); Frame(); time += .1; Frame();
                Check(surface.arrivals.Count > 0 && surface.ghosts.Count > 0, "Regression fixture has no active arrival/eviction");
                surface.Hover(model.History.Items.First().Id); time += .05;
                systemEnabled = false;
                // Reveal is updated by RefreshVisibility on the real system notification.
                surface.Reveal = surface.Reveal;
                var disabled = Frame(); ClearEffects("System animation disable retained effects");
                Check(!surface.animationTimer.IsEnabled && surface.archivePulse == 0, "Disabled motion still schedules animation");
                time += 3;
                Check(disabled.SequenceEqual(Frame()), "Disabled frame changed or retained a partial transition");
                systemEnabled = true; surface.Reveal = surface.Reveal; Frame();
                ClearEffects("Re-enable replayed cancelled effects");
                Receive(); Frame(); model.Settings.Animations = false; model.SavePreferences();
                Frame(); ClearEffects("App animation disable retained effects");
            }
            systemEnabled = true; model.Settings.Animations = true;
            for (var i = 0; i < 32; i++)
            {
                model.Settings.Style = new[] { "A", "B", "C" }[i % 3]; model.SavePreferences();
                Receive(); time += .03; Frame();
                Check(surface.hits.All(h => model.History.Items.Any(c => c.Id == h.Capture.Id)), "Burst left stale hit target");
            }
            time += 5; Frame(); Frame(); ClearEffects("Burst did not settle");
            for (var i = 0; i < 24; i++) Receive();
            Check(surface.arrivals.Count <= 8, "Unpainted evicted arrivals leaked during burst");
            time += 5; Frame(); Frame(); ClearEffects("Unpainted burst did not settle");
            model.Settings.Style = "B"; model.SavePreferences();
            var newest = Receive(); Frame();
            var transfer = surface.bufferArrivals[newest.Id];
            foreach (var age in new[] { .1, .6, transfer.Plan.ReadEnd + .2 })
            {
                time = transfer.Start + age; Frame();
                Point visible;
                if (age < PixelTransfer.ScanSeconds) visible = new Point(500, 102);
                else if (age < transfer.Plan.ReadEnd)
                {
                    var cell = transfer.Plan.Cells[0]; var point = cell.At(age - PixelTransfer.ScanSeconds);
                    visible = new Point(point.X + .1, point.Y + .1);
                }
                else
                {
                    var slot = Array.IndexOf(model.History.Slots, newest.Id);
                    visible = new Point(26 + slot * 120 + 54, 76);
                }
                Check(surface.Hit(visible)?.Id == newest.Id, "B visible scan/read/write image is not selectable");
            }
            surface.Select(newest); Frame();
            Check(model.Selection.Contains(newest.Id), "B animated target selection failed");
            time += 5; Frame();
            foreach (var style in new[] { "A", "B", "C" })
            {
                model.Settings.Style = style; model.SavePreferences();
                surface.Expanded = false;
                foreach (var reveal in new[] { .35, .65, .9 })
                {
                    surface.Reveal = reveal; surface.Width = 164 + 836 * reveal; surface.Height = 34 + 168 * reveal;
                    Frame();
                    var hit = surface.hits.First(h =>
                    {
                        var center = new Point(h.Rect.X + h.Rect.Width / 2 + (surface.Width - 1000) / 2,
                            h.Rect.Y + h.Rect.Height / 2 - 18 * (1 - reveal));
                        return new Rect(0, 0, surface.Width, surface.Height).Contains(center);
                    });
                    var point = new Point(hit.Rect.X + hit.Rect.Width / 2 + (surface.Width - 1000) / 2,
                        hit.Rect.Y + hit.Rect.Height / 2 - 18 * (1 - reveal));
                    Check(surface.Hit(point) is not null, "Visible image during expansion cannot be selected");
                    Check(surface.Hit(new Point(-1, point.Y)) is null, "Clipped image accepts invisible click");
                }
            }
            surface.Reveal = 0; Frame();
            Check(surface.Hit(new Point(50, 20)) is null, "Collapsed capsule selected a hidden image");
            Check(model.History.Items.Count == 8 && Directory.GetFiles(root, "*.png").Length == sequence, "Burst lost original files or exceeded capacity");
            surface.CheckAlignment();
            // Inspect the same in-memory payload used by copy and drag. Never call
            // Clipboard.SetDataObject or start a drag from the background runner.
            model.Selection.Clear();
            Check(surface.Data() is null, "Empty selection produced clipboard data");
            var selected = model.History.Items.Take(2).ToArray();
            model.Selection.Add(selected[0].Id);
            var single = surface.Data()!;
            Check(single.GetFileDropList().Count == 1 && single.GetFileDropList()[0] == selected[0].Path, "Single copy lost its original path");
            var original = single.GetImage();
            Check(original.PixelWidth == 40 && original.PixelHeight == 30, "Single copy lost original image dimensions");
            Check(single.GetData("PNG") is MemoryStream stream && stream.ToArray().SequenceEqual(File.ReadAllBytes(selected[0].Path)), "Single copy changed original PNG bytes");
            model.Selection.Add(selected[1].Id);
            var multiple = surface.Data()!;
            Check(multiple.GetFileDropList().Cast<string>().ToHashSet().SetEquals(selected.Select(c => c.Path)), "Multiple copy lost file paths");
            Check(!multiple.GetDataPresent(DataFormats.Bitmap, false) && !multiple.GetDataPresent("PNG", false), "Multiple copy unexpectedly supplied a single image");
            model.Selection.Clear(); model.Selection.Add(Guid.NewGuid());
            Check(surface.Data() is null, "Stale selection produced clipboard data");
            model.Selection.Clear(); model.Selection.Add(selected[0].Id);
            var held = selected[0].Path + ".held";
            File.Move(selected[0].Path, held);
            try { Check(surface.Data() is null, "Missing selected file produced clipboard data"); }
            finally { File.Move(held, selected[0].Path); }
            Console.WriteLine("PASS: empty/stale/missing copy selection, original PNG/bitmap single copy and file-list multiple copy without system clipboard access");
            Console.WriteLine("PASS: offscreen TraySurface eviction/selection, C flying hit, style switching, app/system motion cancellation, re-enable and burst");
        }
        finally { Directory.Delete(root, true); }
    }
}
