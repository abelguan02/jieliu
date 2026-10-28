namespace Jieliu.Core;

public static class ImageSizing
{
    public static (int Width, int Height) Thumbnail(int width, int height, int maxEdge)
    {
        if (width<=0 || height<=0 || maxEdge<=0) throw new ArgumentOutOfRangeException(nameof(width),"Image dimensions and maximum edge must be positive");
        var scale=Math.Min(1,maxEdge/(double)Math.Max(width,height));
        return (Math.Max(1,(int)(width*scale)),Math.Max(1,(int)(height*scale)));
    }
}
