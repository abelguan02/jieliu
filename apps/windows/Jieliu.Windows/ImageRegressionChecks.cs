using System;
using System.Collections.Concurrent;
using System.IO;
using System.Threading;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Jieliu.Core;

namespace Jieliu.Windows;

internal static class ImageRegressionChecks
{
    internal static void Run()
    {
        static void Check(bool value,string reason) { if (!value) throw new Exception(reason); }
        static void Wait(Func<bool> condition,string reason)
        {
            var deadline=DateTime.UtcNow.AddSeconds(6);
            while (!condition() && DateTime.UtcNow<deadline) Thread.Sleep(40);
            Check(condition(),reason);
        }
        var root=Path.Combine(Path.GetTempPath(),"jieliu-image-check-"+Guid.NewGuid());
        Directory.CreateDirectory(root);
        try
        {
            var model=new Model(Path.Combine(root,"storage"));
            var source=Path.Combine(root,"input"); Directory.CreateDirectory(source);
            void Png(string path,int width,int height)
            {
                var pixels=new byte[width*height*4]; Array.Fill(pixels,(byte)255);
                var bitmap=BitmapSource.Create(width,height,96,96,PixelFormats.Bgra32,null,pixels,width*4);
                var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using var file=File.Create(path); encoder.Save(file);
            }
            foreach (var (width,height) in new[] { (100,2000),(2000,100),(40,30) })
            {
                var path=Path.Combine(root,$"{width}x{height}.png"); Png(path,width,height);
                var capture=new Capture(Guid.NewGuid(),path,DateTime.UtcNow,width,height);
                model.Receive(capture);
                var image=model.Image(capture)!;
                var expected=ImageSizing.Thumbnail(width,height,1000);
                Check(image.PixelWidth==expected.Width && image.PixelHeight==expected.Height,"Actual WPF thumbnail is unbounded or upscaled");
                var original=Model.LoadImage(path);
                Check(original.PixelWidth==width && original.PixelHeight==height,"Original used for drag/copy was resized");
            }
            var bad=Path.Combine(root,"bad.png"); File.WriteAllText(bad,"not a PNG");
            Check(model.Image(new Capture(Guid.NewGuid(),bad,DateTime.UtcNow,100,2000)) is null && !string.IsNullOrEmpty(model.LastError),"Malformed thumbnail was not reported");
            var captures=new ConcurrentQueue<Capture>(); var errors=new ConcurrentQueue<string>();
            var watcher=new CaptureWatcher([source],Path.Combine(root,"archive"),path => Path.GetFileName(path)=="format.png"
                ? throw new FileFormatException("native format failure") : Model.Dimensions(path));
            watcher.Captured+=captures.Enqueue; watcher.Error+=errors.Enqueue; watcher.Start();
            try
            {
                File.WriteAllText(Path.Combine(source,"format.png"),"malformed");
                Wait(()=>!errors.IsEmpty,"Actual FileFormatException was not reported");
                Png(Path.Combine(source,"valid.png"),40,30);
                Wait(()=>captures.Count==1,"WPF format error stopped subsequent native decoding");
            }
            finally { watcher.DisposeAsync().AsTask().GetAwaiter().GetResult(); }
            Check(File.Exists(Path.Combine(source,"format.png")),"Malformed original was removed");
            Console.WriteLine("PASS: native WPF bounded thumbnails, original dimensions, malformed image reporting and FileFormatException recovery");
        }
        finally { Directory.Delete(root,true); }
    }
}
