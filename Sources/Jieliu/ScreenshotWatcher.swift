import AppKit
import ImageIO
import TrayCore

/// Directory events provide low latency; Spotlight catches custom screenshot destinations.
/// All filesystem work stays off the main thread. Existing files are baselined, never swept.
final class ScreenshotWatcher {
    var onCapture: ((Capture) -> Void)?
    var onError: ((String) -> Void)?
    private let work = DispatchQueue(label: "app.jieliu.capture", qos: .userInitiated)
    private let query = NSMetadataQuery()
    private var sources: [DispatchSourceFileSystemObject] = []
    private var timer: DispatchSourceTimer?
    private var observers: [NSObjectProtocol] = []
    private var known = Set<URL>()
    private var pending: [URL: (first: Date, size: Int, stable: Int)] = [:]
    private var directories: [URL] = []
    private var destination: URL
    private let startDate = Date()
    private var reported = Set<String>()
    private let sourceOverride:[URL]?

    init(destination: URL, sourceOverride:[URL]? = nil) { self.destination = destination; self.sourceOverride=sourceOverride }

    func start() {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let configured = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        var paths = [desktop, destination]
        if let configured { paths.append(URL(fileURLWithPath: (configured as NSString).expandingTildeInPath)) }
        directories = Array(Set((sourceOverride ?? paths).map(\.standardizedFileURL)))
        work.async { [self] in
            do { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true) }
            catch { report("无法创建截图文件夹：\(error.localizedDescription)") }
            for directory in directories {
                scan(directory, baseline: true)
                let descriptor = open(directory.path, O_EVTONLY)
                guard descriptor >= 0 else { report("无法监听 \(directory.path)，请在设置中重新授权文件夹。"); continue }
                let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: work)
                source.setEventHandler { [weak self] in self?.scan(directory, baseline: false) }
                source.setCancelHandler { close(descriptor) }
                source.resume(); sources.append(source)
            }
            let clock = DispatchSource.makeTimerSource(queue: work)
            clock.schedule(deadline: .now() + 0.2, repeating: 0.2)
            clock.setEventHandler { [weak self] in self?.drain() }
            clock.resume(); timer = clock
        }
        guard sourceOverride == nil else { return }
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1 AND kMDItemFSCreationDate >= %@", startDate as NSDate)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.notificationBatchingInterval = 0.2
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, Notification.Name.NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.query.disableUpdates()
                let urls = self.query.results.compactMap { ($0 as? NSMetadataItem)?.value(forAttribute: NSMetadataItemURLKey) as? URL }
                self.query.enableUpdates()
                self.work.async { for url in urls { self.enqueue(url) } }
            })
        }
        if !query.start() { onError?("Spotlight 监听不可用；仍通过截图目录检测新文件。") }
    }

    func stop() {
        query.stop(); observers.forEach(NotificationCenter.default.removeObserver); observers.removeAll()
        work.sync { sources.forEach { $0.cancel() }; sources.removeAll(); timer?.cancel(); timer = nil }
    }

    private func scan(_ directory: URL, baseline: Bool) {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            for url in urls {
                if baseline { known.insert(url.standardizedFileURL) } else { enqueue(url) }
            }
        } catch { report("无法读取 \(directory.path)：\(error.localizedDescription)") }
    }

    private func enqueue(_ url: URL) {
        let url = url.standardizedFileURL
        guard !known.contains(url), pending[url] == nil else { return }
        guard ["png", "jpg", "jpeg", "heic", "tiff", "tif", "pdf"].contains(url.pathExtension.lowercased()) else { return }
        pending[url] = (Date(), -1, 0)
    }

    private func drain() {
        let ordered=pending.keys.sorted { a,b in
            let da=(try? FileManager.default.attributesOfItem(atPath:a.path)[.creationDate] as? Date) ?? pending[a]!.first
            let db=(try? FileManager.default.attributesOfItem(atPath:b.path)[.creationDate] as? Date) ?? pending[b]!.first
            return da<db
        }
        for url in ordered {
            guard var state = pending[url] else { continue }
            if Date().timeIntervalSince(state.first) > 30 { pending[url] = nil; known.insert(url); continue }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int, size > 0 else { continue }
            state.stable = size == state.size ? state.stable + 1 : 0
            state.size = size; pending[url] = state
            guard state.stable >= 1, CaptureFiles.isScreenshot(url) else { continue }
            guard let image = NSImage(contentsOf: url), image.isValid else { continue }
            let rep = image.representations.max { $0.pixelsWide < $1.pixelsWide }
            let width = rep?.pixelsWide ?? Int(image.size.width)
            let height = rep?.pixelsHigh ?? Int(image.size.height)
            let rect = CaptureFiles.captureRect(url)
            do {
                let archived = try CaptureFiles.archive(url, into: destination)
                known.insert(url); known.insert(archived.standardizedFileURL); pending[url] = nil
                let capture = Capture(url: archived, date: attrs[.creationDate] as? Date ?? Date(), width: width, height: height, rect: rect)
                DispatchQueue.main.async { self.onCapture?(capture) }
            } catch { report("截图归档失败，原文件保留：\(error.localizedDescription)") }
        }
    }

    private func report(_ message: String) {
        guard reported.insert(message).inserted else { return }
        DispatchQueue.main.async { self.onError?(message) }
    }
}
