import AppKit
import TrayCore

final class TrayView: NSView, NSDraggingSource, NSMenuDelegate {
    let model: AppModel
    var onPreview: ((UUID) -> Void)?
    var onInteraction: (() -> Void)?
    var expanded = false
    var openness: CGFloat = 0
    var spread: CGFloat = 0
    var hovering = false
    var hovered: UUID?
    var dragging = false
    private(set) var menuOpen = false
    var landing: UUID?
    var landingProgress:CGFloat=0
    var arrived:[UUID:Double]=[:]
    var top: CGFloat = 32
    var hardwareInset:CGFloat=0
    var capsuleRect:CGRect { CGRect(x:designWidth/2-38,y:hardwareInset>0 ? hardwareInset+4 : 6,width:76,height:24) }
    var lastFrame = CACurrentMediaTime()
    var layout: [UUID: CGRect] = [:]
    var orderedIDs: [UUID] = []
    var hitPaths:[UUID:CGPath]=[:]
    private var previousConcept:Concept?
    var folderRect = CGRect.zero
    private var downEvent: NSEvent?
    private var downID: UUID?
    private var keyboardCurrent:UUID?
    private var pasteboardProviders:[CapturePasteboard]=[]
    private var accessibleShots:[ShotAccessibility]=[]
    private var outgoing: (Capture, CGRect, Double)?
    private(set) var message = ""
    private let writeClipboard:([NSPasteboardWriting])->Bool
    private var messageUntil: Double = 0
    var scale: CGFloat { min(1, bounds.width / 1100) }
    var designWidth: CGFloat { bounds.width / scale }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(model: AppModel, writeClipboard:@escaping ([NSPasteboardWriting])->Bool = { items in
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects(items)
    }) {
        self.model = model; self.writeClipboard = writeClipboard
        super.init(frame: .zero); setAccessibilityLabel(model.text("截图收纳托盘","Screenshot tray"))
    }
    required init?(coder: NSCoder) { fatalError() }

