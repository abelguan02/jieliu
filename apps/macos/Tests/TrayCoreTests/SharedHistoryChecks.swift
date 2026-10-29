import Foundation
import TrayCore

enum SharedHistoryChecks {
    private struct Scenario: Decodable {
        let name: String, initial: [String], steps: [Step], expected: Expected
    }
    private struct Step: Decodable {
        let op: String, id: String?, path: String?, ids: [String]?
    }
    private struct Expected: Decodable {
        let items: [String], slots: [String?], pinned: [String]
        let pointer: Int, total: Int, status: String?, evicted: String?, next: Int?
    }

    static func run() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../tests/fixtures/history.json").standardizedFileURL
        let scenarios = try JSONDecoder().decode([Scenario].self, from: Data(contentsOf: fixture))
        for scenario in scenarios {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let historyURL = root.appendingPathComponent("history.json")
            var history = TrayHistory(), ids: [String: UUID] = [:], captures: [String: Capture] = [:]
            var deleted = Set<URL>(), result: InsertionResult?
            func id(_ name: String) -> UUID {
                if let value = ids[name] { return value }
                let value = UUID(); ids[name] = value; return value
            }
            func capture(_ name: String, path: String? = nil) throws -> Capture {
                if let value = captures[name] { return value }
                let url = root.appendingPathComponent((path ?? name) + ".png")
                try Data([1, 2, 3]).write(to: url)
                var value = Capture(url: url, width: 10, height: 10); value.id = id(name)
                captures[name] = value; return value
            }
            for name in scenario.initial { history.insert(try capture(name)) }
            for step in scenario.steps {
                switch step.op {
                case "insert": result = history.insert(try capture(step.id!, path: step.path))
                case "pin", "unpin": history.setPinned(Set(step.ids!.map(id)), pinned: step.op == "pin")
                case "remove": history.remove(Set(step.ids!.map(id)))
                case "deleteFile":
                    let url = captures[step.id!]!.url
                    try FileManager.default.removeItem(at: url); deleted.insert(url)
                case "reload", "legacyReload":
                    try history.save(to: historyURL)
                    if step.op == "legacyReload" {
                        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: historyURL)) as! [String: Any]
                        json.removeValue(forKey: "pinnedIDs")
                        try JSONSerialization.data(withJSONObject: json).write(to: historyURL)
                    }
                    history = try TrayHistory.load(from: historyURL)
                default: preconditionFailure("Unknown history operation: \(step.op)")
                }
            }
            let expected = scenario.expected
            func check(_ value: Bool, _ field: String) { precondition(value, "Shared history \(scenario.name): \(field)") }
            check(history.items.map(\.id) == expected.items.map(id), "items")
            check(history.slots == expected.slots.map { $0.map(id) }, "slots")
            check(history.pinnedIDs == Set(expected.pinned.map(id)), "pins")
            check(history.writePointer == expected.pointer && history.total == expected.total, "cursor/total")
            check(history.nextWriteSlot == expected.next, "next write slot")
            check(result?.status.rawValue == expected.status, "insert status")
            check(result?.evicted?.id == expected.evicted.map(id), "evicted")
            for value in captures.values where !deleted.contains(value.url) {
                check(try Data(contentsOf: value.url) == Data([1, 2, 3]), "original file preserved")
            }
        }
        print("PASS: \(scenarios.count) shared history fixtures (empty slots, pins, full tray, versions and persistence)")
    }
}
