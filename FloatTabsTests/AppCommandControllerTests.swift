import AppKit
import XCTest
@testable import FloatTabs

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
            AppCommandController.command(characters: "\t", keyCode: 48, modifiers: [.control]),
            .nextSlot
        )
        XCTAssertEqual(
            AppCommandController.command(characters: "\t", keyCode: 48, modifiers: [.control, .shift]),
            .previousSlot
        )

        XCTAssertNil(AppCommandController.command(characters: "a", keyCode: 0, modifiers: [.command]))
        XCTAssertNil(AppCommandController.command(characters: "c", keyCode: 8, modifiers: [.command]))
        XCTAssertNil(AppCommandController.command(characters: "1", keyCode: 18, modifiers: [.command, .shift]))
    }
}
