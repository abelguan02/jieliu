using System;
using System.Windows;
using System.Windows.Media;
using Jieliu.Core;

namespace Jieliu.Windows;

internal static class LayerDrawing
{
    private static readonly Brush Checker = MakeChecker();
    private static Brush MakeChecker()
    {
        var drawing = new DrawingGroup();
        using (var dc = drawing.Open())
        {
            dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(43, 45, 49)), null, new Rect(0, 0, 12, 12));
            var light = new SolidColorBrush(Color.FromRgb(65, 67, 71));
            dc.DrawRectangle(light, null, new Rect(0, 0, 6, 6)); dc.DrawRectangle(light, null, new Rect(6, 6, 6, 6));
        }
        var brush = new DrawingBrush(drawing) { Viewport = new Rect(0, 0, 12, 12), ViewportUnits = BrushMappingMode.Absolute, TileMode = TileMode.Tile, Stretch = Stretch.None };
        brush.Freeze(); return brush;
    }
    public static Matrix Matrix(LayerPose pose)
    {
        var origin = pose.Project(0, 0);
        return new Matrix(pose.A, pose.B, 0, pose.D, origin.X, origin.Y);
    }
    public static Geometry Shape(LayerPose pose)
    {
        var shape = new RectangleGeometry(new Rect(0, 0, pose.Width, pose.Height)) { Transform = new MatrixTransform(Matrix(pose)) };
        shape.Freeze(); return shape;
    }
    public static void Draw(DrawingContext dc, LayerPose pose, ImageSource? image, bool selected, double now, double opacity = 1, bool motion = true)
    {
        dc.PushOpacity(Math.Clamp(opacity, 0, 1));
        // Soft projected shadow, without per-frame bitmap rasterization.
        for (var i = 5; i >= 1; i--)
        {
            var shadow = Shape(pose with { Y = pose.Y + 5 + i * 1.8, Scale = pose.Scale * (1 + i * .012) });
            dc.DrawGeometry(new SolidColorBrush(Color.FromArgb(16, 0, 0, 0)), null, shadow);
        }
        dc.PushTransform(new MatrixTransform(Matrix(pose)));
        var rect = new Rect(0, 0, pose.Width, pose.Height);
        dc.DrawRectangle(Checker, null, rect);
        if (image is not null) dc.DrawImage(image, rect);
        dc.DrawRectangle(null, new Pen(new SolidColorBrush(Color.FromArgb(150, 255, 255, 255)), .8), rect);
        if (selected)
        {
            rect.Inflate(3, 3);
            dc.DrawRectangle(null, new Pen(Brushes.White, 1) { DashStyle = new DashStyle(new double[] { 4, 3 }, motion ? -now * 14 % 7 : 0) }, rect);
            foreach (var x in new[] { rect.Left, rect.Right }) foreach (var y in new[] { rect.Top, rect.Bottom })
                dc.DrawRectangle(Brushes.White, null, new Rect(x - 2, y - 2, 4, 4));
        }
        dc.Pop(); dc.Pop();
    }
}
