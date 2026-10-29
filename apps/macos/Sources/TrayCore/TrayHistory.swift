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

public enum InsertionStatus: String { case inserted, duplicate, full }
public struct InsertionResult {
    public let status: InsertionStatus
    public let evicted: Capture?
}

public struct TrayHistory: Codable {
    public static let capacity = 8
    public private(set) var items: [Capture] = []
    public private(set) var slots: [UUID?] = Array(repeating: nil, count: capacity)
    public private(set) var writePointer = 0
    public private(set) var total = 0
    public private(set) var pinnedIDs: Set<UUID> = []
    public init() {}

    private enum CodingKeys: String, CodingKey { case items, slots, writePointer, total, pinnedIDs }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        items = try values.decode([Capture].self, forKey: .items)
        slots = try values.decode([UUID?].self, forKey: .slots)
        writePointer = try values.decode(Int.self, forKey: .writePointer)
        total = try values.decode(Int.self, forKey: .total)
        pinnedIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .pinnedIDs) ?? []
    }

    public var nextWriteSlot: Int? {
        let order = (0..<Self.capacity).map { (writePointer + $0) % Self.capacity }
        return order.first { slots[$0] == nil }
            ?? order.first { slots[$0].map { !pinnedIDs.contains($0) } ?? false }
    }

    public mutating func setPinned(_ ids: Set<UUID>, pinned: Bool) {
        let live = ids.intersection(items.map(\.id))
        if pinned { pinnedIDs.formUnion(live) } else { pinnedIDs.subtract(live) }
    }

    @discardableResult public mutating func insert(_ capture: Capture) -> InsertionResult {
        guard !items.contains(where: { $0.id == capture.id }) else { return InsertionResult(status: .duplicate, evicted: nil) }
        // A new version of a pinned file keeps its slot and pin, without moving the cursor.
        if let old = items.first(where: { $0.url == capture.url && pinnedIDs.contains($0.id) }),
           let index = slots.firstIndex(of: old.id) {
            remove([old.id]); items.insert(capture, at: 0); slots[index] = capture.id
            pinnedIDs.insert(capture.id); total += 1
            return InsertionResult(status: .inserted, evicted: old)
        }
        // The watcher assigns a new ID to each file version, even at the same URL.
        remove(Set(items.filter { $0.url == capture.url }.map(\.id)))
        guard let index = nextWriteSlot else { return InsertionResult(status: .full, evicted: nil) }
        let evicted = slots[index].flatMap { id in items.first { $0.id == id } }
        if let evicted { items.removeAll { $0.id == evicted.id } }
        items.insert(capture, at: 0)
        slots[index] = capture.id
        writePointer = (index + 1) % Self.capacity
        total += 1
        return InsertionResult(status: .inserted, evicted: evicted)
    }

    public mutating func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        pinnedIDs.subtract(ids)
        slots = slots.map { id in id.flatMap { ids.contains($0) ? nil : $0 } }
    }

    public mutating func validate() {
        // Never trust a persisted pointer or slot array before indexing it.
        items = Array(items.prefix(Self.capacity))
        var ids = Set<UUID>(), paths = Set<URL>()
        items = items.filter { ids.insert($0.id).inserted && paths.insert($0.url).inserted }
        pinnedIDs.formIntersection(ids)
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
