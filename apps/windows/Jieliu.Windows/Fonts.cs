using System;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Media;

namespace Jieliu.Windows;

internal static class Fonts
{
    public static Typeface Mono { get; } = Load();
    private static Typeface Load()
    {
        try
        {
            var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Jieliu", "Fonts");
            Directory.CreateDirectory(directory);
            var path = Path.Combine(directory, "GeistMono-Medium.ttf");
            if (!File.Exists(path))
            {
                using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("Jieliu.GeistMono")!;
                using var reader = new StreamReader(stream);
                File.WriteAllBytes(path, Convert.FromBase64String(reader.ReadToEnd()));
            }
            return new Typeface(new FontFamily(new Uri(directory + Path.DirectorySeparatorChar), "./#Geist Mono"), FontStyles.Normal, FontWeights.Medium, FontStretches.Normal);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or FormatException)
        { return new Typeface("Consolas"); }
    }
}
