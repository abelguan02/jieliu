import Foundation
import CoreServices
import Darwin

public enum CaptureFiles {
    public static func attribute(_ key: String, at url: URL) -> Any? {
        let name = "com.apple.metadata:" + key
        let size = getxattr(url.path, name, nil, 0, 0, 0)
        if size > 0, size < 65_536 {
            var bytes = [UInt8](repeating: 0, count: size)
            let read = getxattr(url.path, name, &bytes, size, 0, 0)
            if read == size,
               let value = try? PropertyListSerialization.propertyList(from: Data(bytes), options: [], format: nil) {
                return value
            }
        }
        guard let item = MDItemCreate(nil, url.path as CFString) else { return nil }
        return MDItemCopyAttribute(item, key as CFString)
    }

    public static func isScreenshot(_ url: URL) -> Bool {
        let value = attribute("kMDItemIsScreenCapture", at: url)
        return (value as? NSNumber)?.boolValue == true || (value as? String) == "1"
    }

    public static func captureRect(_ url: URL) -> CaptureRect? {
        CaptureRect.parse(attribute("kMDItemScreenCaptureGlobalRect", at: url))
    }

    public static func archive(_ source: URL, into directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if source.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL { return source }
        var destination = directory.appendingPathComponent(source.lastPathComponent)
        if fm.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent(source.deletingPathExtension().lastPathComponent + "-" + UUID().uuidString)
                .appendingPathExtension(source.pathExtension)
        }
        // moveItem never replaces an existing destination, including races with another capture.
        try fm.moveItem(at: source, to: destination)
        return destination
    }
}
