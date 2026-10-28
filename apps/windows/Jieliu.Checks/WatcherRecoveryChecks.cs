using System.Collections.Concurrent;
using Jieliu.Core;

static class WatcherRecoveryChecks
{
    public static async Task Run()
    {
        static void Check(bool condition, string reason) { if (!condition) throw new Exception(reason); }
        static async Task Until(Func<bool> condition, string reason)
        {
            var deadline=DateTime.UtcNow.AddSeconds(6);
            while (!condition() && DateTime.UtcNow<deadline) await Task.Delay(50);
            Check(condition(),reason);
        }
        var root=Path.Combine(Path.GetTempPath(),"jieliu-recovery-"+Guid.NewGuid());
        var input=Path.Combine(root,"input"); var archive=Path.Combine(root,"archive");
        Directory.CreateDirectory(input);
        try
        {
            var captured=new ConcurrentQueue<Capture>(); var errors=new ConcurrentQueue<string>();
            await using var watcher=new CaptureWatcher([input],archive,path => File.ReadAllText(path)=="partial"
                ? throw new FormatException("incomplete bitmap format") : (640,400));
            watcher.Captured+=captured.Enqueue; watcher.Error+=errors.Enqueue; watcher.Start();
            var bad=Path.Combine(input,"bad.png"); File.WriteAllText(bad,"partial");
            await Until(()=>!errors.IsEmpty,"Format error was not reported");
            Check(File.Exists(bad),"Bad image was moved or deleted");
            File.WriteAllText(Path.Combine(input,"valid.png"),"valid");
            await Until(()=>captured.Count==1,"Decoder failure stopped subsequent captures");
            File.WriteAllText(bad,"complete");
            await Until(()=>captured.Count==2,"Completed image was not retried");
            Check(errors.Count==1,"Unchanged malformed image repeatedly reports errors");
        }
        finally { Directory.Delete(root,true); }
        var fatalRoot=Path.Combine(Path.GetTempPath(),"jieliu-fatal-check-"+Guid.NewGuid());
        Directory.CreateDirectory(fatalRoot);
        try
        {
            var errors=new ConcurrentQueue<string>();
            var watcher=new CaptureWatcher([fatalRoot],fatalRoot,_=>throw new InvalidOperationException("unexpected decoder failure"));
            watcher.Error+=errors.Enqueue; watcher.Start();
            File.WriteAllText(Path.Combine(fatalRoot,"fatal.png"),"fatal fixture");
            await Until(()=>errors.Any(e=>e.StartsWith("Capture watcher stopped:")),"Unexpected worker exit was silent");
            try { await watcher.DisposeAsync(); throw new Exception("Worker fault was swallowed"); }
            catch (InvalidOperationException ex) when (ex.Message=="unexpected decoder failure") { }
            var signal=(SemaphoreSlim)typeof(CaptureWatcher).GetField("signal",System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic)!.GetValue(watcher)!;
            try { signal.Wait(0); throw new Exception("Faulted worker leaked signal"); }
            catch (ObjectDisposedException) { }
        }
        finally { Directory.Delete(fatalRoot,true); }
        Console.WriteLine("PASS: image format failure reports, preserves source, continues/retries; unexpected worker fault reports and disposes resources");
    }
}
