import AppKit
import Darwin
import TrayCore

enum CaptureInputChecks {
    static func png(_ width:Int,_ height:Int)->Data {
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        bitmap.bitmapData!.initialize(repeating:255,count:bitmap.bytesPerRow*height)
        return bitmap.representation(using:.png,properties:[:])!
    }
    static func tag(_ url:URL) throws {
        let bytes=try PropertyListSerialization.data(fromPropertyList:true,format:.binary,options:0)
        let result=bytes.withUnsafeBytes { setxattr(url.path,"com.apple.metadata:kMDItemIsScreenCapture",$0.baseAddress,$0.count,0,0) }
        precondition(result==0,"Synthetic screenshot metadata could not be written")
    }
    static func spin(_ seconds:Double) {
        let deadline=Date().addingTimeInterval(seconds)
        while Date()<deadline { RunLoop.current.run(until:Date().addingTimeInterval(0.02)) }
    }
    static func wait(_ condition:()->Bool,_ reason:String) {
        let deadline=Date().addingTimeInterval(6)
        while !condition() && Date()<deadline { spin(0.05) }
        precondition(condition(),reason)
    }
    static func run(root:URL,preferences:UserDefaults) throws {
        try delayedStartup(root:root)
        let directory=root.appendingPathComponent("input-check")
        let source=directory.appendingPathComponent("source"), archive=directory.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let model=AppModel(demo:true,preferences:preferences)
        for (width,height) in [(100,2000),(2000,100),(40,30)] {
            let file=directory.appendingPathComponent("\(width)-\(height).png")
            try png(width,height).write(to:file)
            let capture=Capture(url:file,width:width,height:height)
            let image=model.image(capture)!
            let rep=image.representations.first!
            precondition(rep.pixelsWide<=1400 && rep.pixelsHigh<=1400 && rep.pixelsWide<=width && rep.pixelsHigh<=height,"Mac thumbnail bounds regressed")
        }
        let watcher=ScreenshotWatcher(destination:archive,sourceOverride:[source,archive])
        var captures:[Capture]=[],errors:[String]=[]
        watcher.onCapture={ captures.append($0) }; watcher.onError={ errors.append($0) }
        watcher.start(); defer { watcher.stop() }; spin(0.5)
        let bad=source.appendingPathComponent("partial.png")
        try Data("incomplete PNG".utf8).write(to:bad); try tag(bad); spin(0.5)
        let good=source.appendingPathComponent("valid.png")
        let bytes=png(40,30)
        try bytes.write(to:good); try tag(good)
        wait({captures.count==1},"Malformed file stopped native screenshot input")
        precondition(FileManager.default.fileExists(atPath:bad.path))
        try bytes.write(to:bad,options:.atomic); try tag(bad)
        wait({captures.count==2},"Completed native PNG was not retried")
        spin(0.4)
        precondition(captures.count==2 && errors.isEmpty)
        for capture in captures { precondition(try! Data(contentsOf:capture.url)==bytes) }
        print("PASS: native Mac tall/small thumbnail bounds and malformed screenshot preservation/continued input/recovery")
    }

    private static func delayedStartup(root:URL) throws {
        let directory=root.appendingPathComponent("delayed-startup")
        let source=directory.appendingPathComponent("source"),archive=directory.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
        var initial=true
        let watcher=ScreenshotWatcher(destination:archive,sourceOverride:[source],listDirectory:{ url in
            if initial {
                initial=false; entered.signal()
                guard release.wait(timeout:.now()+5) == .success else {
                    throw NSError(domain:"CaptureInputChecks",code:1,userInfo:[NSLocalizedDescriptionKey:"Initial directory listing was not released"])
                }
            }
            return try FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil)
        })
        // Initialization is not the watch boundary: this file predates start().
        let bytes=png(57,31),old=source.appendingPathComponent("old.png")
        try bytes.write(to:old); try tag(old); spin(0.05)
        var captures:[Capture]=[],errors:[String]=[]
        watcher.onCapture={ captures.append($0) }; watcher.onError={ errors.append($0) }
        watcher.start(); defer { release.signal(); watcher.stop() }
        precondition(entered.wait(timeout:.now()+5) == .success,"Initial listing did not start")
        // Model a desktop permission prompt holding the first directory listing.
        let fresh=source.appendingPathComponent("during-permission.png")
        let partial=source.appendingPathComponent("during-permission-partial.png")
        try bytes.write(to:fresh); try tag(fresh); try Data().write(to:partial)
        release.signal()
        wait({captures.count==1},"Screenshot created while startup listing was blocked became an old-file baseline")
        precondition(captures[0].url.lastPathComponent==fresh.lastPathComponent)
        try bytes.write(to:partial); spin(0.5)
        precondition(captures.count==1,"Unmarked startup image was collected prematurely")
        try tag(partial)
        wait({captures.count==2},"Startup candidate lost delayed write or metadata retry")
        watcher.metadataArrived([old]+captures.map(\.url)); spin(0.4)
        precondition(captures.count==2 && errors.isEmpty && FileManager.default.fileExists(atPath:old.path))
        for capture in captures { precondition(try! Data(contentsOf:capture.url)==bytes) }
        print("PASS: delayed initial directory access preserves old files, collects new screenshots once, and retries partial writes/late metadata")
    }
}
