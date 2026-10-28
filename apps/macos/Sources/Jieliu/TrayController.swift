import AppKit
import TrayCore

class TrayPanel:NSPanel {
    override var canBecomeKey:Bool { true }
    override var canBecomeMain:Bool { false }
}

final class TrayController {
    let model:AppModel
    var panels:[TrayPanel]=[]
    var views:[TrayView]=[]
    var screens:[NSScreen]=[]
    private var timer:Timer?
    private var observer:NSObjectProtocol?
    private var motionObserver:NSObjectProtocol?
    private var currentConcept:Concept
    private var generation=0
    private var deadlines:[Int:Double]=[:]
    private var effects:[UUID:EffectWindow]=[:]
    private var waiting:[(Capture,Capture?)]=[]
    private var animating=false
    private let playCaptureSound:()->Void
    let preview=PreviewController()

    var pendingCount:Int { waiting.count }
    init(model:AppModel,presentWindows:Bool=true,playCaptureSound:@escaping ()->Void = { NSSound(named:"Pop")?.play() }) {
        self.model=model; currentConcept=model.concept
        self.playCaptureSound=playCaptureSound
        if presentWindows { rebuild() }
        if presentWindows {
            observer=NotificationCenter.default.addObserver(forName:NSApplication.didChangeScreenParametersNotification,object:nil,queue:.main) { [weak self] _ in self?.rebuild() }
        }
        let timer=Timer(timeInterval:1/30,repeats:true) { [weak self] _ in self?.tick() }
        if presentWindows { self.timer=timer; RunLoop.main.add(timer,forMode:.common) }
        model.onChange = { [weak self] in self?.synchronizeState() }
        motionObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,object:nil,queue:.main) { [weak self] _ in self?.synchronizeState() }
        model.onEntryChange = { [weak self] in
            guard let self else { return }
            for (index,view) in self.views.enumerated() where !view.dragging && view.landing == nil && !self.preview.visible {
                view.expanded=false; self.deadlines[index]=0
                if self.panels[index].isKeyWindow { self.panels[index].resignKey() }
                view.needsDisplay=true
            }
        }
        model.onCapture = { [weak self] capture,old in
            guard let self else { return }
            if self.model.sound { self.playCaptureSound() }
            self.waiting.append((capture,old)); self.nextCapture()
        }
    }
    private func cancelEffects() {
        generation += 1
        effects.values.forEach { $0.cancel() }; effects.removeAll(); animating=false
        views.forEach { $0.cancelMotion(); $0.needsDisplay=true }
    }
    func synchronizeState() {
        let live=Set(model.history.items.map(\.id))
        waiting.removeAll { !live.contains($0.0.id) }
        if currentConcept != model.concept || !model.motionEnabled || effects.keys.contains(where:{!live.contains($0)}) {
            cancelEffects(); currentConcept=model.concept
            // Already-collected captures settle immediately; do not replay cancelled animations.
            waiting.removeAll()
        }
        views.forEach { $0.synchronizeState(); $0.needsDisplay=true }
        nextCapture()
    }

    func rebuild() {
        cancelEffects(); panels.forEach { $0.orderOut(nil) }; panels.removeAll(); views.removeAll(); deadlines.removeAll()
        screens=NSScreen.screens
        for (index,screen) in screens.enumerated() {
            let frame=CGRect(x:screen.frame.minX,y:screen.frame.maxY-270,width:screen.frame.width,height:270)
            let panel=TrayPanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            panel.isOpaque=false; panel.backgroundColor = .clear; panel.hasShadow=false; panel.hidesOnDeactivate=false
            panel.level=NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+1)
            panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
            panel.isMovable=false; panel.acceptsMouseMovedEvents=true
            let view=TrayView(model:model); view.frame=CGRect(origin:.zero,size:frame.size)
            view.top=max(32,screen.safeAreaInsets.top)/view.scale
            view.hardwareInset=screen.safeAreaInsets.top/view.scale
            view.onInteraction = { [weak self] in self?.deadlines[index]=CACurrentMediaTime()+4.6 }
            view.onPreview = { [weak self] id in
                guard let self else { return }
                self.preview.show(id:id,model:model,screen:screen)
            }
            panel.contentView=view; panel.orderFrontRegardless(); panels.append(panel); views.append(view)
        }
        animating=false; nextCapture()
    }
    func expand(on screen:NSScreen?=nil) {
        let index=screen.flatMap { screens.firstIndex(of:$0) } ?? screens.firstIndex(where:{$0.frame.contains(NSEvent.mouseLocation)}) ?? 0
        guard views.indices.contains(index) else { return }
        views[index].expanded=true; deadlines[index]=CACurrentMediaTime()+4.6
    }
    private func tick() {
        for (index,view) in views.enumerated() {
            let global=NSEvent.mouseLocation, screen=screens[index]
            let p=CGPoint(x:global.x-screen.frame.minX,y:screen.frame.maxY-global.y)
            let inside=screen.frame.contains(global) && view.interactive(at:p)
            panels[index].ignoresMouseEvents = !view.acceptsPointer(at:p) && !view.dragging
            view.hovering=inside
            if inside { view.expanded=true; deadlines[index]=CACurrentMediaTime()+1.8; view.pointer(p) }
            else { view.pointer(CGPoint(x:-100,y:-100)) }
            if !model.autoHide && model.entry == .capsule { view.expanded=true }
            else if !inside,!view.dragging,!preview.visible,view.landing == nil,CACurrentMediaTime()>(deadlines[index] ?? 0) {
                view.expanded=false
                if panels[index].isKeyWindow { panels[index].resignKey() }
            }
            view.tick()
        }
    }
    private func destination(for capture:Capture)->(Int,CGRect?) {
        if let r=capture.rect {
            let rect=CGRect(x:r.x,y:r.y,width:r.width,height:r.height)
            var best:(Int,CGFloat)=(0,0)
            for (i,s) in screens.enumerated() {
                let bounds=displayBounds(s),intersection=rect.intersection(bounds)
                let area=intersection.isNull ? 0 : intersection.width*intersection.height
                if area>best.1 { best=(i,area) }
            }
            if best.1>0 {
                let bounds=displayBounds(screens[best.0])
                return (best.0,rect.offsetBy(dx:-bounds.minX,dy:-bounds.minY))
            }
        }
        // Full-screen captures can still be assigned without private position metadata.
        let matches=screens.indices.filter { i in Int(screens[i].frame.width*screens[i].backingScaleFactor)==capture.width && Int(screens[i].frame.height*screens[i].backingScaleFactor)==capture.height }
        if matches.count == 1 { return(matches[0],CGRect(origin:.zero,size:screens[matches[0]].frame.size)) }
        return (screens.firstIndex(where:{$0.frame.contains(NSEvent.mouseLocation)}) ?? 0,nil)
    }
    private func displayBounds(_ screen:NSScreen)->CGRect {
        let number=screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return number.map { CGDisplayBounds($0.uint32Value) } ?? screen.frame
    }
    private func nextCapture() {
        guard !animating,!waiting.isEmpty,!views.isEmpty else { return }
        let (capture,old)=waiting.removeFirst()
        guard model.history.items.contains(where:{$0.id==capture.id}) else { nextCapture(); return }
        let (index,source)=destination(for:capture), view=views[index]
        animating=true; view.expanded=true; deadlines[index]=CACurrentMediaTime()+6.5
        if let old { view.evict(old) }
        view.needsDisplay=true; view.displayIfNeeded()
        guard let target=view.destinationRect(for:capture),let image=model.image(capture),model.motionEnabled else { view.cancelMotion(); animating=false; nextCapture(); return }
        view.landing=capture.id
        let scale=view.scale
        let end=CGRect(x:target.minX*scale,y:target.minY*scale,width:target.width*scale,height:target.height*scale)
        let fitted=model.concept == .buffer ? Ink.fit(image.size,in:end) : end
        let start=source ?? CGRect(x:screens[index].frame.width/2-90,y:max(80,view.top+20),width:180,height:112)
        if source == nil { view.toast(model.text("位置元数据不可用，已收纳截图","Screenshot collected; position unavailable")) }
        let token=generation
        effects[capture.id]=EffectWindow(screen:screens[index],image:image,source:start,target:fitted,concept:model.concept,top:view.top*scale,tray:view,captureID:capture.id,onProgress:{ [weak view] in view?.landingProgress=$0 }) { [weak self,weak view] in
            guard let self,self.generation == token else { return }
            view?.landing=nil; view?.arrived[capture.id]=CACurrentMediaTime(); view?.needsDisplay=true; self.effects[capture.id]=nil; self.animating=false
            self.nextCapture()
        }
    }
    deinit { timer?.invalidate(); if let observer { NotificationCenter.default.removeObserver(observer) }; if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) } }
}
