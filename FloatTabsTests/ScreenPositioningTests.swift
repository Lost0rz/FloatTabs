import AppKit
import XCTest
@testable import FloatTabs

final class ScreenPositioningTests: XCTestCase {
    func testCenteredFrameUsesRequestedSizeWhenItFits() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 900)

        let frame = ScreenPositioning.centeredFrame(
            size: NSSize(width: 430, height: 820),
            in: visible
        )

        XCTAssertEqual(frame.size, NSSize(width: 430, height: 820))
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 0.001)
        XCTAssertEqual(frame.midY, visible.midY, accuracy: 0.001)
    }

    func testCenteredFrameClampsOversizedPanelToVisibleFrame() {
        let visible = NSRect(x: 100, y: 50, width: 800, height: 600)

        let frame = ScreenPositioning.centeredFrame(
            size: NSSize(width: 1200, height: 900),
            in: visible
        )

        XCTAssertEqual(frame, visible)
    }

    func testClampedFrameKeepsPanelInsideVisibleFrame() {
        let visible = NSRect(x: 100, y: 50, width: 800, height: 600)
        let offscreen = NSRect(x: 850, y: -100, width: 430, height: 500)

        let frame = ScreenPositioning.clampedFrame(offscreen, to: visible)

        XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY)
    }
}
