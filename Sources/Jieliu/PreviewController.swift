import AppKit
import SwiftUI
import TrayCore

final class PreviewPanel:TrayPanel {
    var onKey:((NSEvent)->Void)?
    override func keyDown(with event:NSEvent) { onKey?(event) }
}

final class PreviewController {
    private var panel:PreviewPanel?
    private var model:AppModel?
    private var current:UUID?
    var visible:Bool { panel?.isVisible == true }
    func show(id:UUID,model:AppModel,screen:NSScreen) {
        close(); self.model=model; current=id
        let panel=PreviewPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.backgroundColor = .clear; panel.isOpaque=false; panel.hasShadow=false
        panel.level=NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue+3)
        panel.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]
        panel.onKey = { [weak self] event in
            if [49,53].contains(event.keyCode) { self?.close() }
            else if [123,124].contains(event.keyCode) { self?.navigate(event.keyCode == 124 ? 1 : -1) }
        }
        self.panel=panel; refresh(); panel.makeKeyAndOrderFront(nil)
    }
    private func navigate(_ offset:Int) {
        guard let model,let index=model.history.items.firstIndex(where:{$0.id==current}),!model.history.items.isEmpty else { return }
        let next=(index+offset+model.history.items.count)%model.history.items.count
        current=model.history.items[next].id; refresh()
    }
    private func refresh() {
        guard let panel,let model,let capture=model.history.items.first(where:{$0.id==current}),let image=NSImage(contentsOf:capture.url) else { close(); return }
        let size=Ink.fit(image.size,in:CGRect(x:0,y:0,width:min(1040,panel.frame.width-100),height:min(640,panel.frame.height-180))).size
        panel.contentView=NSHostingView(rootView:ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing:10) {
                Image(nsImage:image).resizable().aspectRatio(contentMode:.fit).frame(width:size.width,height:size.height).clipShape(RoundedRectangle(cornerRadius:6))
                HStack {
                    Text(capture.url.lastPathComponent).lineLimit(1)
                    Spacer(minLength:16)
                    Text("\(capture.width) × \(capture.height)").foregroundStyle(.secondary)
                }.font(.system(size:12,design:.monospaced)).frame(width:size.width)
            }.padding(10).background(Color(red:30/255,green:32/255,blue:38/255).opacity(0.96),in:RoundedRectangle(cornerRadius:14))
                .overlay(RoundedRectangle(cornerRadius:14).stroke(.white.opacity(0.12)))
                .shadow(color:.black.opacity(0.6),radius:40,y:20)
        }.frame(maxWidth:.infinity,maxHeight:.infinity).preferredColorScheme(.dark).onTapGesture { [weak self] in self?.close() })
    }
    func close() { panel?.orderOut(nil); panel=nil }
}
