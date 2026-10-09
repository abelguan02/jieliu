using System.Collections.Concurrent;
using Jieliu.Core;

static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
static Capture Shot(string path) => new(Guid.NewGuid(), path, DateTime.Now, 640, 400);
static async Task Until(Func<bool> condition, string reason)
{
    var deadline = DateTime.UtcNow.AddSeconds(8);
    while (!condition() && DateTime.UtcNow < deadline) await Task.Delay(80);
    Check(condition(), reason);
}

var root = Path.Combine(Path.GetTempPath(), "jieliu-check-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
try
{
    var history = new History();
    var shots = Enumerable.Range(0, 10).Select(i => Shot(Path.Combine(root, i + ".png"))).ToArray();
    foreach (var shot in shots) history.Insert(shot);
    Check(history.Items.Count == 8 && history.WritePointer == 2 && history.Slots[0] == shots[8].Id && history.Slots[1] == shots[9].Id, "Ring must retain stable slots");
    history.Insert(shots[9]); Check(history.Total == 10 && history.WritePointer == 2, "Duplicate advances pointer");
    var replacement = Shot(shots[9].Path); history.Insert(replacement);
    Check(!history.Items.Any(c => c.Id == shots[9].Id) && history.Items[0] == replacement, "Same-path new version not replaced");
    File.WriteAllText(replacement.Path, "original");
    history.Remove(new HashSet<Guid> { replacement.Id });
    Check(File.ReadAllText(replacement.Path) == "original", "Removing a record must retain the file");
    var historyFile = Path.Combine(root, "history.json"); JsonStore.Save(historyFile, history);
    var restored = JsonStore.Read<History>(historyFile)!; restored.Validate();
    Check(restored.WritePointer == history.WritePointer && restored.Total == history.Total && restored.Slots.SequenceEqual(history.Slots), "Persistence loses ring state");
    restored.Slots = []; restored.WritePointer = 999; restored.Validate();
    Check(restored.Slots.Length == 8 && restored.WritePointer < 8, "Corrupt persisted ring not repaired");
    Console.WriteLine("PASS: ring order, duplicate ID, same-path replacement, removal preserves file, atomic persistence and validation");

    var source = Path.Combine(root, "source"); var archive = Path.Combine(root, "archive");
    Directory.CreateDirectory(source); Directory.CreateDirectory(archive);
    var blocked = Path.Combine(root, "not-a-directory"); File.WriteAllText(blocked, "blocked");
    var retained = Path.Combine(root, "retain.png"); File.WriteAllText(retained, "retain");
    try { Archive.Move(retained, blocked); throw new Exception("Archive unexpectedly succeeded"); }
    catch (IOException) { Check(File.ReadAllText(retained) == "retain", "Failed archive removed source"); }
    var old = Path.Combine(source, "old.png"); File.WriteAllText(old, "old");
    var captures = new ConcurrentQueue<Capture>(); var errors = new ConcurrentQueue<string>();
    await using (var watcher = new CaptureWatcher([source], archive, path => File.ReadAllText(path) == "partial" ? throw new IOException("Incomplete image") : (640, 400)))
    {
        watcher.Captured += captures.Enqueue; watcher.Error += errors.Enqueue; watcher.Start();
        await Task.Delay(800); Check(captures.IsEmpty && File.Exists(old), "Startup baseline must not collect old files");
        var path = Path.Combine(source, "same.png");
        File.WriteAllText(path, "one"); await Until(() => captures.Count == 1, "First file not collected");
        File.WriteAllText(path, "two"); await Until(() => captures.Count == 2, "Reused path not collected");
        var items = captures.ToArray();
        Check(items[0].Path != items[1].Path && File.ReadAllText(items[0].Path) == "one" && File.ReadAllText(items[1].Path) == "two", "Collision overwrote original");
        var renamed = Path.Combine(archive, "renamed.png"); File.Move(items[1].Path, renamed);
        await Task.Delay(1000); Check(captures.Count == 2, "Archive rename or events duplicated capture");
        File.WriteAllText(items[0].Path, "new version"); await Until(() => captures.Count == 3, "Changed file in archive ignored");
        var partial = Path.Combine(source, "partial.png"); File.WriteAllText(partial, "partial");
        await Task.Delay(1200); Check(captures.Count == 3 && File.Exists(partial), "Invalid image moved or unexpected capture: " + string.Join(", ", captures.Select(c => Path.GetFileName(c.Path))) + "; errors: " + string.Join(", ", errors));
        File.WriteAllText(partial, "complete"); await Until(() => captures.Count == 4, "Completed image not retried");
        File.WriteAllText(Path.Combine(source, "ignore.txt"), "ignored");
        await Task.Delay(800); Check(captures.Count == 4 && File.Exists(old), "Unrelated files or baseline unexpectedly collected");
        Check(errors.All(e => e == "Incomplete image"), "Unexpected watcher error: " + string.Join(",", errors));
    }
    Console.WriteLine("PASS: archive failure preserves source, watcher baseline, source reuse, collision preservation, rename deduplication, archive replacement, delayed writes and retry");
}
finally { Directory.Delete(root, true); }
