using System.Collections.Concurrent;
using System.Reflection;
using Jieliu.Core;

static class WatcherSchedulingChecks
{
    public static async Task Run()
    {
        var failures = new List<string>();
        foreach (var (name, check) in new (string, Func<Task>)[]
        {
            ("idle directory", CheckIdle),
            ("pending-only retries", CheckPending),
            ("zero-byte delayed write", CheckEmpty),
            ("writer lock released without notification", CheckLocked)
        })
        {
            try { await check(); }
            catch (Exception ex) { failures.Add(name + ": " + ex.Message); }
        }
        if (failures.Count > 0) throw new Exception(string.Join(Environment.NewLine, failures));
        Console.WriteLine("PASS: idle watcher does not scan; one notification retries only pending files, including empty, incomplete and writer-locked images");
    }

    private static void Check(bool condition, string reason)
    {
        if (!condition) throw new Exception(reason);
    }

    private static async Task Until(Func<bool> condition, string reason)
    {
        var deadline = DateTime.UtcNow.AddSeconds(6);
        while (!condition() && DateTime.UtcNow < deadline) await Task.Delay(40);
        Check(condition(), reason);
    }

    private static string NewDirectory()
    {
        var root = Path.Combine(Path.GetTempPath(), "jieliu-scheduling-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        return root;
    }

    // Exercise the real scheduling and filesystem work with exactly controlled signals.
    // Starting then disabling native watchers can still deliver queued startup events.
    // Native notification delivery is covered by the other watcher checks.
    private static void StartWithoutNotifications(CaptureWatcher watcher)
    {
        var worker = (Task)typeof(CaptureWatcher)
            .GetMethod("Run", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(watcher, null)!;
        typeof(CaptureWatcher).GetField("worker", BindingFlags.Instance | BindingFlags.NonPublic)!
            .SetValue(watcher, worker);
    }

    private static void NotifyOnce(CaptureWatcher watcher) => typeof(CaptureWatcher)
        .GetMethod("Wake", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(watcher, null);

    private static async Task CheckIdle()
    {
        var root = NewDirectory();
        try
        {
            var captures = new ConcurrentQueue<Capture>();
            await using var watcher = new CaptureWatcher([root], root, _ => (640, 400));
            watcher.Captured += captures.Enqueue;
            StartWithoutNotifications(watcher);
            var unseen = Path.Combine(root, "unnotified.png");
            File.WriteAllText(unseen, "must await a notification");
            await Task.Delay(1800);
            Check(captures.IsEmpty, "An idle watcher discovered a file without a directory notification");
            NotifyOnce(watcher);
            await Until(() => captures.Count == 1, "One notification did not complete the stable-file retry");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task CheckPending()
    {
        var root = NewDirectory();
        try
        {
            var captures = new ConcurrentQueue<Capture>();
            var errors = new ConcurrentQueue<string>();
            var finishPending = 0;
            await using var watcher = new CaptureWatcher([root], root, path =>
            {
                // Finish the synthetic write after the worker's sharing probe has closed.
                // A wall-clock write can race that read handle on Windows. The changed
                // stamp still has to settle and be retried without another notification.
                if (Interlocked.Exchange(ref finishPending, 0) == 1) File.WriteAllText(path, "complete");
                return File.ReadAllText(path) == "partial"
                    ? throw new FormatException("Image write is incomplete") : (640, 400);
            });
            watcher.Captured += captures.Enqueue; watcher.Error += errors.Enqueue;
            StartWithoutNotifications(watcher);
            var pending = Path.Combine(root, "pending.png");
            File.WriteAllText(pending, "partial"); NotifyOnce(watcher);
            await Until(() => !errors.IsEmpty, "Incomplete file never reached a retry");
            Check(File.ReadAllText(pending) == "partial", "Incomplete source was changed or removed");
            var unseen = Path.Combine(root, "unnotified.png");
            File.WriteAllText(unseen, "not part of the pending set");
            await Task.Delay(1800);
            Check(captures.IsEmpty, "Retrying a pending image scanned and collected an unrelated unnotified file");
            Interlocked.Exchange(ref finishPending, 1);
            await Until(() => captures.Count == 1, "Completed pending file was not retried without another notification");
            Check(captures.Single().Path == pending, "Pending retry collected the wrong file");
            Check(errors.Count == 1, "An unchanged incomplete image repeatedly reported the same error");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task CheckEmpty()
    {
        var root = NewDirectory();
        try
        {
            var captures = new ConcurrentQueue<Capture>();
            await using var watcher = new CaptureWatcher([root], root, _ => (640, 400));
            watcher.Captured += captures.Enqueue;
            StartWithoutNotifications(watcher);
            var path = Path.Combine(root, "empty.png");
            File.WriteAllBytes(path, []); NotifyOnce(watcher);
            await Task.Delay(1200);
            Check(captures.IsEmpty && new FileInfo(path).Length == 0, "Empty source should remain untouched");
            File.WriteAllText(path, "now complete");
            await Until(() => captures.Count == 1, "An initially empty image was lost after its only notification");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task CheckLocked()
    {
        var root = NewDirectory();
        try
        {
            var captures = new ConcurrentQueue<Capture>();
            await using var watcher = new CaptureWatcher([root], root, _ => (640, 400));
            watcher.Captured += captures.Enqueue;
            StartWithoutNotifications(watcher);
            var path = Path.Combine(root, "locked.png");
            using (var writer = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                writer.Write("complete but held by writer"u8); writer.Flush(); NotifyOnce(watcher);
                await Task.Delay(1200);
                Check(captures.IsEmpty && File.Exists(path), "Writer-locked source was collected prematurely");
            }
            await Until(() => captures.Count == 1, "Releasing the writer lock without a notification did not retry the image");
        }
        finally { Directory.Delete(root, true); }
    }
}
