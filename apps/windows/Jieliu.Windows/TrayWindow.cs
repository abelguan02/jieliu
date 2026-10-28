using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Globalization;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Jieliu.Core;
using Forms = System.Windows.Forms;

namespace Jieliu.Windows;

internal sealed class TrayWindow : Window
{
    private readonly Model model;
    private readonly TraySurface surface;
    private readonly DispatcherTimer timer;
    private readonly DispatcherTimer motionTimer;
    private readonly Motion opening = new();
    private DateTime leaveAt = DateTime.UtcNow;
    private DateTime holdUntil;
    private bool expanded;
    private bool closed;
    public Forms.Screen Screen { get; }
    public TrayWindow(Model model, Forms.Screen screen, Action settings)
    {
        this.model = model; Screen = screen;
        WindowStyle = WindowStyle.None; ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true; Background = Brushes.Transparent;
        Topmost = true; ShowInTaskbar = false; ShowActivated = false;
        Width = 164; Height = 34;
        surface = new TraySurface(model, () => Expand(false), () => Collapse(), settings);
        motionTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
        motionTimer.Tick += (_, _) => ApplyFrame();
        Content = new Viewbox { Stretch = Stretch.Fill, Child = surface };
        SourceInitialized += (_, _) => Native.ToolWindow(this);
        MouseEnter += (_, _) => { leaveAt = DateTime.MaxValue; if (!expanded) Expand(false); };
        MouseLeave += (_, _) => leaveAt = DateTime.UtcNow;
        PreviewMouseDown += (_, _) => { Activate(); surface.Focus(); };
        timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(150) };
        timer.Tick += (_, _) =>
        {
            if (!expanded || surface.Dragging || surface.PreviewOpen || surface.MenuOpen || IsMouseOver) return;
            if ((model.Settings.AutoHide || model.Settings.MenuOnly) && DateTime.UtcNow > holdUntil && DateTime.UtcNow - leaveAt > TimeSpan.FromMilliseconds(650)) Collapse();
        };
        timer.Start();
        SystemParameters.StaticPropertyChanged += SystemMotionChanged;
        Closed += (_, _) =>
        {
            closed = true;
            SystemParameters.StaticPropertyChanged -= SystemMotionChanged;
            timer.Stop(); motionTimer.Stop(); surface.Dispose();
        };
    }
    private void SystemMotionChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is not (null or "" or nameof(SystemParameters.ClientAreaAnimation))) return;
        Dispatcher.BeginInvoke(() => { if (!closed) RefreshVisibility(); });
    }
    public void RefreshVisibility()
    {
        if (!surface.MotionEnabled) opening.Retarget(expanded ? 1 : 0, Motion.Now, 0);
        ApplyFrame();
    }
    private void ApplyFrame()
    {
        var now = Motion.Now;
        var progress = opening.Value(now);
        if (!opening.Running(now)) motionTimer.Stop();
        if (model.Settings.MenuOnly && !expanded && progress <= 0.00001) { surface.Reveal = 0; Hide(); return; }
        if (!IsVisible) Show();
        surface.Expanded = progress >= 0.99999;
        surface.Reveal = progress;
        surface.Width = 164 + 836 * progress;
        surface.Height = 34 + 168 * progress;
        Native.Position(this, Screen, surface.Width, surface.Height);
        surface.InvalidateVisual();
    }
    public void Expand(bool incoming)
    {
        holdUntil = DateTime.UtcNow.AddSeconds(incoming ? 4 : 1.5); leaveAt = DateTime.UtcNow;
        if (!expanded)
        {
            expanded = true;
            opening.Retarget(1, Motion.Now, surface.MotionEnabled ? 0.46 : 0);
            motionTimer.Start();
        }
        ApplyFrame();
    }
    public void Present(Capture capture) { Expand(true); surface.Arrive(capture); }
    private void Collapse()
    {
        if (!expanded) return;
        expanded = false;
        opening.Retarget(0, Motion.Now, surface.MotionEnabled ? 0.32 : 0);
        motionTimer.Start(); ApplyFrame();
    }
}

