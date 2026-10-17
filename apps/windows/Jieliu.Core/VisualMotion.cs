namespace Jieliu.Core;

public readonly record struct PlanePoint(double X, double Y)
{
    public static PlanePoint Lerp(PlanePoint a, PlanePoint b, double t) => new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t);
}

// concepts.html uses rotateX then rotateY, with no CSS perspective distance.
// Its flattened 3D matrix is affine; inventing a camera distance changes the original.
public readonly record struct LayerPose(double X, double Y, double Width, double Height, double RotateX = -16, double RotateY = -48, double Scale = 1)
{
    public double A => Math.Cos(RotateY * Math.PI / 180) * Scale;
    public double B => Math.Sin(RotateX * Math.PI / 180) * Math.Sin(RotateY * Math.PI / 180) * Scale;
    public double D => Math.Cos(RotateX * Math.PI / 180) * Scale;
    public PlanePoint Project(double x, double y) => new(X + A * (x - Width / 2), Y + B * (x - Width / 2) + D * (y - Height / 2));
    public bool Contains(PlanePoint point)
    {
        if (Math.Abs(A * D) < 0.000001) return false;
        var x = (point.X - X) / A;
        var y = (point.Y - Y - B * x) / D;
        return Math.Abs(x) <= Width / 2 && Math.Abs(y) <= Height / 2;
    }
    public static LayerPose Lerp(LayerPose a, LayerPose b, double t) => new(
        a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t,
        a.Width + (b.Width - a.Width) * t, a.Height + (b.Height - a.Height) * t,
        a.RotateX + (b.RotateX - a.RotateX) * t, a.RotateY + (b.RotateY - a.RotateY) * t, a.Scale + (b.Scale - a.Scale) * t);
}

public static class HtmlMotion
{
    public const double LayerArrival = 1.15, LayerEviction = 0.7, LayerRemoval = 0.22;
    public static double Bezier(double progress, double x1, double y1, double x2, double y2)
    {
        if (progress <= 0) return 0; if (progress >= 1) return 1;
        static double Axis(double t, double a, double b) => 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t;
        double low = 0, high = 1;
        for (var i = 0; i < 30; i++) { var mid = (low + high) / 2; if (Axis(mid, x1, x2) < progress) low = mid; else high = mid; }
        return Axis((low + high) / 2, y1, y2);
    }
    public static LayerPose Land(LayerPose source, LayerPose target, double seconds)
    {
        var p = seconds / LayerArrival;
        var lifted = source with { X = source.X - 10, Y = source.Y - 24, RotateX = 16, RotateY = -9, Scale = source.Scale * 1.035 };
        return p <= 0.3 ? LayerPose.Lerp(source, lifted, Bezier(p / 0.3, .3, 0, .2, 1))
            : LayerPose.Lerp(lifted, target, Bezier((p - .3) / .7, .5, 0, .15, 1));
    }
    public static (int Columns, int Rows) Grid(int width, int height)
    {
        var ratio = width / (double)Math.Max(1, height);
        return ratio >= 1 ? (24, Math.Clamp((int)Math.Floor(24 / ratio + .5), 2, 24))
            : (Math.Clamp((int)Math.Floor(18 * ratio + .5), 2, 18), 18);
    }
}

public readonly record struct PixelFlight(int Column, int Row, PlanePoint From, PlanePoint Control, PlanePoint To, double Delay, double Duration)
{
    public double Progress(double seconds)
    {
        var t = Math.Clamp((seconds - Delay) / Duration, 0, 1);
        return t < .5 ? 4 * t * t * t : 1 - Math.Pow(-2 * t + 2, 3) / 2;
    }
    public PlanePoint At(double seconds)
    {
        var e = Progress(seconds);
        var u = 1 - e;
        return new(u * u * From.X + 2 * u * e * Control.X + e * e * To.X, u * u * From.Y + 2 * u * e * Control.Y + e * e * To.Y);
    }
}

public sealed class PixelTransfer
{
    public const double ScanSeconds = .32, WriteSeconds = .48;
    public int Columns { get; }
    public int Rows { get; }
    public PixelFlight[] Cells { get; }
    public double ReadEnd { get; }
    public double End => ReadEnd + WriteSeconds;
    public PixelTransfer(int width, int height, PlanePoint source, PlanePoint sourceSize, PlanePoint target, PlanePoint targetSize, int seed)
    {
        (Columns, Rows) = HtmlMotion.Grid(width, height);
        var random = new Random(seed); var cells = new List<PixelFlight>();
        for (var y = 0; y < Rows; y++) for (var x = 0; x < Columns; x++)
        {
            var from = new PlanePoint(source.X + x * sourceSize.X / Columns, source.Y + y * sourceSize.Y / Rows);
            var to = new PlanePoint(target.X + x * targetSize.X / Columns, target.Y + y * targetSize.Y / Rows);
            var delay = y / (double)Rows * .28 + x / (double)Columns * .09 + random.NextDouble() * .12;
            var duration = .56 + random.NextDouble() * .18;
            var control = new PlanePoint((from.X + to.X) / 2 + (random.NextDouble() - .5) * 180,
                Math.Max(10, Math.Min(from.Y, to.Y) - 40 - random.NextDouble() * 140));
            cells.Add(new(x, y, from, control, to, delay, duration));
        }
        Cells = cells.ToArray(); ReadEnd = ScanSeconds + Cells.Max(p => p.Delay + p.Duration);
    }
}
