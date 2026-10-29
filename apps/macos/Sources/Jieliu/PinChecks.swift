import AppKit
import TrayCore

enum PinChecks {
    static func run(root parent: URL) throws {
        let root = parent.appendingPathComponent("pin-checks")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "app.jieliu.pin-checks." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); preferences.removePersistentDomain(forName: suite) }
        let model = AppModel(demo: true, preferences: preferences)
        model.animations = false
        let shots = try (0..<9).map { index -> Capture in
            let file = root.appendingPathComponent("pin-\(index).png")
            try DemoSupport.fixture(0).write(to: file)
            return Capture(url: file, date: Date(timeIntervalSince1970: Double(index)), width: 640, height: 400)
        }
        for capture in shots.prefix(8) { model.receive(capture) }
        let view = TrayView(model: model); view.frame = CGRect(x: 0, y: 0, width: 1100, height: 270)
        view.expanded = true; view.openness = 1; view.spread = 1
        model.selection = [shots[0].id, shots[1].id]
        let menu = view.pinMenu(for: shots[0].id)!
        precondition(model.selection.count == 2 && menu.items[0].title == model.text("固定", "Pin"))
        view.applyPinMenu(menu.items[0])
        precondition(model.selectionIsPinned && model.history.pinnedIDs.count == 2)
        // A menu action keeps its displayed meaning even if selection changes while it is open.
        model.selection = [shots[0].id]; view.applyPinMenu(menu.items[0])
        precondition(model.selectionIsPinned)
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "p", charactersIgnoringModifiers: "p", isARepeat: false, keyCode: 35)!
        view.keyDown(with: key)
        precondition(!model.history.pinnedIDs.contains(shots[0].id) && model.history.pinnedIDs.contains(shots[1].id))
        _ = view.pinMenu(for: shots[2].id)
        precondition(model.selection == [shots[2].id], "Context menu must target the clicked capture")
        view.menuWillOpen(menu); precondition(view.menuOpen)
        view.menuDidClose(menu); precondition(!view.menuOpen)

        func frame() -> Data {
            let image = NSImage(size: view.bounds.size)
            image.lockFocusFlipped(true); view.draw(view.bounds); image.unlockFocus()
            return image.tiffRepresentation!
        }
        for concept in Concept.allCases {
            model.concept = concept; view.synchronizeState(); view.expanded = true; view.openness = 1; view.spread = 1
            model.selection = [shots[7].id]; model.setSelectedPins(false)
            let before = frame()
            let element = (view.accessibilityChildren() as! [ShotAccessibility]).first { $0.isAccessibilitySelected() }!
            precondition(element.accessibilityValue() == nil)
            model.setSelectedPins(true)
            precondition(before != frame(), "Pin badge is missing in \(concept)")
            precondition(element.accessibilityValue() as? String == model.text("已固定", "Pinned"))
            model.setSelectedPins(false)
            precondition(element.accessibilityValue() == nil)
        }
        model.selection = Set(shots.prefix(8).map(\.id)); model.setSelectedPins(true)
        var arrivals = 0, notices: [String] = []
        model.onCapture = { _, _ in arrivals += 1 }
        model.onNotice = { notices.append($0); view.toast($0) }
        model.receive(shots[8])
        precondition(arrivals == 0 && notices.count == 1 && view.message == notices[0])
        precondition(model.history.items.count == 8 && model.history.total == 8 && model.history.nextWriteSlot == nil)
        precondition(FileManager.default.fileExists(atPath: shots[8].url.path))
        model.selection = [shots[0].id]; model.removeSelection()
        precondition(FileManager.default.fileExists(atPath: shots[0].url.path))
        model.receive(shots[8])
        precondition(arrivals == 1 && model.history.slots[0] == shots[8].id && model.history.pinnedIDs.count == 7)
        print("PASS: Mac Pin menu/P key, batch selection, A/B/C badge, live accessibility state and full-tray archive notice")
    }
}