internal sealed partial class TraySurface : FrameworkElement, IDisposable
{
    private readonly Model model;
    private readonly Action expand, collapse, settings;
    private readonly List<(Capture Capture, Rect Rect, Geometry? Shape)> hits = [];
    private Point down;
    private bool pressed;
    private Guid? anchor;
    private PreviewWindow? preview;
    private ContextMenu? contextMenu;
    private Capture? selectOnRelease;
    private Guid? pressedCapture;
    private readonly Func<bool> systemAnimations;
    private readonly Func<double> clock;
    private double Now => clock();
    private readonly DispatcherTimer animationTimer;
    private readonly Dictionary<Guid, Rect> positions = [];
    private readonly Dictionary<Guid, Rect> origins = [];
    private readonly Dictionary<Guid, (Capture Capture, ImageSource? Image)> painted = [];
    private sealed record Ghost(Capture Capture, Rect Rect, ImageSource? Image, double Start, string Style, bool Evicted, LayerPose? Pose);
    private readonly List<Ghost> ghosts = [];
    private readonly Dictionary<Guid, LayerPose> layerPoses = [], layerOrigins = [];
    private readonly Motion spreadMotion = new();
    private bool spread;
    private double spreadLeave = double.PositiveInfinity;
    private string previousStyle;
    private readonly Dictionary<Guid, BufferArrival> bufferArrivals = [];
    private readonly Dictionary<Guid, BufferEviction> bufferEvictions = [];
    private double archivePulse;
    private readonly Dictionary<Guid, double> arrivals = [];
    private readonly List<(Capture Capture, Rect Rect)> incomingOverlay = [];
    private string layoutKey = "";
    private double layoutStart;
    private double reveal;
    private Guid? hovered;
    private readonly Dictionary<Guid, Motion> hoverMotion = [];
    public bool Expanded { get; set; }
    public double Reveal { get => reveal; set { reveal = value; UpdateAnimationTimer(); } }
    public bool MotionEnabled => model.Settings.Animations && systemAnimations();
    public bool Dragging { get; private set; }
    public bool PreviewOpen => preview?.IsVisible == true;
    public bool MenuOpen => contextMenu?.IsOpen == true;
    private static readonly Brush Muted = new SolidColorBrush(Color.FromRgb(125, 131, 141));
    private static readonly Brush Dim = new SolidColorBrush(Color.FromRgb(85, 90, 99));
    private static readonly Brush Tile = new SolidColorBrush(Color.FromRgb(10, 10, 11));
    private static readonly Typeface Mono = Fonts.Mono;

