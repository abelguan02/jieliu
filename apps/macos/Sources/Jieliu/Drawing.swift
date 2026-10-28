import AppKit

enum Ink {
    static let guide = color(0x30d5f7), red = color(0xff3b5c), green = color(0x2be38c), blue = color(0x3d7bff)
    static let foreground = color(0xe8eaee), muted = color(0x8b919c)
    private static func font(_ size:CGFloat,weight:NSFont.Weight = .medium)->NSFont {
        NSFont(name:"GeistMono-Medium",size:size) ?? NSFont.monospacedSystemFont(ofSize:size,weight:weight)
    }
    static func textWidth(_ string:String,size:CGFloat=11)->CGFloat {
        ceil((string as NSString).size(withAttributes:[.font:font(size)]).width)
    }
    static func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255, blue: CGFloat(hex & 255)/255, alpha: alpha)
    }
    static func text(_ string: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 11, color: NSColor = foreground, weight: NSFont.Weight = .medium, alignment:NSTextAlignment = .left) {
        let font=font(size,weight:weight)
        let width=(string as NSString).size(withAttributes:[.font:font]).width
        let left=x-(alignment == .right ? width : alignment == .center ? width/2 : 0)
        (string as NSString).draw(at: NSPoint(x:left,y:y),withAttributes:[.font:font,.foregroundColor:color])
    }
    static func text(_ string:String,in rect:CGRect,size:CGFloat=11,color:NSColor=foreground,alignment:NSTextAlignment = .left) {
        let paragraph=NSMutableParagraphStyle()
        paragraph.alignment=alignment; paragraph.lineBreakMode = .byTruncatingMiddle
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:rect).addClip()
        (string as NSString).draw(in:rect,withAttributes:[.font:font(size),.foregroundColor:color,.paragraphStyle:paragraph])
        NSGraphicsContext.restoreGraphicsState()
    }
    static func box(_ rect: CGRect, color: NSColor, radius: CGFloat = 0, stroke: NSColor? = nil) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        color.setFill(); path.fill()
        if let stroke { stroke.setStroke(); path.lineWidth = 1; path.stroke() }
    }
    static func line(_ from: CGPoint, _ to: CGPoint, color: NSColor, width: CGFloat = 1) {
        let path = NSBezierPath(); path.move(to: from); path.line(to: to); path.lineWidth = width; color.setStroke(); path.stroke()
    }
    static func fit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width/size.width, rect.height/size.height)
        let result = CGSize(width: size.width*scale, height: size.height*scale)
        return CGRect(x: rect.midX-result.width/2, y: rect.midY-result.height/2, width: result.width, height: result.height)
    }
    static func image(_ image: NSImage, in rect: CGRect, alpha: CGFloat = 1) {
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
    static func selection(_ rect: CGRect, time: Double) {
        let r = rect.insetBy(dx: -4, dy: -4)
        let path = NSBezierPath(rect: r); NSColor.black.setStroke(); path.lineWidth = 1; path.stroke()
        path.setLineDash([4,4], count: 2, phase: CGFloat(time*13).truncatingRemainder(dividingBy: 8))
        NSColor.white.setStroke(); path.stroke()
        for p in [CGPoint(x: r.minX,y:r.minY),CGPoint(x:r.maxX,y:r.minY),CGPoint(x:r.minX,y:r.maxY),CGPoint(x:r.maxX,y:r.maxY)] {
            box(CGRect(x:p.x-3,y:p.y-3,width:6,height:6),color:.white,stroke:.black)
        }
    }
    static func checker(_ rect: CGRect, cell: CGFloat = 8) {
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect: rect).addClip()
        for row in 0...Int(rect.height/cell) { for col in 0...Int(rect.width/cell) {
            box(CGRect(x:rect.minX+CGFloat(col)*cell,y:rect.minY+CGFloat(row)*cell,width:cell,height:cell),color:(row+col)%2 == 0 ? .white : color(0xd6d6d6))
        } }; NSGraphicsContext.restoreGraphicsState()
    }
    static func rgb(_ rect: CGRect) {
        for (i, c) in [red,green,blue].enumerated() { box(CGRect(x:rect.minX+CGFloat(i)*rect.width/3,y:rect.minY,width:rect.width/3,height:rect.height),color:c) }
    }
    static func clock(_ date: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: date) }
}

func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b-a)*t }
func clamp(_ x: CGFloat) -> CGFloat { min(1,max(0,x)) }
func ease(_ x: CGFloat) -> CGFloat { let x=clamp(x); return x*x*(3-2*x) }
func mixRect(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
    CGRect(x:mix(a.minX,b.minX,t), y:mix(a.minY,b.minY,t), width:mix(a.width,b.width,t), height:mix(a.height,b.height,t))
}
