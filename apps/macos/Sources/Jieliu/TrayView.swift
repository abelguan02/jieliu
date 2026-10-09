import AppKit
import TrayCore

final class TrayView: NSView, NSDraggingSource {
    let model: AppModel
    var onPreview: ((UUID) -> Void)?
    var onInteraction: (() -> Void)?
    var expanded = false
    var openness: CGFloat = 0
    var spread: CGFloat = 0
    var hovering = false
    var hovered: UUID?
    var dragging = false
    var landing: UUID?
    var landingProgress:CGFloat=0
    var arrived:[UUID:Double]=[:]
    var top: CGFloat = 32
    var hardwareInset:CGFloat=0
    var capsuleRect:CGRect { CGRect(x:designWidth/2-38,y:hardwareInset>0 ? hardwareInset+4 : 6,width:76,height:24) }
    var lastFrame = CACurrentMediaTime()
    var layout: [UUID: CGRect] = [:]
    var orderedIDs: [UUID] = []
    var folderRect = CGRect.zero
    private var downEvent: NSEvent?
    private var downID: UUID?
    private var pasteboardProviders:[CapturePasteboard]=[]
    private var accessibleShots:[ShotAccessibility]=[]
    private var outgoing: (Capture, CGRect, Double)?
    private var message = ""
    private var messageUntil: Double = 0
    var scale: CGFloat { min(1, bounds.width / 1100) }
    var designWidth: CGFloat { bounds.width / scale }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(model: AppModel) { self.model = model; super.init(frame: .zero); setAccessibilityLabel(model.text("截图收纳托盘","Screenshot tray")) }
    required init?(coder: NSCoder) { fatalError() }

    func tick() {
        let now = CACurrentMediaTime(), dt = min(0.05, now-lastFrame); lastFrame = now
        arrived=arrived.filter { now-$0.value<0.5 }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let target: CGFloat = expanded ? 1 : 0
        let new = reduce ? target : openness + (target-openness)*min(1,dt*13)
        let targetSpread: CGFloat = hovering ? 1 : 0
        let newSpread = reduce ? targetSpread : spread + (targetSpread-spread)*min(1,dt*12)
        let moving = abs(new-openness)>0.0001 || abs(newSpread-spread)>0.0001
        openness = abs(new-target)<0.001 ? target : new
        spread = newSpread
        if moving || !model.selection.isEmpty || (expanded && model.concept == .buffer) || outgoing != nil || messageUntil > now || arrived.values.contains(where:{now-$0<0.42}) {
            needsDisplay = true
        }
    }

    func interactive(at point: CGPoint) -> Bool {
        let p = CGPoint(x: point.x/scale, y: point.y/scale)
        if !expanded { return model.entry == .capsule && capsuleRect.contains(p) }
        switch model.concept {
        case .buffer: return CGRect(x:designWidth/2-500,y:0,width:1000,height:top+140).contains(p)
        case .ruler: return p.y < top+175
        case .layers: return p.y < top+200
        }
    }
    func acceptsPointer(at point:CGPoint)->Bool {
        guard expanded,model.concept != .buffer else { return interactive(at:point) }
        let p=CGPoint(x:point.x/scale,y:point.y/scale)
        return folderRect.contains(p) || hit(p) != nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.saveGState(); c.scaleBy(x:scale,y:scale)
        layout.removeAll(); orderedIDs.removeAll()
        guard openness>0.001 else {
            if model.entry == .capsule { drawCapsule() }
            c.restoreGState(); return
        }
        let center = designWidth/2
        if model.concept == .buffer { drawBuffer(center) }
        else {
            if model.entry == .capsule {
                c.saveGState(); c.setAlpha(1-openness); drawCapsule(); c.restoreGState()
            }
            c.saveGState(); c.setAlpha(openness); c.translateBy(x:0,y:-(1-openness)*200)
            if model.concept == .ruler { drawRuler() } else { drawLayers(center) }
            c.restoreGState()
        }
        if let (capture, rect, start) = outgoing {
            let p = clamp(CGFloat((CACurrentMediaTime()-start)/0.65))
            if p >= 1 { outgoing = nil } else if let image = model.image(capture) {
                let end = CGRect(x:folderRect.midX,y:folderRect.midY,width:rect.width*0.1,height:rect.height*0.1)
                Ink.image(image,in:mixRect(rect,end,ease(p)),alpha:1-p)
            }
        }
        if messageUntil > CACurrentMediaTime() {
            let width = Ink.textWidth(message)+24
            Ink.box(CGRect(x:center-width/2,y:top+178,width:width,height:26),color:Ink.color(0x14161b,0.95),radius:8)
            Ink.text(message,center-width/2+12,top+184,size:11)
        }
        c.restoreGState()
    }

