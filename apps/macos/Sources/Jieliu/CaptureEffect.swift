import AppKit
import TrayCore

/// Only visible image geometry accepts input; the remainder of the overlay is click-through.
final class CaptureEffect: NSView {
    let image: NSImage
    let source: CGRect
    var target: CGRect
    var layerTarget:LayerPlacement
    let concept: Concept
    let top: CGFloat
    var progress: CGFloat = 0
    var pixels: [(CGRect, NSColor, CGFloat)] = []
    var onDown:((NSEvent)->Void)?
    var onUp:((NSEvent)->Void)?
    var onDrag:((NSEvent,NSView)->Void)?
    private(set) var imagePath=CGMutablePath()
    var holding=false
    override func mouseDown(with event:NSEvent) {
        guard imagePath.contains(convert(event.locationInWindow,from:nil),using:.winding) else { return }
        holding=true; onDown?(event)
    }
    override func mouseUp(with event:NSEvent) { guard holding else { return }; holding=false; onUp?(event) }
    override func mouseDragged(with event:NSEvent) { onDrag?(event,self) }
    override var isFlipped: Bool { true }

    init(image:NSImage,source:CGRect,target:CGRect,concept:Concept,top:CGFloat) {
        self.image=image; self.source=source; self.target=target; self.concept=concept; self.top=top
        layerTarget=LayerPlacement(rect:target,front:false)
        super.init(frame:.zero)
        let aspect=image.size.width/image.size.height
        let cols=aspect >= 1 ? 24 : max(2,Int(18*aspect)), rows=aspect >= 1 ? max(2,Int(24/aspect)) : 18
        if let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:cols,pixelsHigh:rows,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
           let context=NSGraphicsContext(bitmapImageRep:bitmap) {
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=context
            image.draw(in:CGRect(x:0,y:0,width:cols,height:rows)); NSGraphicsContext.restoreGraphicsState()
            for y in 0..<rows { for x in 0..<cols {
                let rect=CGRect(x:CGFloat(x)/CGFloat(cols),y:CGFloat(y)/CGFloat(rows),width:1/CGFloat(cols),height:1/CGFloat(rows))
                pixels.append((rect,bitmap.colorAt(x:x,y:y) ?? .black,CGFloat(y)/CGFloat(rows)*0.18+CGFloat(x)/CGFloat(cols)*0.06))
            } }
        }
    }
    required init?(coder:NSCoder) { fatalError() }
    func updateDestination(from tray:TrayView,capture:Capture) {
        guard let rect=tray.destinationRect(for:capture) else { return }
        let scale=tray.scale
        let screenRect=CGRect(x:rect.minX*scale,y:rect.minY*scale,width:rect.width*scale,height:rect.height*scale)
        target=concept == .buffer ? Ink.fit(image.size,in:screenRect) : screenRect
        if concept == .layers,let placement=tray.layerPlacement(for:capture) {
            layerTarget=placement.converted(scale:scale,offsetY:-(1-tray.openness)*200)
        }
    }
    func actual(_ unit:CGRect,in r:CGRect)->CGRect { CGRect(x:r.minX+unit.minX*r.width,y:r.minY+unit.minY*r.height,width:unit.width*r.width+0.5,height:unit.height*r.height+0.5) }

