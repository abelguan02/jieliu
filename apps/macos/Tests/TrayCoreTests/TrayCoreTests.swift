import Foundation
import TrayCore

func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a == b, "Expected \(a) == \(b)", file: file, line: line) }
func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a != b) }
func XCTAssertTrue(_ value: Bool) { precondition(value) }
func XCTAssertFalse(_ value: Bool) { precondition(!value) }
func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }

@main struct TrayCoreTests {
    static func main() throws {
        let suite = Self()
        suite.testRingWrapsAndDoesNotReorderSlots()
        try suite.testRemovalLeavesFileAndDoesNotResetPointer()
        try suite.testArchiveDoesNotOverwriteExistingFile()
        suite.testMetadataRectangleParsing()
        suite.testDuplicateDoesNotAdvancePointer()
        print("PASS: 5 core checks (ring order, removal/persistence, collision-safe archive, metadata, deduplication)")
    }
    func shot(_ i: Int) -> Capture { Capture(url: URL(fileURLWithPath: "/tmp/shot-\(i).png"), width: 1440, height: 900) }
    func testRingWrapsAndDoesNotReorderSlots() {
        var history = TrayHistory()
        let shots = (0..<10).map(shot)
        for s in shots { history.insert(s) }
        XCTAssertEqual(history.items.count, 8)
        XCTAssertEqual(history.writePointer, 2)
        XCTAssertEqual(history.slots[0], shots[8].id)
        XCTAssertEqual(history.slots[1], shots[9].id)
        XCTAssertEqual(history.slots[2], shots[2].id)
        XCTAssertEqual(history.items.first?.id, shots[9].id)
    }
    func testRemovalLeavesFileAndDoesNotResetPointer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("capture.png")
        try Data([1,2,3]).write(to: file)
        let capture = Capture(url: file, width: 1, height: 1)
        var history = TrayHistory(); history.insert(capture); history.remove([capture.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(history.writePointer, 1)
        XCTAssertNil(history.slots[0])
        try history.save(to: root.appendingPathComponent("history.json"))
        let restored = try TrayHistory.load(from: root.appendingPathComponent("history.json"))
        XCTAssertTrue(restored.items.isEmpty)
        XCTAssertEqual(restored.total, 1)
    }
    func testArchiveDoesNotOverwriteExistingFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let archive = root.appendingPathComponent("archive")
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("same.png")
        let existing = archive.appendingPathComponent("same.png")
        try Data([1]).write(to: source); try Data([2]).write(to: existing)
        let result = try CaptureFiles.archive(source, into: archive)
        XCTAssertNotEqual(result, existing)
        XCTAssertEqual(try Data(contentsOf: existing), Data([2]))
        XCTAssertEqual(try Data(contentsOf: result), Data([1]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try CaptureFiles.archive(result, into: archive), result)
    }
    func testMetadataRectangleParsing() {
        XCTAssertEqual(CaptureRect.parse("{{-1440, 32}, {800, 600}}"), CaptureRect(x: -1440, y: 32, width: 800, height: 600))
        XCTAssertNil(CaptureRect.parse([0, 0, -3, 5]))
        XCTAssertNil(CaptureRect.parse("malformed"))
    }
    func testDuplicateDoesNotAdvancePointer() {
        var history = TrayHistory(); let s = shot(0)
        history.insert(s); history.insert(s)
        XCTAssertEqual(history.total, 1)
        XCTAssertEqual(history.writePointer, 1)
        let replacement=shot(0)
        history.insert(replacement)
        XCTAssertEqual(history.items.map(\.id),[replacement.id])
        XCTAssertEqual(history.total,2)
        XCTAssertEqual(history.writePointer,2)
        XCTAssertNil(history.slots[0])
        XCTAssertEqual(history.slots[1],replacement.id)
    }
}
