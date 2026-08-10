from pathlib import Path

path = Path("FloatTabsTests/ExternalShellTests.swift")
text = path.read_text(encoding="utf-8")

old = '''    func testTabContextMenuStartsWithReturnToHome() {
        let (_, zone) = makeZoneHarness()
        let active = makeProfile(order: 0, name: "GPT")
        zone.apply(profiles: [active], activeTabID: active.id)
        zone.layoutSubtreeIfNeeded()
'''
new = '''    func testTabContextMenuStartsWithReturnToHome() {
        let (_, zone) = makeZoneHarness()
        let active = makeProfile(order: 0, name: "GPT")
        zone.apply(profiles: [active], activeTabID: active.id)
        zone.setResidentSlotIDs([active.id])
        zone.layoutSubtreeIfNeeded()
'''
if text.count(old) != 1:
    raise RuntimeError(f"expected one resident fixture anchor, found {text.count(old)}")
text = text.replace(old, new, 1)

anchor = '''        XCTAssertFalse(actionTitles.contains("Rename…"))
    }

    func testActiveInactiveAndAddGeometryMatchDesignTokens() {
'''
replacement = '''        XCTAssertFalse(actionTitles.contains("Rename…"))
    }

    func testReleasedTabDisablesReloadWithoutCreatingRuntime() {
        let (_, zone) = makeZoneHarness()
        let released = makeProfile(order: 0, name: "Released")
        zone.apply(profiles: [released], activeTabID: released.id)
        zone.setResidentSlotIDs([])
        zone.layoutSubtreeIfNeeded()

        let tab = try! XCTUnwrap(zone.tabView(for: released.id))
        let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: tab.frame.midX, y: tab.frame.midY),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        )!
        let menu = try! XCTUnwrap(tab.menu(for: event))
        let reload = try! XCTUnwrap(menu.item(withTitle: "Reload"))

        XCTAssertFalse(reload.isEnabled)
    }

    func testActiveInactiveAndAddGeometryMatchDesignTokens() {
'''
if text.count(anchor) != 1:
    raise RuntimeError(f"expected one released-test anchor, found {text.count(anchor)}")
text = text.replace(anchor, replacement, 1)

path.write_text(text, encoding="utf-8")
print("Stage 6C test fixture corrected")
