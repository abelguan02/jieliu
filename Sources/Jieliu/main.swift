import AppKit
import TrayCore
import SwiftUI

final class AppDelegate:NSObject,NSApplicationDelegate {
    let model=AppModel(demo:CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--render-preview"))
    var tray:TrayController?
    var watcher:ScreenshotWatcher?
    var status:NSStatusItem?
    var settings:NSWindow?

    func applicationDidFinishLaunching(_ notification:Notification) {
        setupMenu()
        tray=TrayController(model:model)
        model.onRestart = { [weak self] in self?.startWatching() }
        if model.isDemo { DemoSupport.populate(model); tray?.expand(); return }
        if !model.defaults.bool(forKey:"onboarded") { showSettings(onboarding:true) }
        else { startWatching() }
    }
    func startWatching() {
        watcher?.stop()
        let watcher=ScreenshotWatcher(destination:model.destination)
        watcher.onCapture = { [weak self] in self?.model.receive($0) }
        watcher.onError = { [weak self] message in self?.model.lastError=message; self?.status?.button?.toolTip="截留："+message }
        self.watcher=watcher; watcher.start()
    }
    func setupMenu() {
        let status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status.button?.image=NSImage(systemSymbolName:"viewfinder",accessibilityDescription:"截留")
        status.button?.toolTip="截留 · 截图收纳托盘"
        let menu=NSMenu()
        menu.addItem(withTitle:"展开截图托盘",action:#selector(expand),keyEquivalent:"").target=self
        let concepts=NSMenu()
        for concept in Concept.allCases {
            let item=concepts.addItem(withTitle:"\(concept.rawValue)  \(concept.title)",action:#selector(chooseConcept(_:)),keyEquivalent:"")
            item.representedObject=concept.rawValue; item.target=self
        }
        let parent=menu.addItem(withTitle:"视觉方案",action:nil,keyEquivalent:""); parent.submenu=concepts
        menu.addItem(withTitle:"打开截图文件夹",action:#selector(openFolder),keyEquivalent:"").target=self
        menu.addItem(.separator())
        menu.addItem(withTitle:"设置…",action:#selector(openSettings),keyEquivalent:",").target=self
        menu.addItem(withTitle:"退出截留",action:#selector(quit),keyEquivalent:"q").target=self
        status.menu=menu; self.status=status
    }
    @objc func expand() { tray?.expand() }
    @objc func chooseConcept(_ sender:NSMenuItem) { if let raw=sender.representedObject as? String,let value=Concept(rawValue:raw) { model.concept=value; tray?.expand() } }
    @objc func openFolder() { model.openFolder() }
    @objc func openSettings() { showSettings(onboarding:!model.defaults.bool(forKey:"onboarded")) }
    @objc func quit() { NSApp.terminate(nil) }
    func showSettings(onboarding:Bool) {
        if let settings,settings.isVisible { settings.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); return }
        let view=SettingsView(model:model,onboarding:onboarding) { [weak self] in
            guard let self else { return }
            self.model.defaults.set(true,forKey:"onboarded"); self.settings?.close(); self.startWatching(); self.tray?.expand()
        }
        let window=NSWindow(contentRect:CGRect(x:0,y:0,width:556,height:720),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title=onboarding ? "欢迎使用截留" : "截留设置"
        let hosting=NSHostingView(rootView:view)
        window.contentView=hosting; window.setContentSize(hosting.fittingSize)
        window.isReleasedWhenClosed=false; window.center()
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); settings=window
    }
    func applicationWillTerminate(_ notification:Notification) { watcher?.stop(); model.persist() }
}

let application=NSApplication.shared
application.setActivationPolicy(.accessory)
Fonts.register()
if let index=CommandLine.arguments.firstIndex(of:"--render-icon"),CommandLine.arguments.indices.contains(index+1) {
    try AppIcon.write(to:URL(fileURLWithPath:CommandLine.arguments[index+1])); exit(0)
}
if CommandLine.arguments.contains("--integration-check") { try IntegrationChecks.run(); exit(0) }
let delegate=AppDelegate()
application.delegate=delegate
if CommandLine.arguments.contains("--render-preview") { try DemoSupport.render(); exit(0) }
application.run()
