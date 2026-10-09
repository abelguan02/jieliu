using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Jieliu.Core;

namespace Jieliu.Windows;

internal sealed class PreviewWindow : Window
{
    private readonly Model model;
    private readonly List<Capture> items;
    private int index;
    private readonly Image image = new() { Stretch = Stretch.Uniform, Margin = new Thickness(12) };
    public PreviewWindow(Model model, List<Capture> items, Capture capture)
    {
        this.model = model; this.items = items; index = items.IndexOf(capture);
        Width = Math.Min(1000, SystemParameters.WorkArea.Width * 0.8);
        Height = Math.Min(740, SystemParameters.WorkArea.Height * 0.8);
        Background = new SolidColorBrush(Color.FromRgb(24, 26, 30));
        WindowStartupLocation = WindowStartupLocation.CenterScreen; Content = image;
        KeyDown += (_, e) =>
        {
            if (e.Key is Key.Escape or Key.Space) Close();
            else if (e.Key is Key.Left or Key.Right) { index = Math.Clamp(index + (e.Key == Key.Left ? -1 : 1), 0, items.Count - 1); ShowImage(); }
        };
        ShowImage();
    }
    private void ShowImage()
    {
        var capture = items[index];
        Title = $"{System.IO.Path.GetFileName(capture.Path)} · {capture.Width} × {capture.Height} · {index + 1}/{items.Count}";
        try { image.Source = Model.LoadImage(capture.Path); }
        catch (Exception ex) { image.Source = null; model.Error(ex.Message); }
    }
}
