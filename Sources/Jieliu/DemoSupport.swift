import AppKit
import TrayCore

enum DemoSupport {
    static var output:URL { URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("dist/Previews") }
    static func populate(_ model:AppModel) {
        do {
            try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
            for index in 0..<6 {
                let url=output.appendingPathComponent("sample-\(index).png")
                if !FileManager.default.fileExists(atPath:url.path) { try fixture(index).write(to:url) }
                let capture=Capture(url:url,date:Date(timeIntervalSince1970:1791482400+Double(index)*143),width:640,height:400)
                model.history.insert(capture)
            }
        } catch { model.lastError=error.localizedDescription }
    }
    static func fixture(_ index:Int)->Data {
        let image=NSImage(size:CGSize(width:640,height:400))
        image.lockFocusFlipped(true)
        Ink.box(CGRect(x:0,y:0,width:640,height:400),color:Ink.color(index%2 == 0 ? 0xf5f6f8 : 0x16191e))
        Ink.box(CGRect(x:0,y:0,width:640,height:32),color:Ink.color(index%2 == 0 ? 0xe6e8ed : 0x24282f))
        for (i,color) in [NSColor.systemRed,.systemYellow,.systemGreen].enumerated() { Ink.box(CGRect(x:14+i*20,y:11,width:10,height:10),color:color,radius:5) }
        Ink.text(["Visual references","ScreenshotWatcher.swift","Capture history","Design tokens","Untitled document","Layers"][index%6],220,9,size:12,color:Ink.muted)
        if index%3 == 0 {
            let colors=[0x30d5f7,0xff7a6b,0x4b8dff,0x171923,0xd6d6d6,0x8ec5ff]
            for i in 0..<6 {
                let r=CGRect(x:24+(i%3)*202,y:68+(i/3)*155,width:186,height:140)
                Ink.box(r,color:Ink.color(colors[i]),radius:8)
                Ink.text(["Guide Cyan","Sunset","Selection","Geist Mono","Transparency","Mountain"][i],r.minX+12,r.maxY-30,size:15,color:i == 3 ? .white : Ink.color(0x182330))
            }
        } else if index%3 == 1 {
            for (i,line) in ["import AppKit","","final class ScreenshotWatcher {","    let query = NSMetadataQuery()","","    func start() {","        query.predicate = NSPredicate(","            format: \"kMDItemIsScreenCapture = 1\")","        query.start()","    }","}"].enumerated() {
                Ink.text("\(i+1)",18,60+CGFloat(i)*26,size:13,color:Ink.color(0x5b616c))
                Ink.text(line,60,60+CGFloat(i)*26,size:15,color:i%3 == 0 ? Ink.color(0xff7ab2) : Ink.color(0x6fdcff))
            }
        } else {
            Ink.text("Capture, collect, create.",28,58,size:23,color:index%2 == 0 ? Ink.color(0x16181c) : .white)
            for i in 0..<14 {
                let h=CGFloat(50+(i*37)%190)
                Ink.box(CGRect(x:32+CGFloat(i)*42,y:340-h,width:29,height:h),color:i == 13 ? Ink.blue : Ink.color(0xb1c5e8),radius:3)
            }
        }
        image.unlockFocus()
        return NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
    }
    static func render() throws {
        let model=AppModel(demo:true); populate(model)
        for concept in Concept.allCases {
            model.concept=concept
            let view=TrayView(model:model); view.frame=CGRect(x:0,y:0,width:1440,height:270)
            view.expanded=true; view.openness=1; view.spread=1; view.hovering=true
            if concept == .layers { view.hovered=model.history.items.first?.id }
            model.selection=Set(model.history.items.prefix(1).map(\.id))
            let image=NSImage(size:view.frame.size); image.lockFocusFlipped(true)
            NSGradient(starting:Ink.color(0x143445),ending:Ink.color(0x453044))?.draw(in:view.bounds,angle:0)
            view.draw(view.bounds); image.unlockFocus()
            let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
            try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("\(concept.rawValue)-\(concept.title).png"))
        }
        model.entry = .capsule
        let capsule=TrayView(model:model); capsule.frame=CGRect(x:0,y:0,width:1440,height:270)
        let image=NSImage(size:CGSize(width:360,height:150)); image.lockFocusFlipped(true)
        Ink.box(CGRect(x:0,y:0,width:360,height:150),color:Ink.color(0x203342))
        Ink.text("\u{65E0}\u{5218}\u{6D77}\u{5C4F}\u{5E55}",14,10,size:12)
        let c=NSGraphicsContext.current!.cgContext
        c.saveGState(); c.translateBy(x:-540,y:28); capsule.draw(capsule.bounds); c.restoreGState()
        Ink.text("\u{786C}\u{4EF6}\u{5218}\u{6D77}\u{4E0B}\u{6CBF}",14,75,size:12)
        capsule.hardwareInset=37
        c.saveGState(); c.translateBy(x:-540,y:76); capsule.draw(capsule.bounds); c.restoreGState()
        image.unlockFocus()
        try NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("capsule.png"))
        print("Rendered native tray and capsule previews to \(output.path)")
    }
}
