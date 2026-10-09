using System;
using System.Drawing;
using System.Runtime.InteropServices;

namespace Jieliu.Windows;

internal static class TrayIcon
{
    [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr icon);
    public static Icon Create()
    {
        using var bitmap = new Bitmap(32, 32);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.Clear(Color.FromArgb(12, 14, 18));
        using var pen = new Pen(Color.White, 2.4f);
        foreach (var (x, dx) in new[] { (5, 1), (27, -1) })
            foreach (var (y, dy) in new[] { (7, 1), (25, -1) })
            {
                graphics.DrawLine(pen, x, y, x + 6 * dx, y);
                graphics.DrawLine(pen, x, y, x, y + 6 * dy);
            }
        graphics.FillRectangle(Brushes.CornflowerBlue, 13, 14, 6, 4);
        var handle = bitmap.GetHicon();
        try { using var borrowed = Icon.FromHandle(handle); return (Icon)borrowed.Clone(); }
        finally { DestroyIcon(handle); }
    }
}
