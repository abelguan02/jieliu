using System.Text.Json;
using System.Text.Json.Nodes;
using Jieliu.Core;

internal static class SharedHistoryChecks
{
    private sealed record Scenario(string Name, string[] Initial, Step[] Steps, Expected Expected);
    private sealed record Step(string Op, string? Id, string? Path, string[]? Ids);
    private sealed record Expected(string[] Items, string?[] Slots, string[] Pinned, int Pointer, long Total, string? Status, string? Evicted, int? Next);

    public static void Run()
    {
        var fixture = Path.Combine(AppContext.BaseDirectory, "fixtures", "history.json");
        var scenarios = JsonSerializer.Deserialize<Scenario[]>(File.ReadAllText(fixture), new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
        foreach (var scenario in scenarios)
        {
            var root = Path.Combine(Path.GetTempPath(), "jieliu-shared-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            try
            {
                var historyPath = Path.Combine(root, "history.json");
                var history = new History();
                var ids = new Dictionary<string, Guid>();
                var captures = new Dictionary<string, Capture>();
                var deleted = new HashSet<string>();
                InsertionResult? result = null;
                Guid Id(string name)
                {
                    if (!ids.TryGetValue(name, out var value)) ids[name] = value = Guid.NewGuid();
                    return value;
                }
                Capture Shot(string name, string? file = null)
                {
                    if (captures.TryGetValue(name, out var value)) return value;
                    var path = Path.Combine(root, (file ?? name) + ".png");
                    File.WriteAllBytes(path, [1, 2, 3]);
                    return captures[name] = new(Id(name), path, DateTime.UtcNow, 10, 10);
                }
                foreach (var name in scenario.Initial) history.Insert(Shot(name));
                foreach (var step in scenario.Steps)
                {
                    switch (step.Op)
                    {
                        case "insert": result = history.Insert(Shot(step.Id!, step.Path)); break;
                        case "pin": case "unpin": history.SetPinned(step.Ids!.Select(Id).ToHashSet(), step.Op == "pin"); break;
                        case "remove": history.Remove(step.Ids!.Select(Id).ToHashSet()); break;
                        case "deleteFile":
                            var path = captures[step.Id!].Path; File.Delete(path); deleted.Add(path); break;
                        case "reload": case "legacyReload":
                            var json = JsonSerializer.SerializeToNode(history)!.AsObject();
                            if (step.Op == "legacyReload") json.Remove("PinnedIds");
                            JsonStore.Save(historyPath, json); history = History.Load(historyPath); break;
                        default: throw new Exception("Unknown history operation: " + step.Op);
                    }
                }
                var expected = scenario.Expected;
                void Check(bool value, string field) { if (!value) throw new Exception($"Shared history {scenario.Name}: {field}"); }
                Check(history.Items.Select(c => c.Id).SequenceEqual(expected.Items.Select(Id)), "items");
                Check(history.Slots.SequenceEqual(expected.Slots.Select(n => n is null ? (Guid?)null : Id(n))), "slots");
                Check(history.PinnedIds.SetEquals(expected.Pinned.Select(Id)), "pins");
                Check(history.WritePointer == expected.Pointer && history.Total == expected.Total, "cursor/total");
                Check(history.NextWriteSlot == expected.Next, "next write slot");
                Check(result?.Status.ToString().ToLowerInvariant() == expected.Status, "insert status");
                Check(result?.Evicted?.Id == (expected.Evicted is null ? (Guid?)null : Id(expected.Evicted)), "evicted");
                foreach (var capture in captures.Values.Where(c => !deleted.Contains(c.Path)))
                    Check(File.ReadAllBytes(capture.Path).SequenceEqual(new byte[] { 1, 2, 3 }), "original file preserved");
            }
            finally { Directory.Delete(root, true); }
        }
        Console.WriteLine($"PASS: {scenarios.Length} shared history fixtures (empty slots, pins, full tray, versions and persistence)");
    }
}
