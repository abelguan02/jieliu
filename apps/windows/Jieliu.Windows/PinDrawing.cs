using System;
using System.Windows;
using System.Windows.Media;

namespace Jieliu.Windows;

internal static class PinDrawing
{
    private static readonly Geometry Shape = Geometry.Parse("M5,3 L13,3 12,8 15,11 10,11 10,15 8,17 8,11 3,11 6,8 Z");
    public static void Draw(DrawingContext dc, Rect rect)
    {
        var size = Math.Min(18, Math.Min(rect.Width, rect.Height));
        dc.PushTransform(new TranslateTransform(rect.X, rect.Y));
        dc.PushTransform(new ScaleTransform(size / 18, size / 18));
        dc.DrawRoundedRectangle(Brushes.Black, new Pen(new SolidColorBrush(Color.FromArgb(90, 255, 255, 255)), 1), new Rect(0, 0, 18, 18), 3, 3);
        dc.DrawGeometry(Brushes.White, null, Shape);
        dc.Pop(); dc.Pop();
    }
}
