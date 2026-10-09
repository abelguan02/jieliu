namespace Jieliu.Core;

/// <summary>Time-based, interruptible transition; no dependency on render frame rate.</summary>
public sealed class Motion
{
    private double from, to, started, duration;
    public static double Now => System.Diagnostics.Stopwatch.GetTimestamp() / (double)System.Diagnostics.Stopwatch.Frequency;
    public static double Ease(double progress) => 1 - Math.Pow(1 - Math.Clamp(progress, 0, 1), 3);
    public double Value(double now) => duration <= 0 ? to : from + (to - from) * Ease((now - started) / duration);
    public bool Running(double now) => duration > 0 && now < started + duration;
    public void Retarget(double target, double now, double seconds)
    {
        from = Value(now); to = target; started = now;
        duration = Math.Abs(to - from) < 0.00001 ? 0 : Math.Max(0, seconds);
    }
}
