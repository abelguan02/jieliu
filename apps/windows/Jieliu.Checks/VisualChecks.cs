using Jieliu.Core;

static class VisualChecks
{
    static void Require(bool valid, string reason) { if (!valid) throw new Exception(reason); }
    static bool Close(double a, double b) => Math.Abs(a - b) < 0.00001;
    public static void Run()
    {
        var layer = new LayerPose(500, 108, 184, 112);
        var corner = layer.Project(0, 0);
        Require(Close(corner.X, 500 - 92 * Math.Cos(48 * Math.PI / 180)), "CSS rotateY projected width mismatch");
        Require(Close(corner.Y, 108 - 92 * Math.Sin(16 * Math.PI / 180) * Math.Sin(48 * Math.PI / 180) - 56 * Math.Cos(16 * Math.PI / 180)), "CSS rotate order mismatch");
        Require(layer.Contains(new(500, 108)) && layer.Contains(layer.Project(50, 30)), "Projected image interior must be clickable");
        Require(!layer.Contains(new(corner.X + 1, 108 + 56)), "Empty bounding-box corner must not steal clicks");
        var hover = layer with { RotateX = 0, RotateY = 0, Scale = 1.12 };
        Require(Close(hover.Project(184, 112).X - hover.Project(0, 0).X, 184 * 1.12), "HTML hover must flatten and scale to 1.12");
        var source = layer with { X = 490, Y = 120, RotateX = 0, RotateY = 0, Scale = 2 };
        Require(HtmlMotion.Land(source, layer, 0) == source, "C start pose must match source");
        var lifted = HtmlMotion.Land(source, layer, .345);
        Require(Close(lifted.RotateX, 16) && Close(lifted.RotateY, -9) && Close(lifted.Scale, 2.07), "C 30% lift keyframe differs from HTML");
        Require(HtmlMotion.Land(source, layer, 1.15) == layer && HtmlMotion.Land(source, layer, 10) == layer, "C must settle without extrapolation");
        Require(HtmlMotion.Grid(1000, 1000) == (24, 24) && HtmlMotion.Grid(1, 4000) == (2, 18), "HTML mosaic cell bounds mismatch");
        var pixels = new PixelTransfer(1600, 900, new(380, 40), new(240, 135), new(26, 42), new(108, 60.75), 7);
        Require(pixels.Cells.Length <= 576 && pixels.Cells.Length == pixels.Columns * pixels.Rows, "Particle work must stay bounded");
        foreach (var cell in pixels.Cells)
        {
            Require(cell.At(-1) == cell.From, "Particle must wait for its own delay");
            Require(cell.At(pixels.ReadEnd) == cell.To, "Particle endpoint must match target cell");
            var mid = cell.At(cell.Delay + cell.Duration / 2);
            Require(double.IsFinite(mid.X) && double.IsFinite(mid.Y), "Invalid particle trajectory");
        }
        Require(pixels.ReadEnd > .32 && Close(pixels.End - pixels.ReadEnd, .48), "READ must finish before 480ms WRITE");
        Console.WriteLine("PASS: HTML C projection/hit-test/keyframes and B bounded particle trajectories/phase timing");
    }
}
