import AppKit
import KeyboardShortcuts
import XCTest
@testable import FloatTabs

@MainActor
final class AppCommandControllerTests: XCTestCase {
    func testOnlyExplicitFloatTabsShortcutsAreMatched() {
        XCTAssertEqual(
            defaultCommand(keyCode: 18, modifiers: [.command]),
            .selectSlot(1)
        )
        XCTAssertEqual(
            defaultCommand(keyCode: 25, modifiers: [.command]),
            .selectSlot(9)
        )
        XCTAssertEqual(
            defaultCommand(keyCode: 17, modifiers: [.command]),
            .addWebApp
        )
        XCTAssertEqual(
            defaultCommand(keyCode: 37, modifiers: [.command]),
            .addressBar
        )
        XCTAssertEqual(
            defaultCommand(keyCode: 15, modifiers: [.command]),
            .reload
        )
        XCTAssertEqual(
            defaultCommand(keyCode: 43, modifiers: [.command]),
            .settings
        )
        XCTAssertEqual(
            defaultCommand(keyCode: 24, modifiers: [.command, .shift]),
            .zoomIn
        )
        XCTAssertEqual(
            defaultCommand(keyCode: 24, modifiers: [.command]),
            .zoomIn
        )
        XCTAssertEqual(
            defaultCommand(keyCode: 27, modifiers: [.command]),
            .zoomOut
        )
        XCTAssertEqual(
            defaultCommand(keyCode: 29, modifiers: [.command]),
            .resetZoom
        )
        XCTAssertEqual(
            defaultCommand(keyCode: 48, modifiers: [.control]),
            .nextSlot
        )
        XCTAssertEqual(
            defaultCommand(keyCode: 48, modifiers: [.control, .shift]),
            .previousSlot
        )
        XCTAssertEqual(
            defaultCommand(keyCode: 4, modifiers: [.command, .shift]),
            .returnHome
        )
        XCTAssertEqual(
            defaultCommand(keyCode: 35, modifiers: [.command, .shift]),
            .togglePin
        )

        XCTAssertNil(defaultCommand(keyCode: 0, modifiers: [.command]))
        XCTAssertNil(defaultCommand(keyCode: 8, modifiers: [.command]))
        XCTAssertNil(defaultCommand(keyCode: 18, modifiers: [.command, .shift]))
    }

    func testEveryPreviouslyFixedShortcutHasAnIndividualBinding() {
        XCTAssertEqual(AppShortcutCatalog.slotBindings.count, 9)
        XCTAssertEqual(AppShortcutCatalog.navigationBindings.count, 6)
        XCTAssertEqual(AppShortcutCatalog.viewBindings.count, 4)
        XCTAssertEqual(AppShortcutCatalog.applicationBindings.count, 1)
        XCTAssertEqual(AppShortcutCatalog.allBindings.count, 20)
        XCTAssertEqual(Set(AppShortcutCatalog.allNames.map(\.rawValue)).count, 20)
    }

    func testConfiguredAddressShortcutReplacesDefaultCommandL() {
        let custom = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .option])
        let shortcutFor: (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? = { name in
            name == .addressBar ? custom : name.initialShortcut
        }

        XCTAssertNil(
            AppShortcutCatalog.command(
                keyCode: UInt16(KeyboardShortcuts.Key.l.rawValue),
                modifiers: [.command],
                shortcutFor: shortcutFor
            )
        )
        XCTAssertEqual(
            AppShortcutCatalog.command(
                keyCode: UInt16(KeyboardShortcuts.Key.k.rawValue),
                modifiers: [.command, .option],
                shortcutFor: shortcutFor
            ),
            .addressBar
        )
    }

    func testDefaultCatalogAndGlobalToggleHaveNoDuplicateShortcuts() {
        let names: [KeyboardShortcuts.Name] = [
            .toggleFloatTabs,
        ] + AppShortcutCatalog.allNames
        let shortcuts = names.compactMap(\.initialShortcut)

        XCTAssertEqual(shortcuts.count, names.count)
        XCTAssertEqual(Set(shortcuts).count, shortcuts.count)
    }

    func testAddressBarDismissesForEscapeSecondCommandLAndOutsideClickOnly() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let host = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = host

        let overlay = AddressOverlayView(frame: NSRect(x: 100, y: 300, width: 300, height: 52))
        host.addSubview(overlay)
        overlay.present(url: URL(string: "https://example.com")!, in: window)

        XCTAssertTrue(AppCommandController.presentedAddressOverlay(in: window) === overlay)

        let escape = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        )!
        XCTAssertTrue(AppCommandController.shouldDismissAddressBar(for: escape, overlay: overlay))

        let commandL = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "l",
            charactersIgnoringModifiers: "l",
            isARepeat: false,
            keyCode: 37
        )!
        XCTAssertTrue(AppCommandController.shouldDismissAddressBar(for: commandL, overlay: overlay))

        let insideClick = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 150, y: 320),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
        XCTAssertFalse(AppCommandController.shouldDismissAddressBar(for: insideClick, overlay: overlay))

        let outsideClick = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 40, y: 40),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        )!
        XCTAssertTrue(AppCommandController.shouldDismissAddressBar(for: outsideClick, overlay: overlay))
    }

    func testAddressOverlayFieldEditorReturnCommitsEnteredValue() {
        let overlay = AddressOverlayView()
        let editor = NSTextView()
        var committed: String?
        overlay.onCommit = { value in
            committed = value
            return true
        }
        overlay.field.stringValue = "example.com/project"

        XCTAssertTrue(
            overlay.control(
                overlay.field,
                textView: editor,
                doCommandBy: #selector(NSResponder.insertNewline(_:))
            )
        )
        XCTAssertEqual(committed, "example.com/project")
    }

    func testBlankNewWebAppNameFallsBackToURLHost() {
        let store = TabStore(repository: MemoryProfileRepository())
        let url = URL(string: "https://www.example.com/projects/123")!

        let added = store.add(name: "   ", homeURL: url)

        XCTAssertEqual(added?.name, "example.com")
        XCTAssertEqual(added?.homeURL, url)
        XCTAssertEqual(store.activeTabID, added?.id)
    }

    func testURLFallbackDisplayNameKeepsSubdomainAndDropsLeadingWWW() {
        XCTAssertEqual(
            WebAppURL.defaultDisplayName(
                for: URL(string: "https://www.github.com/openai")!
            ),
            "github.com"
        )
        XCTAssertEqual(
            WebAppURL.defaultDisplayName(
                for: URL(string: "https://docs.example.com/start")!
            ),
            "docs.example.com"
        )
    }

    func testStatusItemToggleRunsAfterTwoMainQueueTurns() async {
        let firstQueuedTurn = expectation(description: "first queued turn")
        let toggleRan = expectation(description: "toggle ran")

        StatusItemController.scheduleAfterStatusItemTracking {
            toggleRan.fulfill()
        }

        DispatchQueue.main.async {
            firstQueuedTurn.fulfill()
        }

        await fulfillment(
            of: [firstQueuedTurn, toggleRan],
            timeout: 1,
            enforceOrder: true
        )
    }

    private func defaultCommand(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> AppCommand? {
        AppShortcutCatalog.command(
            keyCode: keyCode,
            modifiers: modifiers,
            shortcutFor: \.initialShortcut
        )
    }
}