import AppKit
import TrayCore

/// Exercises keyboard dispatch and watcher retries without windows or the system clipboard.
enum CaptureRegressionChecks {
    private final class Clock {
        private let lock=NSLock()
        private var value=Date()
        func now()->Date { lock.lock(); defer { lock.unlock() }; return value }
        func advance(_ seconds:TimeInterval) { lock.lock(); defer { lock.unlock() }; value.addTimeInterval(seconds) }
    }

    static func run(root:URL,preferences:UserDefaults) throws {
        var failures:[String]=[]
        func check(_ condition:Bool,_ message:String) {
            if !condition { failures.append(message); print("FAIL: \(message)") }
        }
        let directory=root.appendingPathComponent("capture-regressions")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let bytes=CaptureInputChecks.png(43,29)
        let png=directory.appendingPathComponent("original.png")
        try bytes.write(to:png)
        let model=AppModel(demo:true,preferences:preferences)
        let capture=Capture(url:png,width:43,height:29)
        model.receive(capture)
        let copy=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:0,context:nil,characters:"c",charactersIgnoringModifiers:"c",isARepeat:false,keyCode:8)!
        let delete=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:51)!
        var writes:[[NSPasteboardWriting]]=[]
        func fileURL(_ writer:NSPasteboardWriting)->String? {
            if let url=writer as? NSURL { return url.absoluteString }
            return (writer as? NSPasteboardItem)?.string(forType:.fileURL)
        }
        let view=TrayView(model:model,writeClipboard:{ writes.append($0); return true })
        view.keyDown(with:copy)
        check(writes.isEmpty && view.message.isEmpty,"Empty Mac copy must preserve clipboard and omit success toast")
        var changes=0
        model.onChange={ changes+=1 }
        let emptyDeleteView=TrayView(model:model,writeClipboard:{ _ in fatalError("Unexpected clipboard access") })
        emptyDeleteView.keyDown(with:delete)
        check(changes==0 && emptyDeleteView.message.isEmpty,"Empty Mac Delete must not mutate history or show a toast")
        check(model.history.items.count==1 && FileManager.default.fileExists(atPath:png.path),"Empty Delete removed a capture")

        writes.removeAll(); model.selection=[capture.id]; view.keyDown(with:copy)
        let single=writes.last?.first as? NSPasteboardItem
        check(writes.count==1 && writes.last?.first.flatMap(fileURL)==png.absoluteString,"Single Mac copy must include the original file URL")
        check(single?.data(forType:.png)==bytes,"Single Mac copy must eagerly preserve original PNG bytes")
        let tiff=single?.data(forType:.tiff).flatMap { NSBitmapImageRep(data:$0) }
        check(tiff?.pixelsWide==43 && tiff?.pixelsHigh==29,"Single Mac copy must include full-size TIFF pixels")
        let dragProvider=CapturePasteboard(url:png), dragItem=dragProvider.item()
        dragProvider.pasteboard(nil,item:dragItem,provideDataForType:.png)
        check(dragItem.string(forType:.fileURL)==png.absoluteString && dragItem.data(forType:.png)==bytes && dragItem.types.contains(.tiff),"Lazy drag must retain original files and image formats")

        let jpeg=directory.appendingPathComponent("converted.jpg")
        try NSBitmapImageRep(data:bytes)!.representation(using:.jpeg,properties:[:])!.write(to:jpeg)
        let other=Capture(url:jpeg,width:43,height:29); model.receive(other)
        writes.removeAll(); model.selection=[other.id]; view.keyDown(with:copy)
        let converted=(writes.last?.first as? NSPasteboardItem)?.data(forType:.png).flatMap { NSBitmapImageRep(data:$0) }
        check(converted?.pixelsWide==43 && converted?.pixelsHigh==29,"Non-PNG copy must supply full-size image data")

        writes.removeAll(); model.selection=[capture.id,other.id]; view.keyDown(with:copy)
        let multiple=writes.last?.compactMap { $0 as? NSPasteboardItem } ?? []
        check(writes.last?.count==2 && Set(writes.last?.compactMap(fileURL) ?? [])==Set([png.absoluteString,jpeg.absoluteString]),"Multi-copy must include both file URLs")
        check(multiple.allSatisfy { !$0.types.contains(.png) && !$0.types.contains(.tiff) },"Multi-copy must match Windows file-list semantics")

        try FileManager.default.removeItem(at:jpeg)
        writes.removeAll(); model.selection=[other.id]; view.keyDown(with:copy)
        check(writes.isEmpty,"Missing selected files must not replace the clipboard")
        model.selection=[capture.id]; emptyDeleteView.keyDown(with:delete)
        check(!model.history.items.contains { $0.id==capture.id } && FileManager.default.fileExists(atPath:png.path),"Delete must remove only the tray entry")

        let failedCopy=TrayView(model:model,writeClipboard:{ _ in false })
        model.receive(capture); model.selection=[capture.id]; failedCopy.keyDown(with:copy)
        check(failedCopy.message.isEmpty && !model.lastError.isEmpty,"Clipboard write failure must report an error without a success toast")

        let source=directory.appendingPathComponent("source"), archive=directory.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
        let clock=Clock()
        let watcher=ScreenshotWatcher(destination:archive,sourceOverride:[source,archive],now:clock.now)
        var captures:[Capture]=[],errors:[String]=[]
        watcher.onCapture={ captures.append($0) }; watcher.onError={ errors.append($0) }
        watcher.start(); defer { watcher.stop() }; CaptureInputChecks.spin(0.4)
        let delayed=source.appendingPathComponent("delayed.png")
        try bytes.write(to:delayed); CaptureInputChecks.spin(0.5)
        check(captures.isEmpty,"Unclassified image must not be collected before metadata arrives")
        try CaptureInputChecks.tag(delayed)
        CaptureInputChecks.wait({captures.count==1},"Delayed screenshot metadata was not retried")

        let expired=source.appendingPathComponent("ordinary.png")
        let replaced=source.appendingPathComponent("replaced.png")
        try bytes.write(to:expired); try bytes.write(to:replaced); CaptureInputChecks.spin(0.5)
        clock.advance(31); CaptureInputChecks.spin(0.4)
        // Metadata alone need not change the tracked content version. A directory event
        // must not restart an expired version; an explicit Spotlight result may do so.
        try CaptureInputChecks.tag(expired)
        try Data().write(to:source.appendingPathComponent("unrelated.txt"))
        CaptureInputChecks.spin(0.8)
        check(captures.count==1 && FileManager.default.fileExists(atPath:expired.path),"Unrelated directory event re-enqueued an expired image version")
        watcher.metadataArrived([expired])
        CaptureInputChecks.wait({captures.count==2},"Explicit screenshot metadata did not revive an expired candidate")
        try bytes.write(to:replaced,options:.atomic); try CaptureInputChecks.tag(replaced)
        CaptureInputChecks.wait({captures.count==3},"Changed file version was incorrectly suppressed after expiration")
        watcher.metadataArrived(captures.map(\.url)); CaptureInputChecks.spin(0.4)
        check(captures.count==3 && errors.isEmpty,"Metadata update duplicated captured images or reported errors")
        guard failures.isEmpty else {
            throw NSError(domain:"CaptureRegressionChecks",code:1,userInfo:[NSLocalizedDescriptionKey:failures.joined(separator:"; ")])
        }
        print("PASS: empty copy/Delete, original and converted image copy, file-list multi-copy, write failure, delayed metadata, expired-version suppression and metadata/content revival")
    }
}
