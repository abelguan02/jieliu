using System;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using Jieliu.Core;

namespace Jieliu.Windows;

internal sealed partial class TraySurface
{
    // Called only by --render-check, on its existing isolated model and offscreen surface.
    private void CheckAlignment()
    {
        static void Check(bool value, string reason) { if (!value) throw new Exception(reason); }
        Rect Ink(string value, double anchor, TextAlignment alignment, double? maxWidth = null)
        {
            var visual = new DrawingVisual();
            using (var dc = visual.RenderOpen()) Text(dc, value, anchor, 8, 10.5, alignment: alignment, maxWidth: maxWidth);
            return visual.Drawing.Bounds;
        }
        foreach (var value in new[] { "00:00:00", "READ", "WRITE", "读取", "写入", "—", "8 个图层", "8 LAYERS", "0 个图层", "0 LAYERS" })
        {
            var right = Ink(value, 200, TextAlignment.Right);
            var center = Ink(value, 500, TextAlignment.Center);
            Check(Math.Abs(right.Right - 200) < 2, "Localized glyphs lost their right anchor");
            Check(Math.Abs(center.X + center.Width / 2 - 500) < 2, "Localized glyphs lost their center anchor");
        }
        Check(Ink("16384×2160", 26, TextAlignment.Left, 60).Right <= 88, "A dimension text exceeds its column");
        var ids = model.History.Items.Select(c => c.Id).ToArray();
        foreach (var count in new[] { 1, 2, 8 })
        foreach (var gap in new[] { 16.67, 32, 60, 88.89 })
        {
            layerPoses.Clear();
            for (var i = 0; i < count; i++) layerPoses[ids[i]] = new LayerPose(500 + (i - (count - 1) / 2.0) * gap, 108, 120, 80);
            var boxes = ids.Take(count).Select(LayerCaptionRect).OrderBy(r => r.X).ToArray();
            for (var i = 1; i < boxes.Length; i++)
                Check(boxes[i].Left - boxes[i - 1].Right >= 11.99, "C captions overlap during spreading");
            Check(Math.Abs((boxes[0].Left + boxes[^1].Right) / 2 - 500) < .01, "C caption group is off center");
        }
        layerPoses.Clear();
        layerPoses[ids[0]] = new LayerPose(500, 108, 120, 80);
        layerPoses[ids[1]] = new LayerPose(500, 108, 120, 80);
        Check(LayerCaptionRect(ids[0]).Width == 0 && LayerCaptionRect(ids[1]).Width == 0, "C coincident moving layers retain overlapping captions");
        layerPoses.Clear();
        var saved = (model.Settings.English, model.Settings.Style, model.Settings.Animations, Reveal, Width, Height);
        try
        {
            model.Settings.Animations = false; Reveal = 1; Width = 1000; Height = 202;
            foreach (var english in new[] { false, true })
            {
                model.Settings.English = english;
                foreach (var style in new[] { "A", "B", "C" })
                {
                    model.Settings.Style = style; model.SavePreferences();
                    var visual = new DrawingVisual();
                    using (var dc = visual.RenderOpen()) OnRender(dc);
                    if (style != "B") continue;
                    var timestamps = 0;
                    void Visit(Drawing drawing)
                    {
                        if (drawing is DrawingGroup group) { foreach (var child in group.Children) Visit(child); }
                        if (drawing is not GlyphRunDrawing glyph || glyph.GlyphRun.Characters is not { } chars) return;
                        var label = new string(chars.ToArray());
                        if (label.Length != 8 || label[2] != ':' || label[5] != ':') return;
                        var slot = (int)Math.Round((glyph.Bounds.Right - 134) / 120);
                        Check(slot >= 0 && slot < 8 && Math.Abs(glyph.Bounds.Right - (134 + slot * 120)) < 2,
                            "B rendered timestamp is not aligned to its card's right edge");
                        timestamps++;
                    }
                    Visit(visual.Drawing);
                    Check(timestamps == model.History.Items.Count, "B glyph regression did not inspect all timestamps");
                }
            }
        }
        finally
        {
            model.Settings.English = saved.Item1; model.Settings.Style = saved.Item2; model.Settings.Animations = saved.Item3;
            Reveal = saved.Item4; Width = saved.Item5; Height = saved.Item6; model.SavePreferences();
        }
        Console.WriteLine("PASS: offscreen A bounded dimensions, bilingual text anchors, C transitional caption spacing and B rendered timestamp alignment");
    }
}
