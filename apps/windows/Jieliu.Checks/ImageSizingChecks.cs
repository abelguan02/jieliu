using Jieliu.Core;

static class ImageSizingChecks
{
    public static void Run()
    {
        foreach (var (width,height) in new[] { (100,2000),(2000,100),(40,30),(8000,8000),(1,100000),(16384,2160) })
        {
            var size=ImageSizing.Thumbnail(width,height,1000);
            if (size.Width>1000 || size.Height>1000 || size.Width>width || size.Height>height || size.Width<1 || size.Height<1)
                throw new Exception("Thumbnail exceeds maximum edge or upscales source");
        }
        if (ImageSizing.Thumbnail(100,2000,1000)!=(50,1000) || ImageSizing.Thumbnail(40,30,1000)!=(40,30))
            throw new Exception("Narrow/small thumbnail sizing is wrong");
        Console.WriteLine("PASS: bounded thumbnails for tall/wide/large images and no small-image upscaling");
    }
}
