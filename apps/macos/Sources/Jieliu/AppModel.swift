import AppKit
import SwiftUI
import TrayCore

enum AppLanguage:String,CaseIterable,Identifiable {
    case chinese = "zh-Hans", english = "en"
    var id:String { rawValue }
    var title:String { self == .chinese ? "中文" : "English" }
}

enum TrayEntry:String,CaseIterable,Identifiable {
    case capsule, menuBarOnly
    var id:String { rawValue }
}

enum Concept: String, CaseIterable, Identifiable {
    case ruler = "A", buffer = "B", layers = "C"
    var id: String { rawValue }
    var title: String { switch self { case .ruler: return "标尺"; case .buffer: return "帧缓冲"; case .layers: return "图层" } }
}

final class AppModel: ObservableObject {
    @Published var entry:TrayEntry {
        didSet { defaults.set(entry.rawValue,forKey:"trayEntry"); onChange?(); onEntryChange?() }
    }
    @Published var language:AppLanguage {
        didSet { defaults.set(language.rawValue,forKey:"language"); onChange?(); onLanguageChange?() }
    }
    @Published var history = TrayHistory()
    @Published var concept: Concept { didSet { defaults.set(concept.rawValue, forKey: "concept"); onChange?() } }
    @Published var autoHide: Bool { didSet { defaults.set(autoHide, forKey: "autoHide") } }
    @Published var sound: Bool { didSet { defaults.set(sound, forKey: "sound") } }
    @Published var lastError = ""
    @Published var destination: URL
    var selection = Set<UUID>()
    var onChange: (() -> Void)?
    var onCapture: ((Capture, Capture?) -> Void)?
    var onRestart: (() -> Void)?
    var onLanguageChange:(()->Void)?
    var onEntryChange:(()->Void)?
    let defaults: UserDefaults
    let historyURL: URL
    let isDemo: Bool
    private var images: [UUID: NSImage] = [:]

    init(demo: Bool = false, preferences:UserDefaults? = nil) {
        isDemo = demo
        defaults = preferences ?? (demo ? UserDefaults(suiteName: "app.jieliu.preview")! : .standard)
        language = AppLanguage(rawValue:defaults.string(forKey:"language") ?? "zh-Hans") ?? .chinese
        entry = TrayEntry(rawValue:defaults.string(forKey:"trayEntry") ?? "capsule") ?? .capsule
        concept = Concept(rawValue: defaults.string(forKey: "concept") ?? "B") ?? .buffer
        autoHide = defaults.object(forKey: "autoHide") as? Bool ?? true
        sound = defaults.bool(forKey: "sound")
        destination = URL(fileURLWithPath: defaults.string(forKey: "destination") ?? NSHomeDirectory() + "/Pictures/Screenshots")
        historyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Jieliu/history.json")
        if !demo, FileManager.default.fileExists(atPath: historyURL.path) {
            do { history = try TrayHistory.load(from: historyURL) }
            catch { lastError = text("历史记录无法读取：","Could not read history: ")+error.localizedDescription }
        }
    }

    func receive(_ capture: Capture) {
        guard !history.items.contains(where: { $0.id == capture.id }) else { return }
        let previous = history.insert(capture)
        selection.formIntersection(Set(history.items.map(\.id)))
        persist(); onCapture?(capture, previous); onChange?()
        let live = Set(history.items.map(\.id))
        images = images.filter { live.contains($0.key) }
    }

    func image(_ capture: Capture) -> NSImage? {
        if let cached = images[capture.id] { return cached }
        // Bounded thumbnails avoid retaining eight full-resolution screenshots.
        guard let source = CGImageSourceCreateWithURL(capture.url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1400,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return NSImage(contentsOf: capture.url) }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        images[capture.id] = image
        return image
    }

    func removeSelection() {
        history.remove(selection); selection.removeAll(); persist(); onChange?()
    }
    func persist() {
        guard !isDemo else { return }
        do { try history.save(to: historyURL) }
        catch { lastError = text("历史记录保存失败：","Could not save history: ")+error.localizedDescription }
    }
    func openFolder() {
        do { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true); NSWorkspace.shared.open(destination) }
        catch { lastError = error.localizedDescription }
    }
    func chooseDestination() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.directoryURL = destination
        panel.prompt = text("用作截图文件夹","Use screenshot folder")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        destination = url; defaults.set(url.path, forKey: "destination"); onRestart?(); onChange?()
    }
    var folderLabel: String { destination.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
    func text(_ chinese:String,_ english:String)->String { language == .chinese ? chinese : english }
    func title(_ concept:Concept)->String {
        switch concept {
        case .ruler: return text("标尺","Ruler")
        case .buffer: return text("帧缓冲","Buffer")
        case .layers: return text("图层","Layers")
        }
    }
}
