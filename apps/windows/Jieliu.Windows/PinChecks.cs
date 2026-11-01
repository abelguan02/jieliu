using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Jieliu.Core;

namespace Jieliu.Windows;

internal sealed partial class TraySurface
{
    internal static void RunPinChecks()
    {
        static void Check(bool value, string reason) { if (!value) throw new Exception(reason); }
        var root = Path.Combine(Path.GetTempPath(), "jieliu-pins-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var model = new Model(root); model.Settings.Animations = false;
            var bitmap = BitmapSource.Create(40, 30, 96, 96, PixelFormats.Bgra32, null, Enumerable.Repeat((byte)255, 40 * 30 * 4).ToArray(), 160);
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using var encoded = new MemoryStream(); encoder.Save(encoded);
            var png = encoded.ToArray();
            var shots = Enumerable.Range(0, 9).Select(i =>
            {
                var path = Path.Combine(root, $"pin-{i}.png");
                File.WriteAllBytes(path, png);
                return new Capture(Guid.NewGuid(), path, DateTime.UnixEpoch.AddSeconds(i), 40, 30);
            }).ToArray();
            foreach (var capture in shots.Take(8)) model.Receive(capture);
            using var surface = new TraySurface(model, () => { }, () => { }, () => { }, () => false, () => 100)
                { Width = 1000, Height = 202, Expanded = true, Reveal = 1 };
            model.Selection.UnionWith(shots.Take(2).Select(c => c.Id));
            var menu = surface.CreateContextMenu(shots[0]);
            var pin = (MenuItem)menu.Items[0];
            Check(model.Selection.Count == 2 && (string)pin.Header == model.Text("固定", "Pin"), "Pin menu lost batch selection");
            pin.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
            Check(model.SelectionIsPinned && model.History.PinnedIds.Count == 2, "Pin menu action failed");
            model.Selection.Remove(shots[1].Id); pin.RaiseEvent(new RoutedEventArgs(MenuItem.ClickEvent));
            Check(model.SelectionIsPinned, "Pin menu changed meaning while open");
            surface.CreateContextMenu(shots[2]);
            Check(model.Selection.SetEquals(new[] { shots[2].Id }), "Context menu must target clicked capture");
            byte[] Frame() => VisualRenderChecks.Render(surface.OnRender);
            foreach (var style in new[] { "A", "B", "C" })
            {
                model.Settings.Style = style; model.SavePreferences(); surface.SetSpread(true);
                model.Selection.Clear(); model.Selection.Add(shots[7].Id); model.SetSelectedPins(false);
                var before = Frame(); model.SetSelectedPins(true);
                Check(!before.SequenceEqual(Frame()), "Missing pin badge for " + style);
                Check(new Model(root).History.PinnedIds.Contains(shots[7].Id), "Model did not persist pin");
                model.SetSelectedPins(false);
            }
            model.Selection.UnionWith(shots.Take(8).Select(c => c.Id)); model.SetSelectedPins(true);
            var arrivals = 0; var notices = 0;
            model.Received += _ => arrivals++;
            model.NoticeRaised += text => { notices++; surface.ShowNotice(text); };
            model.Receive(shots[8]);
            Check(arrivals == 0 && notices == 1 && surface.notice.Length > 0, "Full tray must notify without a capture animation");
            Check(model.History.Items.Count == 8 && model.History.Total == 8 && model.History.NextWriteSlot is null, "Full tray changed history");
            Check(File.Exists(shots[8].Path), "Full tray removed archived file");
            Frame();
            model.Selection.Clear(); model.Selection.Add(shots[0].Id); model.RemoveSelected();
            Check(File.Exists(shots[0].Path), "Explicit removal deleted pinned file");
            model.Receive(shots[8]);
            Check(arrivals == 1 && model.History.Slots[0] == shots[8].Id && model.History.PinnedIds.Count == 7, "Admission did not resume");
            Console.WriteLine("PASS: Windows Pin context action, batch selection, A/B/C badge, persistence and full-tray archive notice");
        }
        finally { Directory.Delete(root, true); }
    }
}
