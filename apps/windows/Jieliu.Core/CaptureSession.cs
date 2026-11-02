namespace Jieliu.Core;

/// <summary>Owns the active folder watcher and serializes settings changes with shutdown.</summary>
public sealed class CaptureSession(Func<string, (int Width, int Height)> dimensions) : IAsyncDisposable
{
    private readonly SemaphoreSlim change = new(1, 1);
    private CaptureWatcher? watcher;
    private string watchedSource = "", watchedDestination = "";
    private bool stopped;
    public event Action<Capture>? Captured;
    public event Action<string>? Error;

    public async Task<bool> RestartAsync(bool enabled, string source, string destination)
    {
        await change.WaitAsync();
        try
        {
            if (stopped || !enabled || (watcher is not null && watchedSource == source && watchedDestination == destination)) return false;
            var previous = watcher;
            watcher = null;
            if (previous is not null) await previous.DisposeAsync();
            var next = new CaptureWatcher([source], destination, dimensions);
            next.Captured += capture => Captured?.Invoke(capture);
            next.Error += error => Error?.Invoke(error);
            try { next.Start(); }
            catch { await next.DisposeAsync(); throw; }
            watcher = next;
            watchedSource = source; watchedDestination = destination;
            return true;
        }
        finally { change.Release(); }
    }

    public async ValueTask DisposeAsync()
    {
        stopped = true;
        await change.WaitAsync();
        try
        {
            var previous = watcher;
            watcher = null;
            if (previous is not null) await previous.DisposeAsync();
        }
        finally { change.Release(); }
    }
}
