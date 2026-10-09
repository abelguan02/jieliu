using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Forms = System.Windows.Forms;

namespace Jieliu.Windows;

internal static class Native
{
    [DllImport("shell32.dll")] private static extern int SHGetKnownFolderPath(in Guid id, uint flags, IntPtr token, out IntPtr path);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromPoint(PointNative point, uint flags);
    [DllImport("shcore.dll")] private static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint x, out uint y);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr window, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern IntPtr SetWindowLongPtr(IntPtr window, int index, IntPtr value);
    [StructLayout(LayoutKind.Sequential)] private readonly struct PointNative(int x, int y) { public readonly int X = x, Y = y; }

    public static string Screenshots()
    {
        var id = new Guid("b7bede81-df94-4682-a7d8-57a52620b86f");
        if (SHGetKnownFolderPath(in id, 0, IntPtr.Zero, out var path) >= 0)
        {
            try { return Marshal.PtrToStringUni(path)!; } finally { Marshal.FreeCoTaskMem(path); }
        }
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Screenshots");
    }
    public static void ToolWindow(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        SetWindowLongPtr(handle, -20, (IntPtr)(GetWindowLongPtr(handle, -20).ToInt64() | 0x80));
    }
    public static void Position(Window window, Forms.Screen screen, double logicalWidth, double logicalHeight)
    {
        var area = screen.WorkingArea;
        var monitor = MonitorFromPoint(new(area.Left + 1, area.Top + 1), 2);
        var scale = GetDpiForMonitor(monitor, 0, out var dpi, out _) == 0 ? dpi / 96.0 : 1;
        var fit = Math.Min(1, Math.Max(0.25, (area.Width - 24 * scale) / (logicalWidth * scale)));
        var w = (int)Math.Round(logicalWidth * scale * fit);
        var h = (int)Math.Round(logicalHeight * scale * fit);
        SetWindowPos(new WindowInteropHelper(window).Handle, new IntPtr(-1), area.Left + (area.Width - w) / 2,
            area.Top + (int)(8 * scale), w, h, 0x0010); // SWP_NOACTIVATE
    }
}
