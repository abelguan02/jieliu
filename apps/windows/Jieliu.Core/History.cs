using System.Text.Json;

namespace Jieliu.Core;

public sealed record Capture(Guid Id, string Path, DateTime Created, int Width, int Height);

public sealed class History
{
    public const int Capacity = 8;
    public List<Capture> Items { get; set; } = [];
    public Guid?[] Slots { get; set; } = new Guid?[Capacity];
    public int WritePointer { get; set; }
    public long Total { get; set; }

    public void Insert(Capture capture)
    {
        if (Items.Any(c => c.Id == capture.Id)) return;
        Remove(Items.Where(c => SamePath(c.Path, capture.Path)).Select(c => c.Id).ToHashSet());
        if (Slots[WritePointer] is { } id) Items.RemoveAll(c => c.Id == id);
        Items.Insert(0, capture);
        Slots[WritePointer] = capture.Id;
        WritePointer = (WritePointer + 1) % Capacity;
        Total++;
    }

    public void Remove(ISet<Guid> ids)
    {
        Items.RemoveAll(c => ids.Contains(c.Id));
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
        var used = new HashSet<Guid>();
        for (var i = 0; i < Capacity; i++)
            if (Slots[i] is { } id && (!live.Contains(id) || !used.Add(id))) Slots[i] = null;
        foreach (var item in Items.Where(c => !Slots.Contains(c.Id))) Slots[Array.IndexOf(Slots, null)] = item.Id;
        Total = Math.Max(Total, Items.Count);
    }

    public static bool SamePath(string a, string b) => string.Equals(System.IO.Path.GetFullPath(a), System.IO.Path.GetFullPath(b), StringComparison.OrdinalIgnoreCase);
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
