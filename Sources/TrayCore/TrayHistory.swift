import Foundation

public struct CaptureRect: Codable, Equatable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public static func parse(_ value: Any?) -> CaptureRect? {
        let numbers: [Double]
        if let array = value as? [NSNumber] { numbers = array.map(\.doubleValue) }
        else if let string = value as? String {
            numbers = string.components(separatedBy: CharacterSet(charactersIn: "0123456789.-").inverted)
                .compactMap(Double.init)
        } else { return nil }
        guard numbers.count == 4, numbers.allSatisfy(\.isFinite), numbers[2] > 0, numbers[3] > 0 else { return nil }
        return CaptureRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }
}

public struct Capture: Codable, Identifiable, Equatable {
    public var id: UUID
    public var url: URL
    public var date: Date
    public var width: Int
    public var height: Int
    public var rect: CaptureRect?
    public init(url: URL, date: Date = Date(), width: Int, height: Int, rect: CaptureRect? = nil) {
        id = UUID(); self.url = url; self.date = date
        self.width = width; self.height = height; self.rect = rect
    }
}

public struct TrayHistory: Codable {
    public static let capacity = 8
    public private(set) var items: [Capture] = []
    public private(set) var slots: [UUID?] = Array(repeating: nil, count: capacity)
    public private(set) var writePointer = 0
    public private(set) var total = 0
    public init() {}

    @discardableResult public mutating func insert(_ capture: Capture) -> Capture? {
        guard !items.contains(where: { $0.url == capture.url }) else { return nil }
        let evicted = slots[writePointer].flatMap { id in items.first { $0.id == id } }
        if let evicted { items.removeAll { $0.id == evicted.id } }
        items.insert(capture, at: 0)
        slots[writePointer] = capture.id
        writePointer = (writePointer + 1) % Self.capacity
        total += 1
        return evicted
    }

    public mutating func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        slots = slots.map { id in id.flatMap { ids.contains($0) ? nil : $0 } }
    }

    public mutating func validate() {
        // Never trust a persisted pointer or slot array before indexing it.
        items = Array(items.prefix(Self.capacity))
        var ids = Set<UUID>(), paths = Set<URL>()
        items = items.filter { ids.insert($0.id).inserted && paths.insert($0.url).inserted }
        if slots.count != Self.capacity || !(0..<Self.capacity).contains(writePointer) {
            slots = Array(repeating: nil, count: Self.capacity)
            for (i, capture) in items.reversed().enumerated() { slots[i] = capture.id }
            writePointer = items.count % Self.capacity
        }
        var used = Set<UUID>()
        slots = slots.map { id in id.flatMap { ids.contains($0) && used.insert($0).inserted ? $0 : nil } }
        for item in items where !slots.contains(item.id) {
            if let index = slots.firstIndex(of: nil) { slots[index] = item.id }
        }
        total = max(total, items.count)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
    public static func load(from url: URL) throws -> TrayHistory {
        var history = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        history.validate()
        history.remove(Set(history.items.filter { !FileManager.default.fileExists(atPath: $0.url.path) }.map(\.id)))
        return history
    }
}