    private func drawCapsule() {
        Ink.box(capsuleRect,color:Ink.color(0x101216,0.97),radius:12,stroke:.white.withAlphaComponent(0.18))
        drawCapsuleContents()
    }
    private func drawCapsuleContents() {
        let r=CGRect(x:capsuleRect.minX+14,y:capsuleRect.minY+6,width:16,height:12)
        for (x,dx) in [(r.minX,CGFloat(1)),(r.maxX,CGFloat(-1))] {
            for (y,dy) in [(r.minY,CGFloat(1)),(r.maxY,CGFloat(-1))] {
                Ink.line(CGPoint(x:x+dx*4,y:y),CGPoint(x:x,y:y),color:Ink.guide,width:1.3)
                Ink.line(CGPoint(x:x,y:y),CGPoint(x:x,y:y+dy*4),color:Ink.guide,width:1.3)
            }
        }
        Ink.text("\(model.history.items.count)",capsuleRect.minX+46,capsuleRect.minY+5,size:12)
    }

    private func drawFolder(_ x: CGFloat, _ y: CGFloat, prefix: String = "") {
        let label = prefix + model.folderLabel + "  \(model.history.total)"
        let width = Ink.textWidth(label,size:10.5)+18
        folderRect = CGRect(x:x-width,y:y,width:width,height:20)
        Ink.box(folderRect,color:.white.withAlphaComponent(0.08),radius:6,stroke:.white.withAlphaComponent(0.14))
        Ink.text(label,folderRect.minX+8,y+3,size:10.5)
    }

