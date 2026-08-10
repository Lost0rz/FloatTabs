import AppKit
import XCTest
@testable import FloatTabs

@MainActor
final class AppCommandControllerTests: XCTestCase {
    func testOnlyExplicitFloatTabsShortcutsAreMatched() {
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
            .quickURL
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

    func testQuickURLDismissesForEscapeSecondCommandLAndOutsideClickOnly() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let host = NSView(frame: window.contentView?.bounds ?? .zero)
        window.contentView = host

        let overlay = QuickURLOverlayView(frame: NSRect(x: 100, y: 300, width: 300, height: 52))
        host.addSubview(overlay)
        overlay.present(url: URL(string: "https://example.com")!, in: window)

        XCTAssertTrue(AppCommandController.presentedQuickURLOverlay(in: window) === overlay)

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
        XCTAssertTrue(AppCommandController.shouldDismissQuickURL(for: escape, overlay: overlay))

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
        XCTAssertTrue(AppCommandController.shouldDismissQuickURL(for: commandL, overlay: overlay))

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
        XCTAssertFalse(AppCommandController.shouldDismissQuickURL(for: insideClick, overlay: overlay))

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
        XCTAssertTrue(AppCommandController.shouldDismissQuickURL(for: outsideClick, overlay: overlay))
    }
}
