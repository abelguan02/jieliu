import AppKit
import ApplicationServices
import TrayCore

/// Input-payload and responder checks only: no windows, posted events or system clipboard.
enum CopyRoutingChecks {
    static func run(root:URL,preferences:UserDefaults) throws {
        let directory=root.appendingPathComponent("copy-routing")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:directory) }
        let url=directory.appendingPathComponent("selected.png")
        let bytes=CaptureInputChecks.png(43,29)
        try bytes.write(to:url)
        let model=AppModel(demo:true,preferences:preferences)
        let capture=Capture(url:url,width:43,height:29)
        model.receive(capture)
        var writes:[[NSPasteboardWriting]]=[]
        let view=TrayView(model:model,writeClipboard:{ writes.append($0); return true })
        view.frame=CGRect(x:0,y:0,width:1100,height:270)
        view.expanded=true; view.openness=1; OffscreenChecks.paint(view)

        // Recreate the previous foreground helper's payload without posting it.
        let cg=CGEvent(keyboardEventSource:nil,virtualKey:8,keyDown:true)!
        cg.flags=CGEventFlags(rawValue:1_048_576)
        guard let native=NSEvent(cgEvent:cg) else {
            throw NSError(domain:"CopyRoutingChecks",code:1,userInfo:[NSLocalizedDescriptionKey:"CGEvent could not become NSEvent"])
        }
        model.selection=[capture.id]
        view.keyDown(with:native)
        let payload=writes.last?.first as? NSPasteboardItem
        let directCopied=writes.count==1 && payload?.data(forType:.png)==bytes

        // Accessibility activation is independent of click coordinates and focus timing.
        model.selection=[]
        guard let button=view.accessibilityChildren()?.first as? ShotAccessibility else {
            throw NSError(domain:"CopyRoutingChecks",code:2,userInfo:[NSLocalizedDescriptionKey:"Capture accessibility button missing"])
        }
        precondition(!button.isAccessibilitySelected(),"Unselected capture was reported as selected")
        let pressed=button.accessibilityPerformPress()
        let selected=model.selection==[capture.id]
        let selectedReported=button.isAccessibilitySelected()
        precondition(pressed && selected,"Accessibility press failed to select the model capture")
        writes.removeAll(); view.keyDown(with:native)
        precondition(writes.count==1 && (writes.first?.first as? NSPasteboardItem)?.data(forType:.png)==bytes,"Copy after accessibility selection did not preserve the original PNG")

        guard directCopied else {
            throw NSError(domain:"CopyRoutingChecks",code:3,userInfo:[NSLocalizedDescriptionKey:"Foreground helper's unposted key payload does not activate copy when delivered directly"])
        }
        guard selectedReported else {
            throw NSError(domain:"CopyRoutingChecks",code:4,userInfo:[NSLocalizedDescriptionKey:"AXPress selected the capture, but its accessible state still reports AXSelected=false"])
        }
        model.selection=[]
        precondition(!button.isAccessibilitySelected(),"Cleared selection remained selected in accessibility")
        print("PASS: previous helper's key payload and accessibility selection activate original PNG copying when directly delivered; system focus/routing remains unverified")
    }
}
