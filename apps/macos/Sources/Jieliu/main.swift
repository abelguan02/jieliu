import AppKit
import TrayCore
import SwiftUI

final class AppDelegate:NSObject,NSApplicationDelegate,NSMenuItemValidation {
    let model=AppModel(demo:CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--render-preview"))
    var tray:TrayController?
    var watcher:ScreenshotWatcher?
    var status:NSStatusItem?
    var settings:NSWindow?
    var onboarding:NSWindow?
    var about:NSWindow?

    func applicationDidFinishLaunching(_ notification:Notification) {
        setupMenu()
        tray=TrayController(model:model)
        model.onLanguageChange = { [weak self] in
            guard let self else { return }
            self.setupMenu()
            self.settings?.title=self.model.text("截留设置","Jieliu Settings")
            self.onboarding?.title=self.model.text("欢迎使用截留","Welcome to Jieliu")
            self.about?.title=self.model.text("关于截留","About Jieliu")
            DispatchQueue.main.async { [weak self] in
                for window in [self?.settings,self?.onboarding,self?.about].compactMap({ $0 }) {
                    guard let view=window.contentView else { continue }
                    view.layoutSubtreeIfNeeded(); window.setContentSize(view.fittingSize)
                }
            }
        }
        model.onRestart = { [weak self] in self?.startWatching() }
        if model.isDemo { DemoSupport.populate(model); tray?.expand(); return }
        if !model.defaults.bool(forKey:"onboarded") { showOnboarding() }
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
        let status=self.status ?? NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status.button?.image=NSImage(systemSymbolName:"viewfinder",accessibilityDescription:model.text("截留","Jieliu"))
        status.button?.toolTip=model.text("截留 · 截图收纳托盘","Jieliu · Screenshot tray")
        let menu=NSMenu()
        menu.addItem(withTitle:model.text("展开截图托盘","Show screenshot tray"),action:#selector(expand),keyEquivalent:"").target=self
        let concepts=NSMenu()
        for concept in Concept.allCases {
            let item=concepts.addItem(withTitle:"\(concept.rawValue)  \(model.title(concept))",action:#selector(chooseConcept(_:)),keyEquivalent:"")
            item.representedObject=concept.rawValue; item.target=self
        }
        let parent=menu.addItem(withTitle:model.text("视觉方案","Appearance"),action:nil,keyEquivalent:""); parent.submenu=concepts
        menu.addItem(withTitle:model.text("打开截图文件夹","Open screenshot folder"),action:#selector(openFolder),keyEquivalent:"").target=self
        menu.addItem(.separator())
        menu.addItem(withTitle:model.text("关于截留","About Jieliu"),action:#selector(openAbout),keyEquivalent:"").target=self
        menu.addItem(withTitle:model.text("设置…","Settings…"),action:#selector(openSettings),keyEquivalent:",").target=self
        menu.addItem(.separator())
        menu.addItem(withTitle:model.text("退出截留","Quit Jieliu"),action:#selector(quit),keyEquivalent:"q").target=self
        status.menu=menu; self.status=status
    }
    func validateMenuItem(_ item:NSMenuItem)->Bool {
        if item.action == #selector(chooseConcept(_:)) { item.state=(item.representedObject as? String) == model.concept.rawValue ? .on : .off }
        return true
    }
    @objc func expand() { tray?.expand() }
    @objc func chooseConcept(_ sender:NSMenuItem) { if let raw=sender.representedObject as? String,let value=Concept(rawValue:raw) { model.concept=value; tray?.expand() } }
    @objc func openFolder() { model.openFolder() }
    @objc func openSettings() { model.defaults.bool(forKey:"onboarded") ? showSettings() : showOnboarding() }
    @objc func openAbout() { showAbout() }
    @objc func quit() { NSApp.terminate(nil) }
    func showSettings() {
        settings=present(settings,title:model.text("截留设置","Jieliu Settings"),content:SettingsView(model:model) { [weak self] in self?.showAbout() })
    }
    func showAbout() {
        about=present(about,title:model.text("关于截留","About Jieliu"),content:AboutView(model:model) { [weak self] in self?.showOnboarding() })
    }
    func showOnboarding() {
        onboarding=present(onboarding,title:model.text("欢迎使用截留","Welcome to Jieliu"),content:OnboardingView(model:model) { [weak self] in
            guard let self else { return }
            self.model.defaults.set(true,forKey:"onboarded"); self.onboarding?.close(); self.startWatching(); self.tray?.expand()
        })
    }
    /// Reuses a visible window; a closed one is rebuilt so it reflects the current state.
    private func present(_ existing:NSWindow?,title:String,content:some View)->NSWindow {
        if let existing,existing.isVisible { existing.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); return existing }
        let window=NSWindow(contentRect:.zero,styleMask:[.titled,.closable],backing:.buffered,defer:false)
        let hosting=NSHostingView(rootView:content)
        window.contentView=hosting; window.setContentSize(hosting.fittingSize)
        window.title=title; window.isReleasedWhenClosed=false; window.center()
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        return window
    }
    func applicationWillTerminate(_ notification:Notification) { watcher?.stop(); model.persist() }
}

let application=NSApplication.shared
application.setActivationPolicy(CommandLine.arguments.contains("--offscreen-check") || CommandLine.arguments.contains("--render-icon") ? .prohibited : .accessory)
Fonts.register()
if CommandLine.arguments.contains("--offscreen-check") { try OffscreenChecks.run(); exit(0) }
if let index=CommandLine.arguments.firstIndex(of:"--render-icon"),CommandLine.arguments.indices.contains(index+1) {
    try AppIcon.write(to:URL(fileURLWithPath:CommandLine.arguments[index+1])); exit(0)
}
if CommandLine.arguments.contains("--integration-check") { try IntegrationChecks.run(); exit(0) }
let delegate=AppDelegate()
application.delegate=delegate
if CommandLine.arguments.contains("--render-preview") { try DemoSupport.render(); exit(0) }
application.run()