    public TraySurface(Model model, Action expand, Action collapse, Action settings, Func<bool>? systemAnimations = null, Func<double>? clock = null)
    {
        this.model = model; this.expand = expand; this.collapse = collapse; this.settings = settings;
        this.systemAnimations = systemAnimations ?? (() => SystemParameters.ClientAreaAnimation);
        this.clock = clock ?? (() => Motion.Now);
        previousStyle = model.Settings.Style;
        animationTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(25) };
        animationTimer.Tick += (_, _) => { UpdateAnimationTimer(); InvalidateVisual(); };
        IsVisibleChanged += (_, _) => UpdateAnimationTimer();
        MouseLeave += (_, _) => { Hover(null); spreadLeave = Now + .26; };
        MouseEnter += (_, _) => { spreadLeave = double.PositiveInfinity; SetSpread(true); };
        Focusable = true; FocusVisualStyle = null;
        model.Changed += Refresh;
        MouseLeftButtonDown += Down;
        MouseLeftButtonUp += (_, _) =>
        {
            var capture = selectOnRelease;
            CancelPress();
            if (capture is not null) Select(capture);
        };
        MouseMove += Move;
        KeyDown += Keys;
        MouseRightButtonUp += (_, _) => Menu();
        ToolTip = model.Text("截图来源屏幕不可用，自动在鼠标所在屏幕展开", "Source display unavailable; new captures open on the pointer's display");
    }
    private void Refresh()
    {
        var liveIds = model.History.Items.Select(c => c.Id).ToHashSet();
        // A burst can evict an arrival before its first frame populated positions.
        foreach (var id in arrivals.Keys.Where(id => !liveIds.Contains(id)).ToArray())
        { arrivals.Remove(id); bufferArrivals.Remove(id); }
        if (pressedCapture is { } downId && !liveIds.Contains(downId)) CancelPress();
        if (selectOnRelease is { } pending && !liveIds.Contains(pending.Id)) CancelPress();
        if (anchor is { } anchorId && !liveIds.Contains(anchorId)) anchor = null;
        if (hovered is { } hoverId && !liveIds.Contains(hoverId)) Hover(null);
        var key = model.Settings.Style + string.Join(",", model.History.Items.Select(c => c.Id));
        if (previousStyle != model.Settings.Style)
        {
            VisualDiagnostics.Event("style-change-cancel-motion", model.Settings.Style, arrivals.Count);
            arrivals.Clear(); bufferArrivals.Clear(); bufferEvictions.Clear(); ghosts.Clear();
            origins.Clear(); layerOrigins.Clear(); layerPoses.Clear(); positions.Clear(); painted.Clear();
            hoverMotion.Clear(); hovered = null; hits.Clear(); incomingOverlay.Clear(); CancelPress();
        }
        if (key != layoutKey)
        {
            hits.Clear();
            layoutStart = Now; layoutKey = key;
            origins.Clear(); foreach (var pair in positions) origins[pair.Key] = pair.Value;
            layerOrigins.Clear(); foreach (var pair in layerPoses) layerOrigins[pair.Key] = pair.Value;
            var live = model.History.Items.Select(c => c.Id).ToHashSet();
            if (MotionEnabled && Reveal > 0.5)
                foreach (var pair in painted.Where(p => !live.Contains(p.Key)))
                    if (positions.TryGetValue(pair.Key, out var rect)) ghosts.Add(new(pair.Value.Capture, rect, pair.Value.Image, layoutStart, previousStyle, model.LastChangeWasCapture, layerPoses.TryGetValue(pair.Key, out var pose) ? pose : null));
            foreach (var id in positions.Keys.Where(id => !live.Contains(id)).ToArray())
            { positions.Remove(id); painted.Remove(id); hoverMotion.Remove(id); arrivals.Remove(id); bufferArrivals.Remove(id); layerPoses.Remove(id); }
            previousStyle = model.Settings.Style;
        }
        UpdateAnimationTimer();
        ToolTip = model.Text("截图来源屏幕不可用，自动在鼠标所在屏幕展开", "Source display unavailable; new captures open on the pointer's display");
        InvalidateVisual();
    }
    public void Arrive(Capture capture)
    {
        VisualDiagnostics.Event("capture-presentation", model.Settings.Style, model.History.Items.Count);
        if (MotionEnabled) arrivals[capture.Id] = Now + (Reveal < 0.95 ? 0.2 : 0);
        UpdateAnimationTimer(); InvalidateVisual();
    }
    private void UpdateAnimationTimer()
    {
        if (IsMouseOver && Reveal > .05 && !Dragging) SetSpread(true);
        if (Reveal <= .001 || (!IsMouseOver && Now >= spreadLeave)) SetSpread(false);
        if (!MotionEnabled)
        {
            ghosts.Clear(); arrivals.Clear(); bufferArrivals.Clear(); bufferEvictions.Clear(); incomingOverlay.Clear();
            origins.Clear(); layerOrigins.Clear(); archivePulse = 0;
            spreadMotion.Retarget(spread ? 1 : 0, Now, 0);
            foreach (var pair in hoverMotion) pair.Value.Retarget(pair.Key == hovered ? 1 : 0, Now, 0);
        }
        if (IsVisible && Reveal > 0.001 && MotionEnabled) animationTimer.Start(); else animationTimer.Stop();
    }
    private void SetSpread(bool value)
    {
        if (spread == value) return;
        spread = value;
        spreadMotion.Retarget(value ? 1 : 0, Now, MotionEnabled ? .55 : 0, t => HtmlMotion.Bezier(t, .3, 1.2, .4, 1));
        InvalidateVisual();
    }
    private void Hover(Guid? id)
    {
        if (hovered == id) return;
        foreach (var pair in hoverMotion) pair.Value.Retarget(0, Now, MotionEnabled ? (model.Settings.Style == "C" ? .55 : .22) : 0,
            model.Settings.Style == "C" ? t => HtmlMotion.Bezier(t, .3, 1.2, .4, 1) : null);
        hovered = id;
        if (id is { } next)
        {
            if (!hoverMotion.TryGetValue(next, out var motion)) hoverMotion[next] = motion = new Motion();
            motion.Retarget(1, Now, MotionEnabled ? 0.55 : 0, t => HtmlMotion.Bezier(t, .3, 1.2, .4, 1));
        }
        InvalidateVisual();
    }
    private void Text(DrawingContext dc, string value, double x, double y, double size = 11, Brush? brush = null,
        TextAlignment alignment = TextAlignment.Left, double? maxWidth = null)
    {
        var text = new FormattedText(value, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, Mono, size,
            brush ?? Brushes.White, VisualTreeHelper.GetDpi(this).PixelsPerDip);
        if (maxWidth is { } width) { text.MaxTextWidth = width; text.MaxLineCount = 1; text.Trimming = TextTrimming.CharacterEllipsis; }
        x -= alignment == TextAlignment.Right ? text.Width : alignment == TextAlignment.Center ? text.Width / 2 : 0;
        if (maxWidth is { } clipWidth) dc.PushClip(new RectangleGeometry(new Rect(x, y, clipWidth, text.Height)));
        dc.DrawText(text, new Point(x, y));
        if (maxWidth is not null) dc.Pop();
    }
    protected override void OnRender(DrawingContext dc)
    {
        // Also enforce the policy on a render already queued before a system change.
        if (!MotionEnabled) UpdateAnimationTimer();
        using var diagnostic = VisualDiagnostics.Measure();
        hits.Clear();
        incomingOverlay.Clear();
        var p = Reveal;
        dc.PushClip(new RectangleGeometry(new Rect(0, 0, Width, Height)));
        Brush backdrop = Brushes.Black;
        if (model.Settings.Style == "C")
            backdrop = new LinearGradientBrush(new GradientStopCollection
            {
                new(Color.FromArgb((byte)(255 - 80 * p), 6, 7, 10), 0),
                new(Color.FromArgb((byte)(255 - 178 * p), 6, 7, 10), .6),
                new(Color.FromArgb((byte)(255 * (1 - p)), 6, 7, 10), 1)
            }, new Point(0, 0), new Point(0, 1));
        dc.DrawRoundedRectangle(backdrop, model.Settings.Style == "C" ? null : new Pen(Dim, .6), new Rect(0, 0, Width, Height), 17 + 8 * p, 17 + 8 * p);
        if (p < 0.65)
        {
            dc.PushOpacity(Math.Max(0, 1 - p / 0.65));
            dc.PushTransform(new TranslateTransform((Width - 164) / 2, 0));
            Corners(dc, new Rect(17, 10, 18, 13), Brushes.White);
            Text(dc, model.Text("截留", "JIELIU"), 48, 10, 11);
            Text(dc, model.History.Items.Count.ToString("00"), 126, 10, 11, Muted);
            dc.Pop(); dc.Pop();
        }
        if (p <= 0.001) { dc.Pop(); return; }
        dc.PushOpacity(Math.Clamp((p - 0.15) / 0.85, 0, 1));
        dc.PushTransform(new TranslateTransform((Width - 1000) / 2, -18 * (1 - p)));
        var style = model.Settings.Style;
        Text(dc, style switch { "A" => model.Text("截图标尺", "SCREENSHOT RULER"), "C" => model.Text("截图图层", "SCREENSHOT LAYERS"), _ => model.Text("截图缓冲区", "SCREENSHOT BUFFER") } + $" · {model.History.Items.Count}/8", 26, 12, 11, Muted);
        Text(dc, model.Text("设置", "SETTINGS") + "  ·  ×", 866, 12, 11, Muted);
        dc.DrawRoundedRectangle(Tile, new Pen(Dim, 0.5), new Rect(580, 7, 265, 22), 5, 5);
        if (MotionEnabled && archivePulse > Now)
            dc.DrawRoundedRectangle(null, new Pen(new SolidColorBrush(Color.FromArgb((byte)(180 * Math.Clamp((archivePulse - Now) / .32, 0, 1)), 255, 255, 255)), 1.5), new Rect(580, 7, 265, 22), 5, 5);
        Text(dc, model.Text("归档 → 截图文件夹", "FLUSH → Screenshots") + $"  {model.History.Total}", 590, 12, 10.5, Muted);
        var items = model.History.Items;
        if (style == "B")
        {
            for (var i = 0; i < History.Capacity; i++)
            {
                var capture = items.FirstOrDefault(c => c.Id == model.History.Slots[i]);
                var rect = new Rect(26 + i * 120, 42, 108, 68);
                Shot(dc, capture, rect);
                Text(dc, $"0x{i:X2}", rect.X, 121, 10.5);
                Text(dc, capture is not null && bufferArrivals.TryGetValue(capture.Id, out var transfer) ? transfer.Status(Now) : capture?.Created.ToString("HH:mm:ss") ?? "—", rect.Right, 121, 10, Muted, TextAlignment.Right);
                Text(dc, capture is null ? model.Text("空", "EMPTY") : $"{capture.Width}×{capture.Height}", rect.X, 139, 10.5, Dim);
                if (i == model.History.WritePointer)
                {
                    dc.PushOpacity(!MotionEnabled ? 1 : 0.4 + 0.6 * (0.5 + 0.5 * Math.Sin(Now * Math.PI * 2)));
                    dc.DrawRectangle(Brushes.OrangeRed, null, new Rect(rect.X, 115, 36, 2));
                    dc.DrawRectangle(Brushes.LimeGreen, null, new Rect(rect.X + 36, 115, 36, 2));
                    dc.DrawRectangle(Brushes.DodgerBlue, null, new Rect(rect.X + 72, 115, 36, 2));
                    dc.Pop();
                }
            }
        }
        else if (style == "A")
        {
            for (var tick = 0; tick <= 94; tick++)
            {
                var x = 26 + tick * 10;
                dc.DrawLine(new Pen(Dim, 0.7), new Point(x, 33), new Point(x, tick % 10 == 0 ? 44 : 38));
                if (tick % 10 == 0) Text(dc, (tick * 10).ToString(), x + 2, 38, 8, Dim);
            }
            for (var i = 0; i < items.Count; i++)
            {
                var rect = new Rect(26 + i * 120, 63, 108, 77);
                Shot(dc, items[i], rect);
                dc.DrawLine(new Pen(Dim, 0.6), new Point(rect.X, 45), new Point(rect.X, 150));
                Text(dc, $"{items[i].Width}×{items[i].Height}", rect.X, 151, 10.5, Muted, maxWidth: rect.Width);
            }
        }
        else
        {
            // Newest on top; hovered and flying layers are brought above the stack.
            foreach (var capture in items.AsEnumerable().Reverse().OrderBy(c => arrivals.ContainsKey(c.Id) ? 2 : hovered == c.Id ? 1 : 0)) DrawLayer(dc, capture);
            dc.PushOpacity(Math.Clamp((spreadMotion.Value(Now) - .5) / .5, 0, 1));
            foreach (var capture in items)
                if (!arrivals.ContainsKey(capture.Id) && layerPoses.ContainsKey(capture.Id))
                {
                    var caption = LayerCaptionRect(capture.Id);
                    if (caption.Width <= 12) continue;
                    dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(205, 12, 14, 18)), null, caption, 5, 5);
                    Text(dc, capture.Created.ToString("HH:mm:ss"), caption.X + 6, 164, 10, maxWidth: caption.Width - 12);
                }
            dc.Pop();
            if (spreadMotion.Value(Now) < .5) Text(dc, model.Text($"{items.Count} 个图层", $"{items.Count} LAYERS"), 500, 164, 11, Muted, TextAlignment.Center);
        }
        Text(dc, model.Text("拖出原图  ·  空格预览  ·  Delete 移出并保留文件", "DRAG ORIGINAL  ·  SPACE PREVIEW  ·  DELETE REMOVES FROM TRAY"), 26, 181, 10, Dim);
        if (!string.IsNullOrEmpty(model.LastError)) Text(dc, model.Text("! 设置中查看错误", "! SEE SETTINGS"), 830, 181, 10, Brushes.Orange);
        foreach (var incoming in incomingOverlay) Shot(dc, incoming.Capture, incoming.Rect, true);
        foreach (var ghost in ghosts.ToArray())
        {
            if (ghost.Style == "B")
            {
                var age = Now - ghost.Start;
                if (!ghost.Evicted) { ghosts.Remove(ghost); continue; }
                if (!bufferEvictions.TryGetValue(ghost.Capture.Id, out var effect) && ghost.Image is System.Windows.Media.Imaging.BitmapSource bitmap)
                {
                    try { bufferEvictions[ghost.Capture.Id] = effect = new(ghost.Capture, bitmap, ghost.Rect); }
                    catch (Exception ex) when (ex is NotSupportedException or ArgumentException or System.Runtime.InteropServices.COMException)
                    { VisualDiagnostics.Event("buffer-eviction-sampling-failed", "B", 0); model.Error(model.Text("移出粒子采样失败：", "Eviction sampling failed: ") + ex.Message); }
                }
                if (effect is null || age >= effect.End)
                { ghosts.Remove(ghost); bufferEvictions.Remove(ghost.Capture.Id); archivePulse = Now + .32; }
                else effect.Draw(dc, age);
                continue;
            }
            if (ghost.Style == "C" && ghost.Pose is { } pose)
            {
                var age = Now - ghost.Start;
                var duration = ghost.Evicted ? HtmlMotion.LayerEviction : HtmlMotion.LayerRemoval;
                var phase = Math.Clamp(age / duration, 0, 1);
                if (phase >= 1) { ghosts.Remove(ghost); if (ghost.Evicted) archivePulse = Now + .32; continue; }
                var qC = HtmlMotion.Bezier(phase, .55, 0, .2, 1);
                var final = pose with { X = 712, Y = 17, Scale = .15 };
                LayerDrawing.Draw(dc, ghost.Evicted ? LayerPose.Lerp(pose, final, qC) : pose, ghost.Image, false, Now, 1 - (ghost.Evicted ? qC : phase), MotionEnabled);
                continue;
            }
            var t = (Now - ghost.Start) / 0.42;
            if (t >= 1) { ghosts.Remove(ghost); continue; }
            var q = Motion.Ease(t);
            var rect = Blend(ghost.Rect, new Rect(720, 17, 8, 5), q);
            dc.PushOpacity(1 - q); dc.DrawRectangle(Tile, null, rect);
            if (ghost.Image is { } image) dc.DrawImage(image, rect);
            dc.Pop();
        }
        dc.Pop(); dc.Pop(); dc.Pop();
    }
    private Rect LayerCaptionRect(Guid id)
    {
        var pose = layerPoses[id];
        var gap = layerPoses.Where(p => p.Key != id).Select(p => Math.Abs(p.Value.X - pose.X)).DefaultIfEmpty(80).Min();
        var width = Math.Clamp(gap - 12, 0, 68);
        return new Rect(pose.X - width / 2, 160, width, 21);
    }
    private static Rect Blend(Rect a, Rect b, double t) => new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Width + (b.Width - a.Width) * t, a.Height + (b.Height - a.Height) * t);
    private void DrawLayer(DrawingContext dc, Capture capture)
    {
        var now = Now; var index = model.History.Items.IndexOf(capture);
        const double stageScale = 1000.0 / 1440;
        var fit = Math.Min(184.0 / capture.Width, 112.0 / capture.Height) * stageScale;
        var gap = (24 + 104 * spreadMotion.Value(now)) * stageScale;
        var target = new LayerPose(500 + (index - (model.History.Items.Count - 1) / 2.0) * gap, 108, capture.Width * fit, capture.Height * fit);
        if (MotionEnabled && layerOrigins.TryGetValue(capture.Id, out var origin) && now - layoutStart < .55)
            target = LayerPose.Lerp(origin, target, HtmlMotion.Bezier((now - layoutStart) / .55, .3, 1.2, .4, 1));
        var hovering = hoverMotion.TryGetValue(capture.Id, out var motion) && spread ? motion.Value(now) : 0;
        target = target with { RotateX = -16 * (1 - hovering), RotateY = -48 * (1 - hovering), Scale = 1 + .12 * hovering };
        var flying = false;
        if (MotionEnabled && arrivals.TryGetValue(capture.Id, out var start))
        {
            flying = now - start < HtmlMotion.LayerArrival;
            var source = target with { X = 500, Y = 112, RotateX = 0, RotateY = 0, Scale = Math.Min(240 / target.Width, 118 / target.Height) };
            target = HtmlMotion.Land(source, target, now - start);
            if (!flying) { arrivals.Remove(capture.Id); VisualDiagnostics.Event("layer-settled", "C", 1); }
        }
        var image = model.Image(capture);
        LayerDrawing.Draw(dc, target, image, model.Selection.Contains(capture.Id), now, 1, MotionEnabled);
        var shape = LayerDrawing.Shape(target);
        layerPoses[capture.Id] = target; positions[capture.Id] = shape.Bounds; painted[capture.Id] = (capture, image);
        if (Reveal > .15) hits.Add((capture, shape.Bounds, shape));
    }
    private Point ContentPoint(Point point) => new(point.X - (Width - 1000) / 2, point.Y + 18 * (1 - Reveal));
    private Capture? Hit(Point point)
    {
        if (Reveal <= .15 || !new Rect(0, 0, Width, Height).Contains(point)) return null;
        var content = ContentPoint(point);
        return hits.LastOrDefault(h => h.Shape?.FillContains(content) ?? h.Rect.Contains(content)).Capture;
    }
    private void Shot(DrawingContext dc, Capture? capture, Rect rect, bool overlay = false)
    {
        if (capture is not null && model.Settings.Style == "B" && MotionEnabled && arrivals.TryGetValue(capture.Id, out var startB))
        {
            if (!bufferArrivals.TryGetValue(capture.Id, out var buffer) && model.Image(capture) is { } bitmap)
            {
                try { bufferArrivals[capture.Id] = buffer = new(capture, bitmap, rect, startB); }
                catch (Exception ex) when (ex is NotSupportedException or ArgumentException or System.Runtime.InteropServices.COMException)
                {
                    VisualDiagnostics.Event("buffer-sampling-failed", "B", 0);
                    model.Error(model.Text("像素采样失败：", "Pixel sampling failed: ") + ex.Message);
                }
            }
            if (buffer is not null && Now < buffer.End)
            {
                if (overlay)
                {
                    var frameTime = Now;
                    buffer.Draw(dc, frameTime);
                    if (Reveal > .15)
                    {
                        var shape = buffer.HitGeometry(frameTime);
                        hits.Add((capture, shape.Bounds, shape));
                    }
                }
                else
                {
                    dc.DrawRoundedRectangle(Tile, new Pen(Dim, .6), rect, 4, 4);
                    if (model.Selection.Contains(capture.Id))
                    {
                        var border = rect; border.Inflate(4, 4);
                        dc.DrawRectangle(null, new Pen(Brushes.White, 1.2) { DashStyle = DashStyles.Dash }, border);
                        Corners(dc, border, Brushes.White);
                    }
                    if (Reveal > .15) hits.Add((capture, rect, null));
                    incomingOverlay.Add((capture, rect));
                }
                positions[capture.Id] = rect; painted[capture.Id] = (capture, model.Image(capture)); return;
            }
            arrivals.Remove(capture.Id); bufferArrivals.Remove(capture.Id);
            if (buffer is not null) VisualDiagnostics.Event("buffer-settled", "B", 1);
        }
        if (!overlay && capture is not null && MotionEnabled && arrivals.TryGetValue(capture.Id, out var began) && Now < began + 0.78)
        {
            dc.DrawRoundedRectangle(Tile, new Pen(Dim, 0.6), rect, 4, 4);
            incomingOverlay.Add((capture, rect)); return;
        }
        var arrival = 1.0;
        if (capture is not null)
        {
            if (MotionEnabled && origins.TryGetValue(capture.Id, out var origin)) rect = Blend(origin, rect, Motion.Ease((Now - layoutStart) / 0.42));
            if (MotionEnabled && arrivals.TryGetValue(capture.Id, out var start))
            {
                arrival = Math.Clamp((Now - start) / 0.78, 0, 1);
                // A visible miniature screenshot descends and settles into its slot.
                rect = Blend(new Rect(428, 30, 144, 90), rect, Motion.Ease(arrival));
                if (arrival >= 1) arrivals.Remove(capture.Id);
            }
            var hover = hoverMotion.TryGetValue(capture.Id, out var motion) ? motion.Value(Now) : 0;
            rect.Inflate(hover * 3, hover * 3);
            positions[capture.Id] = rect;
        }
        dc.PushOpacity(Math.Clamp(arrival * 4, 0, 1));
        dc.DrawRoundedRectangle(Tile, new Pen(Dim, 0.6) { DashStyle = capture is null ? DashStyles.Dash : DashStyles.Solid }, rect, 4, 4);
        if (capture is null) { dc.Pop(); return; }
        if (arrival < 1)
            dc.DrawRoundedRectangle(null, new Pen(new SolidColorBrush(Color.FromArgb((byte)(180 * (1 - arrival)), 70, 140, 255)), 2 + 4 * (1 - arrival)), rect, 4, 4);
        if (model.Image(capture) is { } image)
        {
            var scale = Math.Min(rect.Width / image.PixelWidth, rect.Height / image.PixelHeight);
            var w = image.PixelWidth * scale; var h = image.PixelHeight * scale;
            dc.DrawImage(image, new Rect(rect.X + (rect.Width - w) / 2, rect.Y + (rect.Height - h) / 2, w, h));
        }
        if (model.Selection.Contains(capture.Id))
        {
            var border = rect; border.Inflate(4, 4);
            dc.DrawRectangle(null, new Pen(Brushes.White, 1.2) { DashStyle = new DashStyle(new double[] { 4, 3 }, MotionEnabled ? -Now * 14 % 7 : 0) }, border);
            Corners(dc, border, Brushes.White);
        }
        painted[capture.Id] = (capture, model.Image(capture));
        dc.Pop();
        if (Reveal > .15 && arrival > 0) hits.Add((capture, rect, null));
    }
    private static void Corners(DrawingContext dc, Rect r, Brush color)
    {
        var p = new Pen(color, 1.7);
        foreach (var (x, dx) in new[] { (r.Left, 1), (r.Right, -1) })
            foreach (var (y, dy) in new[] { (r.Top, 1), (r.Bottom, -1) })
            {
                dc.DrawLine(p, new Point(x, y), new Point(x + 5 * dx, y));
                dc.DrawLine(p, new Point(x, y), new Point(x, y + 5 * dy));
            }
    }
    private List<Capture> Ordered() => model.Settings.Style == "B"
        ? model.History.Slots.Select(id => model.History.Items.FirstOrDefault(c => c.Id == id)).OfType<Capture>().ToList()
        : model.History.Items.ToList();
    private void Select(Capture capture)
    {
        var modifiers = Keyboard.Modifiers;
        if (SelectionRules.Apply(Ordered().Select(c => c.Id).ToArray(), model.Selection, capture.Id,
            ref anchor, modifiers.HasFlag(ModifierKeys.Shift), modifiers.HasFlag(ModifierKeys.Control))) model.Notify();
    }
    private void CancelPress()
    {
        pressed = false; pressedCapture = null; selectOnRelease = null;
    }
    private void Down(object sender, MouseButtonEventArgs e)
    {
        CancelPress(); Focus(); down = e.GetPosition(this);
        if (Reveal <= .15) { expand(); return; }
        var content = ContentPoint(down);
        var capture = Hit(down);
        if (!Expanded) expand();
        if (content.Y < 32 && content.X is > 580 and < 845)
        {
            try { Directory.CreateDirectory(model.Settings.Destination); Process.Start(new ProcessStartInfo(model.Settings.Destination) { UseShellExecute = true }); }
            catch (Exception ex) { model.Error(ex.Message); }
            return;
        }
        if (content.Y < 32 && content.X > 850) { if (content.X > 945) collapse(); else settings(); return; }
        if (capture is null) { model.Selection.Clear(); model.Notify(); return; }
        if (!model.Selection.Contains(capture.Id) || Keyboard.Modifiers != ModifierKeys.None) Select(capture);
        else selectOnRelease = capture;
        pressed = true; pressedCapture = capture.Id;
        if (e.ClickCount == 2) { CancelPress(); Preview(capture); }
    }
    private void Move(object sender, MouseEventArgs e)
    {
        if (!Dragging) Hover(Hit(e.GetPosition(this))?.Id);
        if (!pressed || e.LeftButton != MouseButtonState.Pressed) return;
        var delta = e.GetPosition(this) - down;
        if (Math.Abs(delta.X) < SystemParameters.MinimumHorizontalDragDistance && Math.Abs(delta.Y) < SystemParameters.MinimumVerticalDragDistance) return;
        CancelPress(); Dragging = true;
        try { var data = Data(); if (data is not null) DragDrop.DoDragDrop(this, data, DragDropEffects.Copy); }
        catch (Exception ex) { model.Error(ex.Message); }
        finally { Dragging = false; }
    }
    private DataObject? Data()
    {
        var items = Ordered().Where(c => model.Selection.Contains(c.Id) && File.Exists(c.Path)).ToList();
        if (items.Count == 0) return null;
        var data = new DataObject(); var paths = new StringCollection(); paths.AddRange(items.Select(c => c.Path).ToArray());
        data.SetFileDropList(paths);
        if (items.Count == 1)
        {
            data.SetImage(Model.LoadImage(items[0].Path));
            if (Path.GetExtension(items[0].Path).Equals(".png", StringComparison.OrdinalIgnoreCase)) data.SetData("PNG", new MemoryStream(File.ReadAllBytes(items[0].Path)));
        }
        return data;
    }
    private void Copy()
    {
        try { if (Data() is { } data) Clipboard.SetDataObject(data, true); }
        catch (Exception ex) { model.Error(ex.Message); }
    }
    private void Preview(Capture capture)
    {
        preview?.Close(); preview = new PreviewWindow(model, Ordered(), capture);
        preview.Show(); preview.Activate();
    }
    private void Keys(object sender, KeyEventArgs e)
    {
        if (Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
        {
            if (e.Key == Key.A) { model.Selection.UnionWith(model.History.Items.Select(c => c.Id)); model.Notify(); e.Handled = true; }
            if (e.Key == Key.C) { Copy(); e.Handled = true; }
            return;
        }
        switch (e.Key)
        {
            case Key.Delete: model.RemoveSelected(); break;
            case Key.Escape: collapse(); break;
            case Key.Space: if (Ordered().FirstOrDefault(c => model.Selection.Contains(c.Id)) is { } capture) Preview(capture); break;
            case Key.A: case Key.B: case Key.C: model.Settings.Style = e.Key.ToString(); model.SavePreferences(); break;
            case Key.Left: case Key.Right:
                var items = Ordered(); if (items.Count == 0) break;
                SelectionRules.Move(items.Select(c=>c.Id).ToArray(),model.Selection,ref anchor,e.Key==Key.Left ? -1 : 1,Keyboard.Modifiers.HasFlag(ModifierKeys.Shift));
                model.Notify(); break;
            default: return;
        }
        e.Handled = true;
    }
    private void Menu()
    {
        var menu = new ContextMenu(); contextMenu = menu;
        void Add(string zh, string en, Action action) { var item = new MenuItem { Header = model.Text(zh, en) }; item.Click += (_, _) => action(); menu.Items.Add(item); }
        Add("复制", "Copy", Copy);
        Add("预览", "Preview", () => { if (Ordered().FirstOrDefault(c => model.Selection.Contains(c.Id)) is { } c) Preview(c); });
        Add("移出托盘（保留文件）", "Remove from tray (keep file)", model.RemoveSelected);
        Add("设置…", "Settings…", settings); menu.IsOpen = true;
    }
    public void Dispose() { animationTimer.Stop(); model.Changed -= Refresh; preview?.Close(); if (contextMenu is not null) contextMenu.IsOpen = false; }
}
