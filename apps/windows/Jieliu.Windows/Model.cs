using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows.Media.Imaging;
using Jieliu.Core;

namespace Jieliu.Windows;

public sealed class Preferences
{
    public bool English { get; set; }
    public string Style { get; set; } = "B";
    public bool MenuOnly { get; set; }
    public bool AutoHide { get; set; } = true;
    public bool Animations { get; set; } = true;
    public string Source { get; set; } = Native.Screenshots();
    public string Destination { get; set; } = Native.Screenshots();
}

public sealed class Model
{
    private readonly string folder;
    private readonly Dictionary<Guid, BitmapSource> thumbnails = [];
    public Preferences Settings { get; private set; } = new();
    public History History { get; private set; } = new();
    public HashSet<Guid> Selection { get; } = [];
    public bool LastChangeWasCapture { get; private set; }
    public string LastError { get; private set; } = "";
    public event Action? Changed;
    public event Action? PreferencesChanged;
    public event Action<Capture>? Received;
    public event Action<string>? NoticeRaised;
    public string Text(string chinese, string english) => Settings.English ? english : chinese;

    public Model(string? storage = null)
    {
        folder = storage ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Jieliu");
        try
        {
            Settings = JsonStore.Read<Preferences>(Path.Combine(folder, "settings.json")) ?? new();
            if (!new[] { "A", "B", "C" }.Contains(Settings.Style)) Settings.Style = "B";
            if (string.IsNullOrWhiteSpace(Settings.Source)) Settings.Source = Native.Screenshots();
            if (string.IsNullOrWhiteSpace(Settings.Destination)) Settings.Destination = Native.Screenshots();
        }
        catch (Exception ex) when (ex is IOException or System.Text.Json.JsonException or UnauthorizedAccessException) { LastError = ex.Message; }
        try
        {
            History = History.Load(Path.Combine(folder, "history.json"));
        }
        catch (Exception ex) when (ex is IOException or System.Text.Json.JsonException or UnauthorizedAccessException) { LastError = ex.Message; }
    }
    public void Error(string text) { LastError = text; Changed?.Invoke(); }
    public void Notify() => Changed?.Invoke();
    public void SavePreferences()
    {
        try { JsonStore.Save(Path.Combine(folder, "settings.json"), Settings); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { Error(ex.Message); }
        PreferencesChanged?.Invoke(); Changed?.Invoke();
    }
    private void SaveHistory()
    {
        try { JsonStore.Save(Path.Combine(folder, "history.json"), History); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { Error(ex.Message); }
    }
    public void Receive(Capture capture)
    {
        var result = History.Insert(capture);
        if (result.Status == InsertionStatus.Duplicate) return;
        if (result.Status == InsertionStatus.Full)
        {
            NoticeRaised?.Invoke(Text("8 格均已固定，截图已保存到文件夹，未加入托盘", "All 8 slots are pinned. Screenshot saved to folder; tray unchanged."));
            return;
        }
        LastChangeWasCapture = true;
        Selection.IntersectWith(History.Items.Select(c => c.Id));
        foreach (var id in thumbnails.Keys.Except(History.Items.Select(c => c.Id)).ToArray()) thumbnails.Remove(id);
        SaveHistory(); Changed?.Invoke(); Received?.Invoke(capture);
    }
    public void RemoveSelected()
    {
        LastChangeWasCapture = false;
        History.Remove(Selection);
        foreach (var id in Selection) thumbnails.Remove(id);
        Selection.Clear(); SaveHistory(); Changed?.Invoke();
    }
    public bool SelectionIsPinned
    {
        get
        {
            var live = Selection.Intersect(History.Items.Select(c => c.Id)).ToHashSet();
            return live.Count > 0 && live.IsSubsetOf(History.PinnedIds);
        }
    }
    public void ToggleSelectedPins()
    {
        LastChangeWasCapture = false;
        History.SetPinned(Selection, !SelectionIsPinned);
        SaveHistory(); Changed?.Invoke();
    }
    public BitmapSource? Image(Capture capture)
    {
        if (thumbnails.TryGetValue(capture.Id, out var image)) return image;
        try { return thumbnails[capture.Id] = LoadImage(capture.Path, 1000); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or FormatException or ArgumentException or NotSupportedException or System.Runtime.InteropServices.COMException) { LastError = ex.Message; return null; }
    }
    public static BitmapImage LoadImage(string path, int maxEdge = 0)
    {
        var size=maxEdge>0 ? Dimensions(path) : (0,0);
        using var stream = File.OpenRead(path);
        var image = new BitmapImage(); image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad;
        if (maxEdge>0)
        {
            var thumbnail=ImageSizing.Thumbnail(size.Item1,size.Item2,maxEdge);
            image.DecodePixelWidth=thumbnail.Width; image.DecodePixelHeight=thumbnail.Height;
        }
        image.StreamSource = stream; image.EndInit(); image.Freeze(); return image;
    }
    public static (int, int) Dimensions(string path)
    {
        using var stream = File.OpenRead(path);
        var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.DelayCreation, BitmapCacheOption.None);
        return (decoder.Frames[0].PixelWidth, decoder.Frames[0].PixelHeight);
    }
}
