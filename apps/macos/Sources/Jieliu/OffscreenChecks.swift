import AppKit
import TrayCore

/// No NSWindow construction, app activation, input injection, clipboard or user screenshots.
enum OffscreenChecks {
    static func paint(_ view:NSView) {
        let image=NSImage(size:view.bounds.size)
        image.lockFocusFlipped(true); view.draw(view.bounds); image.unlockFocus()
    }
    static func event(_ point:CGPoint,flags:NSEvent.ModifierFlags=[])->NSEvent {
        NSEvent.mouseEvent(with:.leftMouseDown,location:point,modifierFlags:flags,timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1)!
    }
    static func run() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("jieliu-offscreen-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let suite="app.jieliu.offscreen."+UUID().uuidString, defaults=UserDefaults(suiteName:suite)!
        defer { try? FileManager.default.removeItem(at:root); defaults.removePersistentDomain(forName:suite) }
        let model=AppModel(demo:true,preferences:defaults)
        model.reduceMotion={false}
        AlignmentChecks.run(model)
        ReviewRegressionChecks.run(model)
        try CaptureInputChecks.run(root:root,preferences:defaults)
        try CaptureRegressionChecks.run(root:root,preferences:defaults)
        try CopyRoutingChecks.run(root:root,preferences:defaults)
        try PinChecks.run(root:root)
        let bytes=DemoSupport.fixture(0)
        var shots:[Capture]=[]
        for i in 0..<40 {
            let url=root.appendingPathComponent("\(i).png"); try bytes.write(to:url)
            shots.append(Capture(url:url,width:640,height:400))
        }
        for shot in shots.prefix(5) { model.receive(shot) }
        model.selection=[shots[1].id]; model.receive(shots[5])
        precondition(model.history.slots[5]==shots[5].id && model.history.writePointer==6)
        let view=TrayView(model:model); view.frame=CGRect(x:0,y:0,width:1100,height:270)
        for concept in Concept.allCases {
            model.concept=concept; view.synchronizeState()
            for openness:CGFloat in [0.4,0.7,1] {
                view.expanded=false; view.openness=openness; view.spread=1
                paint(view)
                let candidate=view.orderedIDs.compactMap { id -> CGPoint? in
                    guard let path=view.hitPaths[id] else { return nil }
                    let r=path.boundingBox.intersection(view.bounds), p=CGPoint(x:r.midX,y:r.midY)
                    return view.hit(p) != nil ? p : nil
                }.first!
                let expected=view.hit(candidate)!
                precondition(view.acceptsPointer(at:candidate),"Visible opening frame rejected pointer")
                let click=event(view.convert(candidate,to:nil))
                view.mouseDown(with:click); view.mouseUp(with:click)
                precondition(model.selection == [expected],"Opening click selected wrong image")
                precondition(view.hit(CGPoint(x:-1,y:40)) == nil)
            }
        }
        print("PASS: A/B/C visible expansion hit geometry and synthetic selection; write pointer independent of selection")
        model.concept = .buffer; view.synchronizeState(); view.expanded=true; view.openness=1
        let oldest=model.history.items.last!
        paint(view); view.beginPress(oldest.id,event:event(.zero))
        for shot in shots.dropFirst(6) { model.receive(shot); view.synchronizeState() }
        view.mouseUp(with:event(.zero,flags:.shift))
        precondition(!model.selection.contains(oldest.id) && model.history.items.count==8)
        paint(view)
        let current=model.history.items[0]
        view.beginPress(current.id,event:event(.zero)); model.concept = .layers; view.synchronizeState()
        model.selection=[]; view.mouseUp(with:event(.zero)); precondition(model.selection.isEmpty)
        view.landing=current.id; view.arrived[current.id]=CACurrentMediaTime(); view.evict(current)
        model.animations=false; view.tick(); paint(view)
        precondition(view.landing==nil && view.arrived.isEmpty && view.openness==1)
        model.animations=true; view.landing=current.id; model.reduceMotion={true}; view.tick()
        precondition(view.landing==nil && view.arrived.isEmpty)
        model.reduceMotion={false}; view.tick(); precondition(view.landing==nil)
        precondition(AppModel(demo:true,preferences:defaults).animations)
        print("PASS: burst eviction before release, style cancellation, app/system reduced motion and re-enable")
        let image=NSImage(data:bytes)!
        for concept in Concept.allCases {
            let effect=CaptureEffect(image:image,source:CGRect(x:300,y:50,width:240,height:150),target:CGRect(x:40,y:42,width:108,height:68),concept:concept,top:32)
            effect.frame=CGRect(x:0,y:0,width:1100,height:500)
            effect.onDown={ view.beginPress(current.id,event:$0) }
            effect.onUp={ view.mouseUp(with:$0) }
            for progress:CGFloat in [0.1,0.5,0.85,1] {
                effect.progress=progress; paint(effect)
                precondition(!effect.imagePath.isEmpty,"Visible arrival has no interactive geometry")
                precondition(!effect.imagePath.contains(CGPoint(x:1090,y:490),using:.winding),"Overlay blocks unrelated content")
                let bounds=effect.imagePath.boundingBox
                var visible:CGPoint?
                for y in stride(from:bounds.minY+0.1,through:bounds.maxY,by:1) {
                    for x in stride(from:bounds.minX+0.1,through:bounds.maxX,by:1) where visible == nil {
                        let p=CGPoint(x:x,y:y)
                        if effect.imagePath.contains(p,using:.winding) { visible=p }
                    }
                    if visible != nil { break }
                }
                model.selection=[]
                let click=event(effect.convert(visible!,to:nil))
                effect.mouseDown(with:click); effect.mouseUp(with:click)
                precondition(model.selection == [current.id] && !effect.holding)
            }
        }
        print("PASS: native A/B/C effect geometry and selection callbacks throughout arrival")
        let controller=TrayController(model:model,presentWindows:false)
        for shot in shots.prefix(4) { model.receive(shot) }
        precondition(controller.pendingCount>0)
        model.concept = .buffer; precondition(controller.pendingCount==0)
        model.receive(shots[5]); model.reduceMotion={true}; controller.synchronizeState()
        precondition(controller.pendingCount==0)
        let retained=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
        precondition(retained.count==40)
        precondition(NSApplication.shared.windows.allSatisfy { !$0.isVisible },"Background checks created a visible window")
        print("PASS: headless queue drains on style/system policy changes; all originals retained")
    }
}
