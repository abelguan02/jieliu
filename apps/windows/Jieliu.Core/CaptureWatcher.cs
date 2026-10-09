namespace Jieliu.Core;

public readonly record struct FileStamp(long Length, long Modified, long Created)
{
    public static FileStamp? Read(string path)
    {
        try
        {
            var file = new FileInfo(path);
            return file.Exists && !file.Attributes.HasFlag(FileAttributes.ReparsePoint)
                ? new(file.Length, file.LastWriteTimeUtc.Ticks, file.CreationTimeUtc.Ticks) : null;
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }
}

public static class Archive
{
    public static string Move(string source, string destination)
    {
        Directory.CreateDirectory(destination);
        if (History.SamePath(System.IO.Path.GetDirectoryName(source)!, destination)) return source;
        var target = System.IO.Path.Combine(destination, System.IO.Path.GetFileName(source));
        if (File.Exists(target)) target = System.IO.Path.Combine(destination,
            System.IO.Path.GetFileNameWithoutExtension(source) + "-" + Guid.NewGuid().ToString("N") + System.IO.Path.GetExtension(source));
        File.Move(source, target); // Never replace a destination or delete a failed source.
        return target;
    }
}

/// <summary>Only explicitly configured screenshot folders are observed; no filename heuristic or clipboard collection.</summary>
public sealed class CaptureWatcher : IAsyncDisposable
{
    private readonly string[] directories;
    private readonly string destination;
    private readonly Func<string, (int Width, int Height)> dimensions;
    private readonly Dictionary<string, FileStamp> known = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, FileStamp> pending = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> reported = [];
    private readonly CancellationTokenSource cancel = new();
    private readonly SemaphoreSlim signal = new(0, 1);
    private readonly List<FileSystemWatcher> watchers = [];
    private readonly System.Collections.Concurrent.ConcurrentQueue<(string Old, string New)> renames = new();
    private Task? worker;
    public event Action<Capture>? Captured;
    public event Action<string>? Error;

    public CaptureWatcher(IEnumerable<string> sources, string destination, Func<string, (int, int)> dimensions)
    {
        this.destination = System.IO.Path.GetFullPath(destination);
        directories = sources.Append(destination).Select(System.IO.Path.GetFullPath).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        this.dimensions = dimensions;
    }

    public void Start()
    {
        if (worker is not null) throw new InvalidOperationException("Watcher already started");
        // Baseline is synchronous: files arriving after Start returns are never treated as old.
        foreach (var directory in directories)
        {
            try
            {
                Directory.CreateDirectory(directory);
                var watcher = new FileSystemWatcher(directory) { NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size };
                FileSystemEventHandler changed = (_, _) => Wake();
                watcher.Created += changed; watcher.Changed += changed; watcher.Deleted += changed;
                watcher.Renamed += (_, e) => { renames.Enqueue((e.OldFullPath, e.FullPath)); Wake(); };
                watcher.Error += (_, _) => Wake();
                watcher.EnableRaisingEvents = true; watchers.Add(watcher);
                foreach (var path in Directory.GetFiles(directory)) if (FileStamp.Read(path) is { } stamp) known[path] = stamp;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { Report(ex.Message); }
        }
        worker = Task.Run(Run);
    }

    private void Wake() { try { signal.Release(); } catch (SemaphoreFullException) { } }
    private void Report(string message) { if (reported.Add(message)) Error?.Invoke(message); }

    private async Task Run()
    {
        try
        {
            while (!cancel.IsCancellationRequested)
            {
                await signal.WaitAsync(TimeSpan.FromMilliseconds(450), cancel.Token);
                // Always wait one interval between observations, including event bursts.
                await Task.Delay(180, cancel.Token);
                while (renames.TryDequeue(out var rename))
                {
                    if (known.TryGetValue(rename.Old, out var stamp) && FileStamp.Read(rename.New) == stamp)
                    { known[rename.New] = stamp; known.Remove(rename.Old); }
                    pending.Remove(rename.Old);
                }
                foreach (var directory in directories)
                {
                    try
                    {
                        var paths = Directory.GetFiles(directory);
                        var present = paths.ToHashSet(StringComparer.OrdinalIgnoreCase);
                        foreach (var stale in pending.Keys.Where(p => History.SamePath(System.IO.Path.GetDirectoryName(p)!, directory) && !present.Contains(p)).ToArray()) pending.Remove(stale);
                        foreach (var path in paths.OrderBy(p => FileStamp.Read(p)?.Created)) Process(path);
                        foreach (var stale in known.Keys.Where(p => History.SamePath(System.IO.Path.GetDirectoryName(p)!, directory) && !present.Contains(p)).ToArray()) known.Remove(stale);
                    }
                    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { Report(ex.Message); }
                }
            }
        }
        catch (OperationCanceledException) when (cancel.IsCancellationRequested) { }
    }

    private void Process(string path)
    {
        if (!new[] { ".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff" }.Contains(System.IO.Path.GetExtension(path).ToLowerInvariant())) return;
        if (FileStamp.Read(path) is not { } stamp || stamp.Length == 0 || known.GetValueOrDefault(path) == stamp) return;
        // Directory notifications can arrive after a polling scan. Preserve rename
        // suppression even when the old name disappeared before the event arrived.
        if (known.Any(entry => entry.Value == stamp && !File.Exists(entry.Key)))
        { known[path] = stamp; pending.Remove(path); return; }
        if (!pending.TryGetValue(path, out var previous) || previous != stamp) { pending[path] = stamp; return; }
        try
        {
            // Reject files held by a writer; decoding must finish before archiving.
            using (File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read)) { }
            var (width, height) = dimensions(path);
            if (width <= 0 || height <= 0 || FileStamp.Read(path) != stamp) return;
            var archived = Archive.Move(path, destination);
            known[path] = stamp;
            if (FileStamp.Read(archived) is { } moved) known[archived] = moved;
            pending.Remove(path);
            Captured?.Invoke(new(Guid.NewGuid(), archived, new DateTime(stamp.Created, DateTimeKind.Utc).ToLocalTime(), width, height));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException or System.Runtime.InteropServices.COMException)
        { Report(ex.Message); }
    }

    public async ValueTask DisposeAsync()
    {
        foreach (var watcher in watchers) watcher.Dispose();
        await cancel.CancelAsync();
        if (worker is not null) await worker;
        signal.Dispose(); cancel.Dispose();
    }
}
