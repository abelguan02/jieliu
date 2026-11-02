using System.Collections.Concurrent;
using Jieliu.Core;

static class WatcherStartupChecks
{
    public static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "jieliu-startup-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        var input = Path.Combine(root, "input");
        var archive = Path.Combine(root, "archive");
        Directory.CreateDirectory(input);
        File.WriteAllText(archive, "temporarily blocks archive directory");
        try
        {
            await using var watcher = new CaptureWatcher([input], archive, _ => (640, 400));
            var failed = false;
            try { watcher.Start(); }
            catch (IOException) { failed = true; }
            Check(failed, "Failed directory initialization was reported as a running watcher");
            var active = (System.Collections.ICollection)typeof(CaptureWatcher)
                .GetField("watchers", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(watcher)!;
            Check(active.Count == 0, "Partially initialized directory watchers were retained after startup failed");
        }
        finally { Directory.Delete(root, true); }
        await CheckSessionRecovery();
        Console.WriteLine("PASS: transactional watcher startup, onboarding gate, same-path restart after failure and stable active session");
    }

    private static async Task CheckSessionRecovery()
    {
        var root = Path.Combine(Path.GetTempPath(), "jieliu-session-" + Guid.NewGuid());
        Directory.CreateDirectory(root);
        var input = Path.Combine(root, "input");
        var archive = Path.Combine(root, "archive");
        File.WriteAllText(archive, "temporarily blocks archive directory");
        try
        {
            var captures = new ConcurrentQueue<Capture>();
            await using var session = new CaptureSession(_ => (640, 400));
            session.Captured += captures.Enqueue;
            Check(!await session.RestartAsync(false, input, archive) && !Directory.Exists(input),
                "Preferences before Start collecting initialized screenshot directories");
            var failed = false;
            try { await session.RestartAsync(true, input, archive); }
            catch (IOException) { failed = true; }
            Check(failed, "Session accepted failed watcher initialization");
            File.Delete(archive);
            Check(await session.RestartAsync(true, input, archive), "Selecting the same paths did not retry failed startup");
            File.WriteAllText(Path.Combine(input, "recovered.png"), "recovered image");
            await Until(() => captures.Count == 1, "Recovered session did not collect a new image");
            Check(!await session.RestartAsync(true, input, archive), "Unchanged active paths unnecessarily restarted the watcher");
            File.WriteAllText(Path.Combine(input, "next.png"), "second image");
            await Until(() => captures.Count == 2, "Saving unchanged preferences interrupted collection");
            Check(captures.All(c => File.Exists(c.Path) && Path.GetDirectoryName(c.Path) == archive), "Recovered captures were not archived");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task Until(Func<bool> condition, string reason)
    {
        var deadline = DateTime.UtcNow.AddSeconds(6);
        while (!condition() && DateTime.UtcNow < deadline) await Task.Delay(40);
        Check(condition(), reason);
    }

    private static void Check(bool condition, string reason)
    {
        if (!condition) throw new Exception(reason);
    }
}
