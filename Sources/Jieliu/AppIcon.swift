import AppKit

enum AppIcon {
    static func write(to url:URL) throws {
        var chunks=Data()
        for (size,type) in [(128,"ic07"),(256,"ic08"),(512,"ic09"),(1024,"ic10")] {
            let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            let context=NSGraphicsContext(bitmapImageRep:bitmap)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=context
            context.cgContext.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
            let rect=CGRect(x:70,y:70,width:884,height:884)
            Ink.box(rect,color:Ink.color(0x101216),radius:195,stroke:Ink.color(0x333945))
            let corners=[(CGPoint(x:250,y:410),CGPoint(x:250,y:250),CGPoint(x:410,y:250)),(CGPoint(x:614,y:250),CGPoint(x:774,y:250),CGPoint(x:774,y:410)),(CGPoint(x:774,y:614),CGPoint(x:774,y:774),CGPoint(x:614,y:774)),(CGPoint(x:410,y:774),CGPoint(x:250,y:774),CGPoint(x:250,y:614))]
            for (a,b,c) in corners { Ink.line(a,b,color:.white,width:22); Ink.line(b,c,color:.white,width:22) }
            for (index,color) in [Ink.red,Ink.green,Ink.blue].enumerated() {
                Ink.box(CGRect(x:340+index*122,y:395,width:100,height:230),color:color,radius:18)
            }
            NSGraphicsContext.restoreGraphicsState()
            let png=bitmap.representation(using:.png,properties:[:])!
            chunks.append(type.data(using:.ascii)!); chunks.append(integer(png.count+8)); chunks.append(png)
        }
        var file=Data("icns".utf8); file.append(integer(chunks.count+8)); file.append(chunks)
        try file.write(to:url,options:.atomic)
    }
    private static func integer(_ value:Int)->Data { var number=UInt32(value).bigEndian; return withUnsafeBytes(of:&number) { Data($0) } }
}