    override func draw(_ dirtyRect:NSRect) {
        imagePath=CGMutablePath()
        switch concept {
        case .ruler: ruler()
        case .buffer: buffer()
        case .layers: layers()
        }
    }
    private func ruler() {
        let meet=CGRect(x:target.minX,y:max(top+188,min(bounds.height-150,source.midY-target.height/2)),width:target.width,height:target.height)
        let r=progress<0.55 ? mixRect(source,meet,ease(progress/0.55)) : mixRect(meet,target,ease((progress-0.55)/0.45))
        let length=progress<0.46 ? ease((progress-0.08)/0.38) : 1
        Ink.line(CGPoint(x:target.midX,y:top+22),CGPoint(x:target.midX,y:mix(top+22,r.minY,length)),color:Ink.guide)
        Ink.image(image,in:r)
        imagePath.addRect(r)
        Ink.box(r,color:.clear,radius:2,stroke:Ink.guide.withAlphaComponent(min(1,progress*3)))
    }
    private func buffer() {
        if progress < 0.18 {
            let scan=progress/0.18, line=source.minY+source.height*scan
            for (unit,color,_) in pixels {
                let r=actual(unit,in:source)
                if r.midY<line { Ink.box(r,color:color); imagePath.addRect(r) }
            }
            scanline(CGRect(x:source.minX,y:line,width:source.width,height:6))
        } else if progress < 0.74 {
            let t=(progress-0.18)/0.56
            for (unit,color,delay) in pixels {
                let p=ease((t-delay)/(1-delay)), a=actual(unit,in:source), b=actual(unit,in:target)
                var r=mixRect(a,b,p)
                r.origin.y -= sin(p * .pi)*min(140,source.minY*0.4+40)
                r.origin.x += sin(p * .pi)*sin(unit.midY*18)*28
                Ink.box(r,color:color)
                imagePath.addRect(r)
            }
        } else {
            imagePath.addRect(target)
            let write=clamp((progress-0.74)/0.26)
            for (unit,color,_) in pixels { Ink.box(actual(unit,in:target),color:color) }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect:CGRect(x:target.minX,y:target.minY,width:target.width,height:target.height*write)).addClip()
            Ink.image(image,in:target); NSGraphicsContext.restoreGraphicsState()
            scanline(CGRect(x:target.minX,y:target.minY+target.height*write-5,width:target.width,height:6))
        }
    }
    private func scanline(_ r:CGRect) {
        for (index,color) in [Ink.red,Ink.green,Ink.blue,NSColor.white].enumerated() {
            Ink.box(CGRect(x:r.minX,y:r.minY+CGFloat(index)*1.5,width:r.width,height:1.5),color:color)
        }
    }
    private func layers() {
        if progress < 0.95 {
            let heal=clamp((progress-0.42)/0.53)
            let r=CGRect(x:source.minX,y:source.minY+source.height*heal,width:source.width,height:source.height*(1-heal))
            Ink.checker(r,cell:8); Ink.selection(r,time:CACurrentMediaTime())
        }
        let t=ease(max(0,(progress-0.3)/0.7))
        let r=mixRect(source,layerTarget.rect,t)
        guard let c=NSGraphicsContext.current?.cgContext else { return }
        c.saveGState()
        let lift=progress<0.3 ? sin(progress/0.3 * .pi/2)*24 : (1-t)*24
        c.translateBy(x:r.midX,y:r.midY-lift)
        let pose=layerTarget.transform
        c.concatenate(CGAffineTransform(a:mix(1,pose.a,t),b:mix(0,pose.b,t),c:0,d:mix(1,pose.d,t),tx:0,ty:0))
        let local=CGRect(x:-r.width/2,y:-r.height/2,width:r.width,height:r.height)
        let transform=CGAffineTransform(a:mix(1,pose.a,t),b:mix(0,pose.b,t),c:0,d:mix(1,pose.d,t),tx:r.midX,ty:r.midY-lift)
        imagePath.addRect(local,transform:transform)
        Ink.image(image,in:local); Ink.box(local,color:.clear,stroke:.white.withAlphaComponent(0.6)); c.restoreGState()
    }
}

final class EffectWindow {
    private let panel: NSPanel
    private let effect: CaptureEffect
    private var timer: Timer?
    init(screen:NSScreen,image:NSImage,source:CGRect,target:CGRect,concept:Concept,top:CGFloat,tray:TrayView,captureID:UUID,onProgress:@escaping (CGFloat)->Void,completion:@escaping ()->Void) {
        panel=NSPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.backgroundColor = .clear; panel.isOpaque=false; panel.hasShadow=false; panel.ignoresMouseEvents=true
        panel.level=NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+2)
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
        effect=CaptureEffect(image:image,source:source,target:target,concept:concept,top:top)
        if let capture=tray.model.history.items.first(where:{$0.id==captureID}) { effect.updateDestination(from:tray,capture:capture) }
        effect.onDown={ [weak tray] event in tray?.beginPress(captureID,event:event) }
        effect.onUp={ [weak tray] event in tray?.mouseUp(with:event) }
        effect.onDrag={ [weak tray,weak effect] event,source in tray?.drag(with:event,from:source); if tray?.dragging == true { effect?.holding=false } }
        effect.frame=CGRect(origin:.zero,size:screen.frame.size); panel.contentView=effect
        panel.orderFrontRegardless()
        let start=CACurrentMediaTime(), duration=concept == .buffer ? 1.9 : 1.15
        let timer=Timer(timeInterval:1/60,repeats:true) { [weak self,weak tray] timer in
            guard let self else { timer.invalidate(); return }
            if let tray,let capture=tray.model.history.items.first(where:{$0.id==captureID}) {
                self.effect.updateDestination(from:tray,capture:capture)
            }
            self.effect.progress=clamp(CGFloat((CACurrentMediaTime()-start)/duration)); self.effect.needsDisplay=true
            self.effect.displayIfNeeded()
            let mouse=NSEvent.mouseLocation
            let point=CGPoint(x:mouse.x-screen.frame.minX,y:screen.frame.maxY-mouse.y)
            self.panel.ignoresMouseEvents = !self.effect.imagePath.contains(point,using:.winding) && !self.effect.holding
            onProgress(self.effect.progress)
            if self.effect.progress >= 1 && !self.effect.holding && tray?.dragging != true { timer.invalidate(); self.panel.orderOut(nil); completion() }
        }
        self.timer=timer; RunLoop.main.add(timer,forMode:.common)
    }
    func cancel() { timer?.invalidate(); timer=nil; panel.orderOut(nil) }
    deinit { timer?.invalidate(); panel.orderOut(nil) }
}
