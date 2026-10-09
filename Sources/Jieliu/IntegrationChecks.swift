import AppKit
import TrayCore

enum IntegrationChecks {
    static func run() throws {
        checkLanguage()
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("jieliu-check-"+UUID().uuidString)
        let source=root.appendingPathComponent("source"), archive=root.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
        try FileManager.default.createDirectory(at:archive,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let bytes=DemoSupport.fixture(0)
        let old=source.appendingPathComponent("old.png")
        try bytes.write(to:old); try tag(old,key:"kMDItemIsScreenCapture",value:true)
        let watcher=ScreenshotWatcher(destination:archive,sourceOverride:[source,archive])
        var captures:[Capture]=[],errors:[String]=[]
        watcher.onCapture={ captures.append($0) }; watcher.onError={ errors.append($0) }
        watcher.start(); spin(0.4)
        let untagged=source.appendingPathComponent("Screen Shot misleading filename.png")
        try bytes.write(to:untagged)
        let capture=source.appendingPathComponent("anything.png")
        try bytes.write(to:capture)
        // Metadata may arrive after the directory creation event.
        spin(0.3)
        try tag(capture,key:"kMDItemIsScreenCapture",value:true)
        try tag(capture,key:"kMDItemScreenCaptureGlobalRect",value:[-1440,32,640,400])
        let deadline=Date().addingTimeInterval(6)
        while captures.isEmpty && Date()<deadline { spin(0.1) }
        spin(0.6); watcher.stop()
        precondition(errors.isEmpty,"Watcher errors: \(errors)")
        precondition(captures.count == 1,"Expected exactly one capture, got \(captures.count)")
        precondition(captures[0].url.deletingLastPathComponent().resolvingSymlinksInPath().path == archive.resolvingSymlinksInPath().path,"Wrong archive: \(captures[0].url.path)")
        let fixture=NSBitmapImageRep(data:bytes)!
        precondition(captures[0].width == fixture.pixelsWide && captures[0].height == fixture.pixelsHigh)
        precondition(captures[0].rect == CaptureRect(x:-1440,y:32,width:640,height:400))
        precondition(FileManager.default.fileExists(atPath:old.path),"Old screenshots must remain untouched")
        precondition(FileManager.default.fileExists(atPath:untagged.path),"Filename alone must never identify a screenshot")
        precondition(!FileManager.default.fileExists(atPath:capture.path))
        let provider=CapturePasteboard(url:captures[0].url), item=provider.item()
        provider.pasteboard(nil,item:item,provideDataForType:.png)
        precondition(item.data(forType:.png) == bytes,"Drag must preserve original PNG pixels")
        precondition(item.string(forType:.fileURL) == captures[0].url.absoluteString)
        try checkInteractions(captures[0])
        try checkPanelFocus()
        print("PASS: watcher, delayed metadata, source rectangle, archive, duplicate suppression, old-file baseline, filename false-positive rejection, original drag bytes")
    }
    static func checkLanguage() {
        let suite="app.jieliu.language-check."+UUID().uuidString
        let defaults=UserDefaults(suiteName:suite)!
        defer { defaults.removePersistentDomain(forName:suite) }
        let model=AppModel(demo:true,preferences:defaults)
        precondition(model.language == .chinese)
        precondition(model.text("截图缓冲区","SCREENSHOT BUFFER") == "截图缓冲区")
        var redraws=0,menuUpdates=0
        model.onChange={redraws+=1}; model.onLanguageChange={menuUpdates+=1}
        model.language = .english
        precondition(model.text("截图缓冲区","SCREENSHOT BUFFER") == "SCREENSHOT BUFFER")
        precondition(model.title(.layers) == "Layers")
        precondition(redraws == 1 && menuUpdates == 1)
        let restored=AppModel(demo:true,preferences:defaults)
        precondition(restored.language == .english)
        restored.language = .chinese
        precondition(AppModel(demo:true,preferences:defaults).language == .chinese)
        precondition(restored.title(.buffer) == "帧缓冲")
        print("PASS: default Chinese, immediate language callbacks, English strings and preference restoration")
    }
    static func checkPanelFocus() throws {
        guard !NSScreen.screens.isEmpty else { throw NSError(domain:"Jieliu.Checks",code:1,userInfo:[NSLocalizedDescriptionKey:"No display available for panel focus check"]) }
        let model=AppModel(demo:true)
        let controller=TrayController(model:model)
        defer { controller.panels.forEach { $0.orderOut(nil) } }
        controller.expand(); spin(0.5)
        precondition(controller.panels.allSatisfy { $0.isVisible && !$0.isKeyWindow },"Automatic presentation must not take keyboard focus")
        print("PASS: live NSPanel presentation remains nonactivating across \(controller.panels.count) attached displays")
    }
    static func checkInteractions(_ capture:Capture) throws {
        for concept in Concept.allCases {
            let model=AppModel(demo:true); model.history.insert(capture); model.concept=concept
            let view=TrayView(model:model); view.frame=CGRect(x:0,y:0,width:1440,height:270)
            // Regression: a collapsed buffer must have an animation target before it is painted.
            precondition(view.destinationRect(for:capture) != nil)
            view.expanded=true; view.openness=1
            let surface=NSImage(size:view.frame.size); surface.lockFocusFlipped(true); view.draw(view.bounds); surface.unlockFocus()
            let r=view.layout[capture.id]!
            if concept != .buffer { precondition(!view.acceptsPointer(at:CGPoint(x:10,y:10)),"Must not block the Apple menu") }
            let click=view.convert(CGPoint(x:r.midX,y:r.midY),to:nil)
            let down=NSEvent.mouseEvent(with:.leftMouseDown,location:click,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            view.mouseDown(with:down); view.mouseUp(with:down)
            precondition(model.selection == [capture.id],"Selection failed for \(concept)")
            var previewed:UUID?; view.onPreview={previewed=$0}
            let space=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:" ",charactersIgnoringModifiers:" ",isARepeat:false,keyCode:49)!
            view.keyDown(with:space); precondition(previewed == capture.id)
            let delete=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:51)!
            view.keyDown(with:delete); precondition(model.history.items.isEmpty)
            precondition(FileManager.default.fileExists(atPath:capture.url.path))
        }
        print("PASS: all three native tray layouts, collapsed landing geometry, click selection, Space preview and Delete preservation")
    }
    static func tag(_ url:URL,key:String,value:Any) throws {
        let bytes=try PropertyListSerialization.data(fromPropertyList:value,format:.binary,options:0)
        let result=bytes.withUnsafeBytes { ptr in setxattr(url.path,"com.apple.metadata:"+key,ptr.baseAddress,ptr.count,0,0) }
        precondition(result == 0,"Could not tag test fixture")
    }
    static func spin(_ seconds:Double) {
        let end=Date().addingTimeInterval(seconds)
        while Date()<end { RunLoop.current.run(until:min(end,Date().addingTimeInterval(0.05))) }
    }
}
