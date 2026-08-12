import AppKit
import KeyboardShortcuts
import XCTest
@testable import FloatTabs

@MainActor
final class AppCommandControllerTests: XCTestCase {
    func testOnlyExplicitFloatTabsShortcutsAreMatched() {
        // KeyboardShortcuts intentionally persists user customizations. This
        // test verifies the catalog defaults, so isolate it from the developer
        // machine's current Settings choices and restore them afterward.
        let originalShortcuts = AppShortcutCatalog.allBindings.map {
            ($0.name, KeyboardShortcuts.getShortcut(for: $0.name))
        }
        KeyboardShortcuts.reset(AppShortcutCatalog.allNames)
        defer {
            for (name, shortcut) in originalShortcuts {
                KeyboardShortcuts.setShortcut(shortcut, for: name)
            }
        }

        XCTAssertEqual(
            AppCommandController.command(characters: "1", keyCode: 18, modifiers: [.command]),
            .selectSlot(1)
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "9", keyCode: 25, modifiers: [.command]),
            .selectSlot(9)
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "t", keyCode: 17, modifiers: [.command]),
            .addWebApp
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "l", keyCode: 37, modifiers: [.command]),
            .addressBar
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "r", keyCode: 15, modifiers: [.command]),
            .reload
        )
        XCTAssertEqual(
            AppCommandController.command(characters: ",", keyCode: 43, modifiers: [.command]),
            .settings
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "+", keyCode: 24, modifiers: [.command, .shift]),
            .zoomIn
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "=", keyCode: 24, modifiers: [.command]),
            .zoomIn
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "-", keyCode: 27, modifiers: [.command]),
            .zoomOut
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "0", keyCode: 29, modifiers: [.command]),
            .resetZoom
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "\t", keyCode: 48, modifiers: [.control]),
            .nextSlot
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "\t", keyCode: 48, modifiers: [.control, .shift]),
            .previousSlot
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "h", keyCode: 4, modifiers: [.command, .shift]),
            .returnHome
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "H", keyCode: 4, modifiers: [.command, .shift]),
            .returnHome
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "p", keyCode: 35, modifiers: [.command, .shift]),
            .togglePin
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "P", keyCode: 35, modifiers: [.command, .shift]),
            .togglePin
        )

        XCTAssertNil(AppCommandController.command(characters: "a", keyCode: 0, modifiers: [.command]))
        XCTAssertNil(AppCommandController.command(characters: "c", keyCode: 8, modifiers: [.command]))
        XCTAssertNil(AppCommandController.command(characters: "1", keyCode: 18, modifiers: [.command, .shift]))
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
        let original = KeyboardShortcuts.getShortcut(for: .addressBar)
        let custom = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .option])
        KeyboardShortcuts.setShortcut(custom, for: .addressBar)
        defer { KeyboardShortcuts.setShortcut(original, for: .addressBar) }

        XCTAssertNil(
            AppCommandController.command(
                characters: "l",
                keyCode: UInt16(KeyboardShortcuts.Key.l.rawValue),
                modifiers: [.command]
            )
        )
        XCTAssertEqual(
            AppCommandController.command(
                characters: "k",
                keyCode: UInt16(KeyboardShortcuts.Key.k.rawValue),
                modifiers: [.command, .option]
            ),
            .addressBar
        )
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
}
