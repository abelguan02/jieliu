using System;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Jieliu.Core;

namespace Jieliu.Windows;

internal sealed class PixelPalette
{
    public int Columns { get; }
    public int Rows { get; }
    public Brush[] Colors { get; }
    public PixelPalette(BitmapSource image, int width, int height)
    {
        (Columns, Rows) = HtmlMotion.Grid(width, height);
        var scaled = new TransformedBitmap(image, new ScaleTransform(Columns / (double)image.PixelWidth, Rows / (double)image.PixelHeight));
        var bitmap = new FormatConvertedBitmap(scaled, PixelFormats.Bgra32, null, 0);
        var stride = bitmap.PixelWidth * 4; var bytes = new byte[stride * bitmap.PixelHeight]; bitmap.CopyPixels(bytes, stride, 0);
        Colors = new Brush[Columns * Rows];
        for (var y = 0; y < Rows; y++) for (var x = 0; x < Columns; x++)
        {
            var offset = Math.Min(y, bitmap.PixelHeight - 1) * stride + Math.Min(x, bitmap.PixelWidth - 1) * 4;
            var color = new SolidColorBrush(Color.FromArgb(bytes[offset + 3], bytes[offset + 2], bytes[offset + 1], bytes[offset])); color.Freeze(); Colors[y * Columns + x] = color;
        }
    }
    public void Draw(DrawingContext dc, Rect rect, double rows = 1)
    {
        dc.PushClip(new RectangleGeometry(rect));
        for (var y = 0; y < Rows; y++) for (var x = 0; x < Columns; x++)
            if ((y + .5) / Rows <= rows) dc.DrawRectangle(Colors[y * Columns + x], null,
                new Rect(rect.X + x * rect.Width / Columns, rect.Y + y * rect.Height / Rows, rect.Width / Columns + .5, rect.Height / Rows + .5));
        dc.Pop();
    }
}

internal sealed class BufferArrival
{
    private readonly BitmapSource image;
    private readonly PixelPalette palette;
    private readonly Rect source, target;
    public PixelTransfer Plan { get; }
    public double Start { get; }
    private int phase = -1;
    public double End => Start + Plan.End;
    public string Status(double now) => now < Start + Plan.ReadEnd ? "READ" : "WRITE";
    public BufferArrival(Capture capture, BitmapSource image, Rect slot, double start)
    {
        this.image = image; Start = start; palette = new(image, capture.Width, capture.Height);
        target = Fit(capture.Width, capture.Height, slot);
        source = Fit(capture.Width, capture.Height, new Rect(380, 42, 240, 120));
        Plan = new(capture.Width, capture.Height, new(source.X, source.Y), new(source.Width, source.Height), new(target.X, target.Y), new(target.Width, target.Height), capture.Id.GetHashCode());
    }
    internal static Rect Fit(int width, int height, Rect box)
    {
        var scale = Math.Min(box.Width / width, box.Height / height); var w = width * scale; var h = height * scale;
        return new Rect(box.X + (box.Width - w) / 2, box.Y + (box.Height - h) / 2, w, h);
    }
    private static void Scan(DrawingContext dc, Rect rect, double progress)
    {
        var y = rect.Y + rect.Height * Math.Clamp(progress, 0, 1);
        dc.DrawRectangle(Brushes.OrangeRed, null, new Rect(rect.X, y - 4, rect.Width, 1.5));
        dc.DrawRectangle(Brushes.LimeGreen, null, new Rect(rect.X, y - 2.5, rect.Width, 1.5));
        dc.DrawRectangle(Brushes.DodgerBlue, null, new Rect(rect.X, y - 1, rect.Width, 1.5));
        dc.DrawRectangle(Brushes.White, null, new Rect(rect.X, y + .5, rect.Width, 1));
    }
    public void Draw(DrawingContext dc, double now)
    {
        var age = now - Start; if (age < 0) return;
        var nextPhase = age < PixelTransfer.ScanSeconds ? 0 : age < Plan.ReadEnd ? 1 : 2;
        if (phase != nextPhase) { phase = nextPhase; VisualDiagnostics.Event(new[] { "buffer-scan", "buffer-read", "buffer-write" }[phase], "B", Plan.Cells.Length); }
        if (age >= Plan.End) { dc.DrawImage(image, target); return; }
        if (age < PixelTransfer.ScanSeconds)
        {
            dc.DrawImage(image, source); palette.Draw(dc, source, age / PixelTransfer.ScanSeconds); Scan(dc, source, age / PixelTransfer.ScanSeconds); return;
        }
        if (age < Plan.ReadEnd)
        {
            foreach (var cell in Plan.Cells)
            {
                var t = age - PixelTransfer.ScanSeconds; var point = cell.At(t); var e = cell.Progress(t);
                var w = (source.Width + (target.Width - source.Width) * e) / Plan.Columns + .5;
                var h = (source.Height + (target.Height - source.Height) * e) / Plan.Rows + .5;
                dc.DrawRectangle(palette.Colors[cell.Row * Plan.Columns + cell.Column], null, new Rect(point.X, point.Y, w, h));
            }
            return;
        }
        var write = Math.Clamp((age - Plan.ReadEnd) / PixelTransfer.WriteSeconds, 0, 1);
        palette.Draw(dc, target);
        dc.PushClip(new RectangleGeometry(new Rect(target.X, target.Y, target.Width, target.Height * write)));
        dc.DrawImage(image, target); dc.Pop();
        if (write < 1) Scan(dc, target, write);
    }
}

internal sealed class BufferEviction
{
    private readonly PixelPalette palette;
    private readonly Rect from;
    private readonly (double Delay, double Duration)[] times;
    public double End { get; }
    public BufferEviction(Capture capture, BitmapSource image, Rect slot)
    {
        palette = new(image, capture.Width, capture.Height); from = BufferArrival.Fit(capture.Width, capture.Height, slot);
        var random = new Random(capture.Id.GetHashCode()); times = new (double, double)[palette.Columns * palette.Rows];
        for (var y = 0; y < palette.Rows; y++) for (var x = 0; x < palette.Columns; x++) times[y * palette.Columns + x] = ((1 - x / (double)palette.Columns) * .18 + random.NextDouble() * .14, .46 + random.NextDouble() * .2);
        End = times.Max(t => t.Delay + t.Duration);
    }
    public void Draw(DrawingContext dc, double age)
    {
        for (var y = 0; y < palette.Rows; y++) for (var x = 0; x < palette.Columns; x++)
        {
            var i = y * palette.Columns + x; var t = Math.Clamp((age - times[i].Delay) / times[i].Duration, 0, 1); if (t >= 1) continue;
            var e = t * t * (3 - 2 * t); var x0 = from.X + x * from.Width / palette.Columns; var y0 = from.Y + y * from.Height / palette.Rows;
            var size = Math.Max(1, from.Width / palette.Columns * (1 - e * .6));
            dc.PushOpacity(1 - e * .5); dc.DrawRectangle(palette.Colors[i], null,
                new Rect(x0 + (712 - x0) * e, y0 + (17 - y0) * e - Math.Sin(e * Math.PI) * 36, size, size)); dc.Pop();
        }
    }
}