    private func drawBuffer(_ center: CGFloat) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        if openness == 0 {
            if model.entry == .capsule { drawCapsule() }
            return
        }
        let end=CGRect(x:center-500,y:hardwareInset>0 ? 0 : 4,width:1000,height:top+134)
        let frame=mixRect(capsuleRect,end,openness)
        c.saveGState()
        if model.entry == .menuBarOnly { c.setAlpha(openness) }
        Ink.box(frame,color:.black,radius:mix(12,30,openness))
        c.restoreGState()
        if model.entry == .capsule {
            c.saveGState(); c.setAlpha(clamp(1-openness*4)); drawCapsuleContents(); c.restoreGState()
        }
        guard openness > 0.02 else { return }
        c.saveGState()
        NSBezierPath(roundedRect:frame,xRadius:mix(12,30,openness),yRadius:mix(12,30,openness)).addClip()
        c.setAlpha(clamp((openness-0.3)/0.7))
        let x = center-474
        Ink.text(model.text("截图缓冲区","SCREENSHOT BUFFER")+" · \(model.history.items.count)/8",x,10,size:11,color:Ink.color(0x7d838d))
        drawFolder(center+474,7,prefix:model.text("归档 → ","FLUSH → "))
        for index in 0..<8 {
            let left = x+CGFloat(index)*120, r = CGRect(x:left,y:top+10,width:108,height:68)
            let capture = model.history.slots[index].flatMap { id in model.history.items.first { $0.id == id } }
            Ink.box(r,color:Ink.color(0x0a0a0b),radius:4,stroke:capture == nil ? nil : .white.withAlphaComponent(0.14))
            if let capture {
                layout[capture.id] = r; orderedIDs.append(capture.id)
                if capture.id != landing, let image = model.image(capture) { Ink.image(image,in:Ink.fit(image.size,in:r),alpha:dragging && model.selection.contains(capture.id) ? 0.3 : 1) }
                if model.selection.contains(capture.id) { Ink.selection(r,time:CACurrentMediaTime()) }
                Ink.text(capture.id == landing ? (landingProgress > 0.74 ? model.text("写入","WRITE") : model.text("读取","READ")) : Ink.clock(capture.date),left+49,top+87,size:10.5,color:capture.id == landing ? Ink.green : Ink.color(0x6d727b))
                Ink.text(dimensions(capture),left,top+103,size:10.5,color:Ink.color(0x555a63))
            } else {
                let border=NSBezierPath(roundedRect:r.insetBy(dx:0.5,dy:0.5),xRadius:4,yRadius:4)
                border.setLineDash([3,3],count:2,phase:0); NSColor.white.withAlphaComponent(0.16).setStroke(); border.stroke()
                Ink.text("—",left+98,top+87,size:10.5,color:Ink.color(0x6d727b)); Ink.text(model.text("空","Empty"),left,top+103,size:10.5,color:Ink.color(0x555a63))
            }
            Ink.text(String(format:"0x%02X",index),left,top+87,size:10.5,color:Ink.color(0xcfd2d8))
            if index == model.history.writePointer && (Int(CACurrentMediaTime()*2)%2 == 0 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
                Ink.rgb(CGRect(x:left,y:top+81,width:108,height:2))
            }
        }
        c.restoreGState()
    }

    private func drawRuler() {
        Ink.box(CGRect(x:0,y:top,width:designWidth,height:22),color:Ink.color(0x0e1014,0.9))
        for x in stride(from:CGFloat(0),through:designWidth,by:10) {
            let height:CGFloat = Int(x)%100 == 0 ? 9 : (Int(x)%50 == 0 ? 6 : 3)
            Ink.line(CGPoint(x:x+0.5,y:top+22),CGPoint(x:x+0.5,y:top+22-height),color:.white.withAlphaComponent(0.32))
            if Int(x)%100 == 0 && x > 0 { Ink.text("\(Int(x))",x+3,top+3,size:9,color:.white.withAlphaComponent(0.5)) }
        }
        drawFolder(designWidth-8,top+1)
        var left: CGFloat = 24
        let maxWidth = min(176,(designWidth-48-140)/8)
        for capture in model.history.items {
            let r = Ink.fit(CGSize(width:capture.width,height:capture.height),in:CGRect(x:left,y:top+36,width:maxWidth,height:92))
            let shot = CGRect(x:left,y:top+36,width:r.width,height:r.height)
            layout[capture.id]=shot; orderedIDs.append(capture.id)
            Ink.line(CGPoint(x:shot.midX,y:top+22),CGPoint(x:shot.midX,y:shot.minY),color:Ink.guide)
            let diamond = NSBezierPath(); diamond.move(to:CGPoint(x:shot.midX,y:top+18)); diamond.line(to:CGPoint(x:shot.midX+4,y:top+22)); diamond.line(to:CGPoint(x:shot.midX,y:top+26)); diamond.line(to:CGPoint(x:shot.midX-4,y:top+22)); diamond.close(); Ink.guide.setFill(); diamond.fill()
            if capture.id != landing { drawShot(capture,shot) }
            let label=dimensions(capture)
            let clock=String(Ink.clock(capture.date).prefix(5))
            Ink.box(CGRect(x:left,y:shot.maxY+7,width:max(shot.width,CGFloat(label.count+6)*6.6+12),height:19),color:Ink.color(0x0a0c10,0.8),radius:4)
            Ink.text(label,left+6,shot.maxY+10,size:11)
            Ink.text(clock,left+12+CGFloat(label.count)*6.6,shot.maxY+10,size:11,color:.white.withAlphaComponent(0.5))
            if hovered == capture.id {
                Ink.box(CGRect(x:left,y:top,width:shot.width,height:22),color:Ink.guide.withAlphaComponent(0.16))
                Ink.text(label,left+5,top+5,size:10.5,color:Ink.guide)
            }
            left += shot.width+20
        }
    }

    private func drawLayers(_ center: CGFloat) {
        let band = CGRect(x:0,y:top,width:designWidth,height:200)
        NSGradient(starting:Ink.color(0x06070a,0.62),ending:.clear)?.draw(in:band,angle:90)
        drawFolder(designWidth-24,top+12)
        let gap = mix(24,min(128,(designWidth-180)/8),spread)
        let start = center-CGFloat(max(0,model.history.items.count-1))*gap/2
        let sorted = model.history.items.enumerated().reversed()
        for (index,capture) in sorted where capture.id != hovered { drawLayer(capture,index:index,start:start,gap:gap) }
        if let hovered, let index=model.history.items.firstIndex(where:{$0.id == hovered}) { drawLayer(model.history.items[index],index:index,start:start,gap:gap) }
        if spread < 0.5 {
            let label=model.history.items.first.map { model.text("\(model.history.items.count) 个图层 · 最新 \(Ink.clock($0.date))","\(model.history.items.count) layers · Latest \(Ink.clock($0.date))") } ?? model.text("没有图层","No layers")
            Ink.text(label,center-CGFloat(label.count)*3.7,top+154,size:11)
        }
    }

    private func drawLayer(_ capture: Capture,index: Int,start:CGFloat,gap:CGFloat) {
        let r = Ink.fit(CGSize(width:capture.width,height:capture.height),in:CGRect(x:start+CGFloat(index)*gap-92,y:top+20,width:184,height:112))
        let front = hovered == capture.id && spread > 0.5
        let sx:CGFloat = front ? 1.12 : cos(48 * .pi/180), sy:CGFloat = front ? 1.12 : cos(16 * .pi/180)
        let shear:CGFloat = front ? 0 : sin(16 * .pi/180)*sin(48 * .pi/180)
        layout[capture.id] = CGRect(x:r.midX-r.width*sx/2,y:r.midY-r.height*sy/2,width:r.width*sx,height:r.height*sy)
        orderedIDs.append(capture.id)
        guard let c=NSGraphicsContext.current?.cgContext else { return }
        c.saveGState(); c.translateBy(x:r.midX,y:r.midY); c.concatenate(CGAffineTransform(a:sx,b:shear,c:0,d:sy,tx:0,ty:0))
        if capture.id != landing { drawShot(capture,CGRect(x:-r.width/2,y:-r.height/2,width:r.width,height:r.height)) }
        c.restoreGState()
        if spread > 0.5 {
            let label=model.text("截屏 ","Capture ") + Ink.clock(capture.date).replacingOccurrences(of:":",with:".")
            Ink.box(CGRect(x:r.midX-65,y:top+142,width:130,height:20),color:Ink.color(0x0c0e12,0.85),radius:5)
            Ink.checker(CGRect(x:r.midX-59,y:top+148,width:8,height:8),cell:4)
            Ink.text(label,r.midX-45,top+146,size:10.5)
        }
    }

    private func drawShot(_ capture:Capture,_ rect:CGRect) {
        NSGraphicsContext.saveGraphicsState()
        let shadow=NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.45); shadow.shadowBlurRadius=20; shadow.shadowOffset=NSSize(width:0,height:-10); shadow.set()
        Ink.box(rect,color:.black,radius:3,stroke:hovered == capture.id && model.concept == .ruler ? Ink.guide : .white.withAlphaComponent(0.45))
        NSGraphicsContext.restoreGraphicsState()
        if let image=model.image(capture) { Ink.image(image,in:rect,alpha:openness*(dragging && model.selection.contains(capture.id) ? 0.3 : 1)) }
        if model.selection.contains(capture.id) { Ink.selection(rect,time:CACurrentMediaTime()) }
    }

    func evict(_ capture:Capture) { if let rect=layout[capture.id] { outgoing=(capture,rect,CACurrentMediaTime()) } }
    private func dimensions(_ capture:Capture)->String {
        let p=arrived[capture.id].map { ease(CGFloat((CACurrentMediaTime()-$0)/0.42)) } ?? 1
        return "\(Int(CGFloat(capture.width)*p))×\(Int(CGFloat(capture.height)*p))"
    }
    /// Geometry must exist before the first expanded frame is painted.
    func destinationRect(for capture:Capture)->CGRect? {
        switch model.concept {
        case .buffer:
            guard let index=model.history.slots.firstIndex(of:capture.id) else { return nil }
            return CGRect(x:designWidth/2-474+CGFloat(index)*120,y:top+10,width:108,height:68)
        case .ruler:
            var left:CGFloat=24
            for item in model.history.items {
                let r=Ink.fit(CGSize(width:item.width,height:item.height),in:CGRect(x:left,y:top+36,width:min(176,(designWidth-188)/8),height:92))
                if item.id == capture.id { return CGRect(x:left,y:top+36,width:r.width,height:r.height) }
                left += r.width+20
            }
            return nil
        case .layers:
            guard let index=model.history.items.firstIndex(where:{$0.id==capture.id}) else { return nil }
            let gap=mix(24,min(128,(designWidth-180)/8),spread)
            let start=designWidth/2-CGFloat(max(0,model.history.items.count-1))*gap/2
            let r=Ink.fit(CGSize(width:capture.width,height:capture.height),in:CGRect(x:start+CGFloat(index)*gap-92,y:top+20,width:184,height:112))
            let width=r.width*cos(48 * .pi/180)
            return CGRect(x:r.midX-width/2,y:r.minY,width:width,height:r.height)
        }
    }
    func toast(_ text:String) { message=text; messageUntil=CACurrentMediaTime()+2.4; needsDisplay=true }
    func hit(_ p:CGPoint) -> UUID? { orderedIDs.reversed().first { layout[$0]?.contains(p) == true } }
    func pointer(_ point:CGPoint) {
        let value = hit(CGPoint(x:point.x/scale,y:point.y/scale))
        if hovered != value { hovered=value; needsDisplay=true }
    }

    override func mouseDown(with event:NSEvent) {
        onInteraction?()
        let raw=convert(event.locationInWindow,from:nil), p=CGPoint(x:raw.x/scale,y:raw.y/scale)
        if expanded && folderRect.contains(p) { model.openFolder(); return }
        guard let id=hit(p), expanded else { expanded=true; return }
        window?.makeKey(); window?.makeFirstResponder(self)
        downEvent=event; downID=id
        if event.clickCount == 2 { onPreview?(id); return }
        needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        defer { downEvent=nil; downID=nil }
        guard let id=downID,!dragging else { return }
        if event.modifierFlags.intersection([.shift,.command,.control]).isEmpty { model.selection=[id] }
        else if model.selection.contains(id) { model.selection.remove(id) } else { model.selection.insert(id) }
        needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        guard let id=downID,let down=downEvent,!dragging else { return }
        guard hypot(event.locationInWindow.x-down.locationInWindow.x,event.locationInWindow.y-down.locationInWindow.y)>5 else { return }
        if !model.selection.contains(id) { model.selection=[id] }
        let captures=model.history.items.filter { model.selection.contains($0.id) && FileManager.default.fileExists(atPath:$0.url.path) }
        let p=convert(event.locationInWindow,from:nil)
        pasteboardProviders=captures.map { CapturePasteboard(url:$0.url) }
        let items=captures.enumerated().map { index,capture -> NSDraggingItem in
            let writer=pasteboardProviders[index].item()
            let item=NSDraggingItem(pasteboardWriter:writer)
            let image=model.image(capture)
            let rect=Ink.fit(image?.size ?? CGSize(width:170,height:110),in:CGRect(x:p.x-85+CGFloat(index*5),y:p.y-55+CGFloat(index*5),width:170,height:110))
            item.setDraggingFrame(rect,contents:image)
            return item
        }
        guard !items.isEmpty else { return }
        dragging=true; needsDisplay=true
        let session=beginDraggingSession(with:items,event:event,source:self)
        session.animatesToStartingPositionsOnCancelOrFail=true; session.draggingFormation = .pile
        downID=nil; downEvent=nil
    }
    func draggingSession(_ session:NSDraggingSession,sourceOperationMaskFor context:NSDraggingContext)->NSDragOperation { .copy }
    func draggingSession(_ session:NSDraggingSession,endedAt screenPoint:NSPoint,operation:NSDragOperation) {
        dragging=false; needsDisplay=true; onInteraction?()
        if operation.contains(.copy) { toast(model.text("已拷贝 \(model.selection.count) 张截图","Copied \(model.selection.count) screenshots")) }
    }
    override func keyDown(with event:NSEvent) {
        onInteraction?()
        switch event.keyCode {
        case 49: if let id=model.history.items.first(where:{model.selection.contains($0.id)})?.id ?? hovered { onPreview?(id) }
        case 51,117: let count=model.selection.count; model.removeSelection(); toast(model.text("已移出 \(count) 张，文件仍保留","Removed \(count) from tray; files kept"))
        case 53: model.selection.removeAll(); window?.resignKey(); needsDisplay=true
        case 123,124:
            let ids=model.concept == .buffer ? model.history.slots.compactMap{$0} : model.history.items.map(\.id)
            guard !ids.isEmpty else { return }
            let current=ids.firstIndex(where:{model.selection.contains($0)}) ?? (event.keyCode == 124 ? -1 : 0)
            let next=(current+(event.keyCode == 124 ? 1 : -1)+ids.count)%ids.count
            if !event.modifierFlags.contains(.shift) { model.selection.removeAll() }
            model.selection.insert(ids[next]); needsDisplay=true
        default:
            if event.modifierFlags.contains(.command),event.charactersIgnoringModifiers == "a" { model.selection=Set(model.history.items.map(\.id)); needsDisplay=true }
            else if event.modifierFlags.contains(.command),event.charactersIgnoringModifiers == "c" {
                let urls=model.history.items.filter { model.selection.contains($0.id) }.map { $0.url as NSURL }
                NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(urls); toast(model.text("已拷贝 \(urls.count) 张截图","Copied \(urls.count) screenshots"))
            } else if event.modifierFlags.intersection([.command,.control,.option]).isEmpty,let key=event.charactersIgnoringModifiers?.uppercased(),let concept=Concept(rawValue:key) { model.concept=concept }
            else { super.keyDown(with:event) }
        }
    }
    override func accessibilityChildren()->[Any]? {
        guard expanded else {
            guard model.entry == .capsule else { return [] }
            let element=ShotAccessibility()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(model.text("展开截图托盘","Show screenshot tray"))
            element.setAccessibilityParent(self)
            let r=capsuleRect
            let local=CGRect(x:r.minX*scale,y:r.minY*scale,width:r.width*scale,height:r.height*scale)
            if let window { element.setAccessibilityFrame(window.convertToScreen(convert(local,to:nil))) }
            element.press = { [weak self] in self?.expanded=true; self?.onInteraction?(); self?.needsDisplay=true }
            accessibleShots=[element]; return accessibleShots
        }
        accessibleShots=model.history.items.compactMap { capture in
            guard let r=layout[capture.id] else { return nil }
            let element=ShotAccessibility()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(model.text("\(capture.url.lastPathComponent)，\(capture.width) 乘 \(capture.height) 像素","\(capture.url.lastPathComponent), \(capture.width) by \(capture.height) pixels"))
            element.setAccessibilityHelp(model.text("按下以选中，空格预览，Delete 从托盘移出并保留文件。","Press to select, Space to preview, Delete to remove from the tray while keeping the file."))
            element.setAccessibilityParent(self)
            let local=CGRect(x:r.minX*scale,y:r.minY*scale,width:r.width*scale,height:r.height*scale)
            if let window { element.setAccessibilityFrame(window.convertToScreen(convert(local,to:nil))) }
            element.press = { [weak self] in
                self?.model.selection=[capture.id]; self?.window?.makeKey(); self?.window?.makeFirstResponder(self); self?.needsDisplay=true
            }
            return element
        }
        return accessibleShots
    }
}

final class ShotAccessibility:NSAccessibilityElement {
    var press:(()->Void)?
    override func accessibilityPerformPress()->Bool { press?(); return true }
}
