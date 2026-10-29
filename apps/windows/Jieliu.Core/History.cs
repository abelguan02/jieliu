using System.Text.Json;
using System.Text.Json.Serialization;

namespace Jieliu.Core;

public sealed record Capture(Guid Id, string Path, DateTime Created, int Width, int Height);
public enum InsertionStatus { Inserted, Duplicate, Full }
public readonly record struct InsertionResult(InsertionStatus Status, Capture? Evicted = null);

public sealed class History
{
    public const int Capacity = 8;
    public List<Capture> Items { get; set; } = [];
    public Guid?[] Slots { get; set; } = new Guid?[Capacity];
    public int WritePointer { get; set; }
    public long Total { get; set; }
    public HashSet<Guid> PinnedIds { get; set; } = [];

    [JsonIgnore]
    public int? NextWriteSlot
    {
        get
        {
            var order = Enumerable.Range(0, Capacity).Select(i => (WritePointer + i) % Capacity).ToArray();
            var index = Array.FindIndex(order, i => Slots[i] is null);
            if (index >= 0) return order[index];
            index = Array.FindIndex(order, i => Slots[i] is { } id && !PinnedIds.Contains(id));
            return index >= 0 ? order[index] : null;
        }
    }

    public void SetPinned(ISet<Guid> ids, bool pinned)
    {
        var live = Items.Where(c => ids.Contains(c.Id)).Select(c => c.Id);
        if (pinned) PinnedIds.UnionWith(live); else PinnedIds.ExceptWith(live);
    }

    public InsertionResult Insert(Capture capture)
    {
        if (Items.Any(c => c.Id == capture.Id)) return new(InsertionStatus.Duplicate);
        // A new version of a pinned file keeps its slot and pin, without moving the cursor.
        if (Items.FirstOrDefault(c => SamePath(c.Path, capture.Path) && PinnedIds.Contains(c.Id)) is { } old)
        {
            var pinnedSlot = Array.IndexOf(Slots, old.Id);
            Remove(new HashSet<Guid> { old.Id }); Items.Insert(0, capture); Slots[pinnedSlot] = capture.Id;
            PinnedIds.Add(capture.Id); Total++;
            return new(InsertionStatus.Inserted, old);
        }
        Remove(Items.Where(c => SamePath(c.Path, capture.Path)).Select(c => c.Id).ToHashSet());
        if (NextWriteSlot is not { } index) return new(InsertionStatus.Full);
        var evicted = Items.FirstOrDefault(c => c.Id == Slots[index]);
        if (evicted is not null) Items.RemoveAll(c => c.Id == evicted.Id);
        Items.Insert(0, capture);
        Slots[index] = capture.Id;
        WritePointer = (index + 1) % Capacity;
        Total++;
        return new(InsertionStatus.Inserted, evicted);
    }

    public void Remove(ISet<Guid> ids)
    {
        Items.RemoveAll(c => ids.Contains(c.Id));
        PinnedIds.ExceptWith(ids);
        for (var i = 0; i < Slots.Length; i++)
            if (Slots[i] is { } id && ids.Contains(id)) Slots[i] = null;
    }

    public void Validate()
    {
        Items = (Items ?? []).Where(c => c is not null && !string.IsNullOrWhiteSpace(c.Path))
            .DistinctBy(c => c.Id).DistinctBy(c => c.Path, StringComparer.OrdinalIgnoreCase)
            .Take(Capacity).ToList();
        if (Slots is null || Slots.Length != Capacity || WritePointer < 0 || WritePointer >= Capacity)
        {
            Slots = new Guid?[Capacity];
            foreach (var (item, index) in Items.AsEnumerable().Reverse().Select((c, i) => (c, i))) Slots[index] = item.Id;
            WritePointer = Items.Count % Capacity;
        }
        var live = Items.Select(c => c.Id).ToHashSet();
        PinnedIds = (PinnedIds ?? []).Intersect(live).ToHashSet();
        var used = new HashSet<Guid>();
        for (var i = 0; i < Capacity; i++)
            if (Slots[i] is { } id && (!live.Contains(id) || !used.Add(id))) Slots[i] = null;
        foreach (var item in Items.Where(c => !Slots.Contains(c.Id))) Slots[Array.IndexOf(Slots, null)] = item.Id;
        Total = Math.Max(Total, Items.Count);
    }

    public static bool SamePath(string a, string b) => string.Equals(System.IO.Path.GetFullPath(a), System.IO.Path.GetFullPath(b), StringComparison.OrdinalIgnoreCase);

    public static History Load(string path)
    {
        var history = JsonStore.Read<History>(path) ?? new();
        history.Validate();
        history.Remove(history.Items.Where(c => !File.Exists(c.Path)).Select(c => c.Id).ToHashSet());
        return history;
    }
}

public static class JsonStore
{
    public static T? Read<T>(string path) => File.Exists(path) ? JsonSerializer.Deserialize<T>(File.ReadAllText(path)) : default;
    public static void Save<T>(string path, T value)
    {
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(path)!);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporary, path, true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