    func tick() {
        let now = CACurrentMediaTime(), dt = min(0.05, now-lastFrame); lastFrame = now
        arrived=arrived.filter { now-$0.value<0.5 }
        synchronizeState()
        let reduce = !model.motionEnabled
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
        if hit(p) != nil { return true }
        if !expanded { return model.entry == .capsule && capsuleRect.contains(p) }
        switch model.concept {
        case .buffer:
            let end=CGRect(x:designWidth/2-500,y:hardwareInset>0 ? 0 : 4,width:1000,height:top+134)
            return mixRect(capsuleRect,end,openness).contains(p)
        case .ruler: return p.y < top+175
        case .layers: return p.y < top+200
        }
    }
    func acceptsPointer(at point:CGPoint)->Bool {
        if hit(CGPoint(x:point.x/scale,y:point.y/scale)) != nil { return true }
        guard expanded,model.concept != .buffer else { return interactive(at:point) }
        let p=CGPoint(x:point.x/scale,y:point.y/scale)
        let folderPoint=CGPoint(x:p.x,y:p.y+(model.concept == .buffer ? 0 : (1-openness)*200))
        return (visibleContent(at:p) && folderRect.contains(folderPoint)) || hit(p) != nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        c.saveGState(); c.scaleBy(x:scale,y:scale)
        synchronizeState()
        layout.removeAll(); orderedIDs.removeAll(); hitPaths.removeAll()
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
                layout[capture.id] = r; orderedIDs.append(capture.id); registerHit(capture.id,CGPath(rect:r,transform:nil))
                if capture.id != landing, let image = model.image(capture) { Ink.image(image,in:Ink.fit(image.size,in:r),alpha:dragging && model.selection.contains(capture.id) ? 0.3 : 1) }
                if model.history.pinnedIDs.contains(capture.id) { Ink.pin(r) }
                if model.selection.contains(capture.id) { Ink.selection(r,time:model.motionEnabled ? CACurrentMediaTime() : 0) }
                Ink.text(capture.id == landing ? (landingProgress > 0.74 ? model.text("写入","WRITE") : model.text("读取","READ")) : Ink.clock(capture.date),r.maxX,top+87,size:10.5,color:capture.id == landing ? Ink.green : Ink.color(0x6d727b),alignment:.right)
                Ink.text(dimensions(capture),left,top+103,size:10.5,color:Ink.color(0x555a63))
            } else {
                let border=NSBezierPath(roundedRect:r.insetBy(dx:0.5,dy:0.5),xRadius:4,yRadius:4)
                border.setLineDash([3,3],count:2,phase:0); NSColor.white.withAlphaComponent(0.16).setStroke(); border.stroke()
                Ink.text("—",r.maxX,top+87,size:10.5,color:Ink.color(0x6d727b),alignment:.right); Ink.text(model.text("空","Empty"),left,top+103,size:10.5,color:Ink.color(0x555a63))
            }
            Ink.text(String(format:"0x%02X",index),left,top+87,size:10.5,color:Ink.color(0xcfd2d8))
            if index == model.history.nextWriteSlot && (Int(CACurrentMediaTime()*2)%2 == 0 || !model.motionEnabled) {
                Ink.rgb(CGRect(x:left,y:top+81,width:108,height:2))
            }
        }
        c.restoreGState()
    }

    func rulerLayout() -> [(capture:Capture,shot:CGRect,caption:CGRect)] {
        var left:CGFloat=24
        let maxWidth=min(176,(designWidth-48-140)/8)
        return model.history.items.map { capture in
            let fitted=Ink.fit(CGSize(width:capture.width,height:capture.height),in:CGRect(x:left,y:top+36,width:maxWidth,height:92))
            let shot=CGRect(x:left,y:top+36,width:fitted.width,height:fitted.height)
            let label="\(capture.width)×\(capture.height)"
            let clock=String(Ink.clock(capture.date).prefix(5))
            let captionWidth=max(shot.width,min(maxWidth,Ink.textWidth(label)+Ink.textWidth(clock)+18))
            let caption=CGRect(x:left,y:shot.maxY+7,width:captionWidth,height:19)
            left += caption.width+20
            return (capture,shot,caption)
        }
    }

    private func drawRuler() {
        Ink.box(CGRect(x:0,y:top,width:designWidth,height:22),color:Ink.color(0x0e1014,0.9))
        drawFolder(designWidth-8,top+1)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:CGRect(x:0,y:top,width:max(0,folderRect.minX-8),height:22)).addClip()
        for x in stride(from:CGFloat(0),through:designWidth,by:10) {
            let height:CGFloat = Int(x)%100 == 0 ? 9 : (Int(x)%50 == 0 ? 6 : 3)
            Ink.line(CGPoint(x:x+0.5,y:top+22),CGPoint(x:x+0.5,y:top+22-height),color:.white.withAlphaComponent(0.32))
            if Int(x)%100 == 0 && x > 0 { Ink.text("\(Int(x))",x+3,top+3,size:9,color:.white.withAlphaComponent(0.5)) }
        }
        NSGraphicsContext.restoreGraphicsState()
        for (capture,shot,caption) in rulerLayout() {
            let left=shot.minX
            layout[capture.id]=shot; orderedIDs.append(capture.id)
            if capture.id != landing { registerHit(capture.id,CGPath(rect:shot,transform:nil)) }
            Ink.line(CGPoint(x:shot.midX,y:top+22),CGPoint(x:shot.midX,y:shot.minY),color:Ink.guide)
            let diamond = NSBezierPath(); diamond.move(to:CGPoint(x:shot.midX,y:top+18)); diamond.line(to:CGPoint(x:shot.midX+4,y:top+22)); diamond.line(to:CGPoint(x:shot.midX,y:top+26)); diamond.line(to:CGPoint(x:shot.midX-4,y:top+22)); diamond.close(); Ink.guide.setFill(); diamond.fill()
            if capture.id != landing { drawShot(capture,shot) }
            let label=dimensions(capture)
            let clock=String(Ink.clock(capture.date).prefix(5))
            Ink.box(caption,color:Ink.color(0x0a0c10,0.8),radius:4)
            let clockWidth=Ink.textWidth(clock)
            Ink.text(label,in:CGRect(x:caption.minX+6,y:caption.minY+3,width:caption.width-clockWidth-18,height:16))
            Ink.text(clock,caption.maxX-6,caption.minY+3,size:11,color:.white.withAlphaComponent(0.5),alignment:.right)
            if hovered == capture.id {
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(rect:CGRect(x:0,y:top,width:max(0,folderRect.minX-8),height:22)).addClip()
                Ink.box(CGRect(x:left,y:top,width:caption.width,height:22),color:Ink.guide.withAlphaComponent(0.16))
                Ink.text(label,in:CGRect(x:left+5,y:top+3,width:caption.width-10,height:16),size:10.5,color:Ink.guide)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }

    func layerGap()->CGFloat {
        mix(24,min(142,(designWidth-48)/CGFloat(max(1,model.history.items.count))),spread)
    }
    func layerCaptionRect(center:CGFloat,gap:CGFloat)->CGRect {
        let width=model.history.items.count == 1 ? 130 : min(130,max(0,gap-12))
        return CGRect(x:center-width/2,y:top+142,width:width,height:20)
    }
    private func drawLayers(_ center: CGFloat) {
        let band = CGRect(x:0,y:top,width:designWidth,height:200)
        NSGradient(starting:Ink.color(0x06070a,0.62),ending:.clear)?.draw(in:band,angle:90)
        drawFolder(designWidth-24,7)
        let sorted=model.history.items.reversed()
        for capture in sorted where capture.id != hovered { drawLayer(capture) }
        if let hovered,let capture=model.history.items.first(where:{$0.id==hovered}) { drawLayer(capture) }
        if spread < 0.5 {
            let label=model.history.items.first.map { model.text("\(model.history.items.count) 个图层 · 最新 \(Ink.clock($0.date))","\(model.history.items.count) layers · Latest \(Ink.clock($0.date))") } ?? model.text("没有图层","No layers")
            Ink.text(label,center,top+154,size:11,alignment:.center)
        }
    }

    func layerPlacement(for capture:Capture)->LayerPlacement? {
        guard let index=model.history.items.firstIndex(where:{$0.id==capture.id}) else { return nil }
        let gap=layerGap(), start=designWidth/2-CGFloat(max(0,model.history.items.count-1))*gap/2
        let rect=Ink.fit(CGSize(width:capture.width,height:capture.height),in:CGRect(x:start+CGFloat(index)*gap-92,y:top+20,width:184,height:112))
        return LayerPlacement(rect:rect,front:hovered==capture.id && spread>0.5)
    }
    private func drawLayer(_ capture: Capture) {
        guard let placement=layerPlacement(for:capture) else { return }
        let r=placement.rect
        layout[capture.id]=placement.path.boundingBox
        orderedIDs.append(capture.id)
        if capture.id != landing {
            registerHit(capture.id,placement.path)
        }
        guard let c=NSGraphicsContext.current?.cgContext else { return }
        c.saveGState(); c.concatenate(placement.transform)
        if capture.id != landing { drawShot(capture,placement.localRect) }
        c.restoreGState()
        if spread > 0.5 && capture.id != landing {
            let caption=layerCaptionRect(center:r.midX,gap:layerGap())
            let clock=Ink.clock(capture.date).replacingOccurrences(of:":",with:".")
            let fullLabel=model.text("截屏 ","Capture ")+clock
            let label=Ink.textWidth(fullLabel,size:10.5) <= caption.width-26 ? fullLabel : clock
            Ink.box(caption,color:Ink.color(0x0c0e12,0.85),radius:5)
            Ink.checker(CGRect(x:caption.minX+6,y:caption.minY+6,width:8,height:8),cell:4)
            Ink.text(label,in:CGRect(x:caption.minX+20,y:caption.minY+4,width:caption.width-26,height:16),size:10.5)
        }
    }

    private func drawShot(_ capture:Capture,_ rect:CGRect) {
        NSGraphicsContext.saveGraphicsState()
        let shadow=NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.45); shadow.shadowBlurRadius=20; shadow.shadowOffset=NSSize(width:0,height:-10); shadow.set()
        Ink.box(rect,color:.black,radius:3,stroke:hovered == capture.id && model.concept == .ruler ? Ink.guide : .white.withAlphaComponent(0.45))
        NSGraphicsContext.restoreGraphicsState()
        if let image=model.image(capture) { Ink.image(image,in:rect,alpha:openness*(dragging && model.selection.contains(capture.id) ? 0.3 : 1)) }
        if model.history.pinnedIDs.contains(capture.id) { Ink.pin(rect) }
        if model.selection.contains(capture.id) { Ink.selection(rect,time:model.motionEnabled ? CACurrentMediaTime() : 0) }
    }

    func evict(_ capture:Capture) { if model.motionEnabled,let rect=layout[capture.id] { outgoing=(capture,rect,CACurrentMediaTime()) } }
    func cancelMotion() {
        landing=nil; landingProgress=0; arrived.removeAll(); outgoing=nil
        openness=expanded ? 1 : 0; spread=hovering ? 1 : 0
    }
    func synchronizeState() {
        let live=Set(model.history.items.map(\.id))
        if let downID,!live.contains(downID) { self.downID=nil; downEvent=nil }
        if let hovered,!live.contains(hovered) { self.hovered=nil }
        if let keyboardCurrent,!live.contains(keyboardCurrent) { self.keyboardCurrent=nil }
        if previousConcept != model.concept {
            if previousConcept != nil { cancelMotion() }
            downID=nil; downEvent=nil; hitPaths.removeAll(); outgoing=nil; hovered=nil
            keyboardCurrent=nil
            previousConcept=model.concept
        }
        if !model.motionEnabled { cancelMotion() }
    }
    private func registerHit(_ id:UUID,_ path:CGPath) {
        var shift=CGAffineTransform(translationX:0,y:model.concept == .buffer ? 0 : -(1-openness)*200)
        hitPaths[id]=path.copy(using:&shift)
    }
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
            return rulerLayout().first(where:{$0.capture.id==capture.id})?.shot.offsetBy(dx:0,dy:-(1-openness)*200)
        case .layers:
            return layerPlacement(for:capture)?.path.boundingBox.offsetBy(dx:0,dy:-(1-openness)*200)
        }
    }
    func toast(_ text:String,duration:TimeInterval=2.4) { message=text; messageUntil=CACurrentMediaTime()+duration; needsDisplay=true }
    func visibleContent(at p:CGPoint)->Bool {
        guard openness>0.001,CGRect(x:0,y:0,width:designWidth,height:bounds.height/scale).contains(p) else { return false }
        if model.concept == .buffer {
            guard openness>0.3 else { return false }
            let end=CGRect(x:designWidth/2-500,y:hardwareInset>0 ? 0 : 4,width:1000,height:top+134)
            let clip=CGPath(roundedRect:mixRect(capsuleRect,end,openness),cornerWidth:mix(12,30,openness),cornerHeight:mix(12,30,openness),transform:nil)
            guard clip.contains(p) else { return false }
        }
        return true
    }
    func hit(_ p:CGPoint) -> UUID? {
        guard visibleContent(at:p) else { return nil }
        return orderedIDs.reversed().first { id in model.history.items.contains(where:{$0.id==id}) && hitPaths[id]?.contains(p) == true }
    }
    func pointer(_ point:CGPoint) {
        let value = hit(CGPoint(x:point.x/scale,y:point.y/scale))
        if hovered != value { hovered=value; needsDisplay=true }
    }

    override func mouseDown(with event:NSEvent) {
        synchronizeState(); downID=nil; downEvent=nil
        onInteraction?()
        let raw=convert(event.locationInWindow,from:nil), p=CGPoint(x:raw.x/scale,y:raw.y/scale)
        let folderPoint=CGPoint(x:p.x,y:p.y+(model.concept == .buffer ? 0 : (1-openness)*200))
        if visibleContent(at:p) && folderRect.contains(folderPoint) { model.openFolder(); return }
        guard let id=hit(p) else { expanded=true; return }
        beginPress(id,event:event)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        return pinMenu(for: hit(CGPoint(x: point.x / scale, y: point.y / scale)))
    }
    func pinMenu(for id: UUID?) -> NSMenu? {
        guard let id, model.history.items.contains(where: { $0.id == id }) else { return nil }
        downID = nil; downEvent = nil
        if !model.selection.contains(id) { model.selection = [id] }
        keyboardCurrent = id; onInteraction?(); needsDisplay = true
        let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = self
        let title = model.selectionIsPinned ? model.text("取消固定", "Unpin") : model.text("固定", "Pin")
        let item = NSMenuItem(title: title, action: #selector(applyPinMenu(_:)), keyEquivalent: "")
        item.representedObject = !model.selectionIsPinned
        item.target = self; menu.addItem(item)
        return menu
    }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; onInteraction?() }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; onInteraction?() }
    @objc func togglePins(_ sender: Any?) { model.toggleSelectedPins(); needsDisplay = true }
    @objc func applyPinMenu(_ item: NSMenuItem) {
        model.setSelectedPins(item.representedObject as! Bool); needsDisplay = true
    }
    func beginPress(_ id:UUID,event:NSEvent) {
        guard model.history.items.contains(where:{$0.id==id}) else { return }
        expanded=true; onInteraction?()
        window?.makeKey(); window?.makeFirstResponder(self)
        downEvent=event; downID=id
        keyboardCurrent=id
        if event.clickCount == 2 { downID=nil; downEvent=nil; onPreview?(id); return }
        needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        defer { downEvent=nil; downID=nil }
        guard let id=downID,!dragging,model.history.items.contains(where:{$0.id==id}) else { return }
        if event.modifierFlags.intersection([.shift,.command,.control]).isEmpty { model.selection=[id] }
        else if model.selection.contains(id) { model.selection.remove(id) } else { model.selection.insert(id) }
        needsDisplay=true
    }
    override func mouseDragged(with event:NSEvent) {
        drag(with:event,from:self)
    }
    func drag(with event:NSEvent,from source:NSView) {
        guard let id=downID,let down=downEvent,!dragging,model.history.items.contains(where:{$0.id==id}) else { return }
        guard hypot(event.locationInWindow.x-down.locationInWindow.x,event.locationInWindow.y-down.locationInWindow.y)>5 else { return }
        if !model.selection.contains(id) { model.selection=[id] }
        let captures=model.history.items.filter { model.selection.contains($0.id) && FileManager.default.fileExists(atPath:$0.url.path) }
        let p=source.convert(event.locationInWindow,from:nil)
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
        let session=source.beginDraggingSession(with:items,event:event,source:self)
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
        case 51,117:
            let count=model.history.items.filter { model.selection.contains($0.id) }.count
            guard count>0 else { return }
            model.removeSelection(); toast(model.text("已移出 \(count) 张，文件仍保留","Removed \(count) from tray; files kept"))
        case 53: model.selection.removeAll(); keyboardCurrent=nil; window?.resignKey(); needsDisplay=true
        case 123,124:
            let ids=model.concept == .buffer ? model.history.slots.compactMap{$0} : model.history.items.map(\.id)
            guard !ids.isEmpty else { return }
            let current=keyboardCurrent.flatMap { id in model.selection.contains(id) ? ids.firstIndex(of:id) : nil }
                ?? ids.firstIndex(where:{model.selection.contains($0)}) ?? (event.keyCode == 124 ? -1 : 0)
            let next=(current+(event.keyCode == 124 ? 1 : -1)+ids.count)%ids.count
            if !event.modifierFlags.contains(.shift) { model.selection.removeAll() }
            keyboardCurrent=ids[next]; model.selection.insert(ids[next]); needsDisplay=true
        default:
            if event.modifierFlags.contains(.command),event.charactersIgnoringModifiers == "a" { model.selection=Set(model.history.items.map(\.id)); needsDisplay=true }
            else if event.modifierFlags.contains(.command),event.charactersIgnoringModifiers == "c" {
                let urls=model.history.items.filter { model.selection.contains($0.id) && FileManager.default.fileExists(atPath:$0.url.path) }.map(\.url)
                guard !urls.isEmpty else { return }
                guard writeClipboard(CapturePasteboard.copyItems(urls)) else {
                    model.lastError=model.text("无法写入剪贴板，请重试。","Could not write to the clipboard. Please try again.")
                    return
                }
                toast(model.text("已拷贝 \(urls.count) 张截图","Copied \(urls.count) screenshots"))
            } else if event.modifierFlags.intersection([.command,.control,.option]).isEmpty,event.charactersIgnoringModifiers?.lowercased() == "p" { togglePins(nil) }
            else if event.modifierFlags.intersection([.command,.control,.option]).isEmpty,let key=event.charactersIgnoringModifiers?.uppercased(),let concept=Concept(rawValue:key) { model.concept=concept }
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
            element.selected = { [weak self] in self?.model.selection.contains(capture.id) ?? false }
            element.pinStatus = { [weak self] in
                guard let self else { return nil }
                return self.model.history.pinnedIDs.contains(capture.id) ? self.model.text("已固定", "Pinned") : nil
            }
            element.setAccessibilityLabel(model.text("\(capture.url.lastPathComponent)，\(capture.width) 乘 \(capture.height) 像素","\(capture.url.lastPathComponent), \(capture.width) by \(capture.height) pixels"))
            element.setAccessibilityHelp(model.text("按下以选中，P 固定或取消固定，空格预览，Delete 移出并保留文件。","Press to select, P to pin or unpin, Space to preview, Delete to remove while keeping the file."))
            element.setAccessibilityParent(self)
            let local=CGRect(x:r.minX*scale,y:r.minY*scale,width:r.width*scale,height:r.height*scale)
            if let window { element.setAccessibilityFrame(window.convertToScreen(convert(local,to:nil))) }
            element.press = { [weak self] in
                guard self?.model.history.items.contains(where:{$0.id==capture.id}) == true else { return }
                self?.model.selection=[capture.id]; self?.keyboardCurrent=capture.id; self?.window?.makeKey(); self?.window?.makeFirstResponder(self); self?.needsDisplay=true
            }
            return element
        }
        return accessibleShots
    }
}

final class ShotAccessibility:NSAccessibilityElement {
    var press:(()->Void)?
    var selected:(()->Bool)?
    var pinStatus:(()->String?)?
    override func accessibilityValue()->Any? { pinStatus?() }
    override func isAccessibilitySelected()->Bool { selected?() ?? false }
    override func accessibilityPerformPress()->Bool { press?(); return true }
}
