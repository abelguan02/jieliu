import AppKit
import SwiftUI

/// Lays out settings, about and every onboarding page in both languages without a window.
/// Set JIELIU_RENDER_DIR to also write the rendered panels as PNG files.
enum PanelChecks {
    static func run(_ model:AppModel) {
        let output=ProcessInfo.processInfo.environment["JIELIU_RENDER_DIR"].map { URL(fileURLWithPath:$0) }
        let original=model.language
        for language in AppLanguage.allCases {
            model.language=language
            var panels:[(String,AnyView,ClosedRange<CGFloat>)]=[
                ("settings",AnyView(SettingsView(model:model) {}),360...620),
                ("about",AnyView(AboutView(model:model) {}),420...640)
            ]
            for page in 0..<4 { panels.append(("onboarding-\(page)",AnyView(OnboardingView(model:model,page:page,baseline:model.history.total,start:{},finish:{})),380...420)) }
            panels.append(("onboarding-3-received",AnyView(OnboardingView(model:model,page:3,baseline:model.history.total-1,start:{},finish:{})),380...420))
            var onboardingHeights=Set<CGFloat>()
            for (name,view,heights) in panels {
                let host=NSHostingView(rootView:view.background(Color(white:0.13)))
                host.appearance=NSAppearance(named:.darkAqua)
                let size=host.fittingSize
                precondition(size.width>=420 && size.width<=520 && heights.contains(size.height),"\(name) \(language.rawValue) fits \(size)")
                if name.hasPrefix("onboarding") { onboardingHeights.insert(size.height) }
                host.frame=CGRect(origin:.zero,size:size); host.layoutSubtreeIfNeeded()
                guard let rep=host.bitmapImageRepForCachingDisplay(in:host.bounds) else { preconditionFailure("\(name) has no bitmap") }
                host.cacheDisplay(in:host.bounds,to:rep)
                if let output,let png=rep.representation(using:.png,properties:[:]) {
                    try? FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
                    try? png.write(to:output.appendingPathComponent("\(name)-\(language.rawValue).png"))
                }
            }
            precondition(onboardingHeights.count == 1,"Onboarding pages resize the window: \(onboardingHeights)")
        }
        model.language=original
        precondition(NSApplication.shared.windows.allSatisfy { !$0.isVisible },"Panel checks created a visible window")
        print("PASS: settings, about, onboarding pages and trial states fit in Chinese and English without windows")
    }
}
