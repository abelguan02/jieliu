using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows;
using System.Windows.Media;
using Jieliu.Core;

namespace Jieliu.Windows;

internal static class VisualDiagnostics
{
    private static long frames;
    private static double totalMs, maxMs;
    private static readonly Queue<object> events = new();
    public static IDisposable Measure() => new Sample();
    private sealed class Sample : IDisposable
    {
        private readonly long start = Stopwatch.GetTimestamp();
        public void Dispose()
        {
            var ms = Stopwatch.GetElapsedTime(start).TotalMilliseconds;
            frames++; totalMs += ms; maxMs = Math.Max(maxMs, ms);
        }
    }
    public static void Event(string phase, string style, int count)
    {
        events.Enqueue(new { timeUtc = DateTime.UtcNow, phase, style, count });
        while (events.Count > 32) events.Dequeue();
    }
    public static void Save(string path, Model model) => JsonStore.Save(path, new
    {
        version = typeof(VisualDiagnostics).Assembly.GetName().Version?.ToString(3),
        os = Environment.OSVersion.VersionString, runtime = Environment.Version.ToString(),
        graphicsTier = RenderCapability.Tier >> 16,
        systemAnimation = SystemParameters.ClientAreaAnimation, appAnimation = model.Settings.Animations,
        style = model.Settings.Style, menuOnly = model.Settings.MenuOnly, historyCount = model.History.Items.Count,
        frames, cpuDrawMeanMs = frames == 0 ? 0 : totalMs / frames, cpuDrawMaxMs = maxMs,
        hasReportedError = !string.IsNullOrEmpty(model.LastError), events = events.ToArray(),
        note = "CPU drawing samples, not monitor FPS. No screenshot pixels, names, paths or credentials included."
    });
}
