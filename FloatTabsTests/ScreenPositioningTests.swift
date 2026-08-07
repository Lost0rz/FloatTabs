import AppKit
import WebKit
import XCTest
@testable import FloatTabs

final class PanelMetricsTests: XCTestCase {
    func testDefaultViewportProducesExpectedTotalPanelSize() {
        XCTAssertEqual(
            PanelMetrics.panelSize(forViewport: NSSize(width: 430, height: 820)),
            NSSize(width: 506, height: 820)
        )
        XCTAssertEqual(PanelMetrics.defaultPanelSize, NSSize(width: 506, height: 820))
    }

    func testMinimumViewportProducesExpectedMinimumPanelSize() {
        XCTAssertEqual(
            PanelMetrics.panelSize(forViewport: NSSize(width: 320, height: 400)),
            NSSize(width: 396, height: 400)
        )
        XCTAssertEqual(PanelMetrics.minimumPanelSize, NSSize(width: 396, height: 400))
    }

    func testPanelSizeProducesViewportSizeWithoutControlZone() {
        XCTAssertEqual(
            PanelMetrics.viewportSize(forPanelSize: NSSize(width: 506, height: 820)),
            NSSize(width: 430, height: 820)
        )
    }

    func testResizeCannotShrinkViewportBelowMinimum() {
        let panelSize = PanelMetrics.clampedPanelSize(NSSize(width: 250, height: 180))
        let viewportSize = PanelMetrics.viewportSize(forPanelSize: panelSize)

        XCTAssertEqual(panelSize, NSSize(width: 396, height: 400))
        XCTAssertEqual(viewportSize, PanelMetrics.minimumViewportSize)
    }

    func testPerimeterDragBandLeavesNativeResizeLaneAndCornersFree() {
        XCTAssertGreaterThan(PanelMetrics.perimeterDragResizeInset, 0)
        XCTAssertGreaterThan(PanelMetrics.perimeterDragBandWidth, 0)
        XCTAssertGreaterThan(
            PanelMetrics.perimeterDragCornerExclusion,
            PanelMetrics.perimeterDragBandWidth
        )
    }
}

final class ScreenPositioningTests: XCTestCase {
    func testCenteredFrameUsesRequestedSizeWhenItFits() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 1000)

        let frame = ScreenPositioning.centeredFrame(
            size: PanelMetrics.defaultPanelSize,
            in: visible
        )

        XCTAssertEqual(frame.size, NSSize(width: 506, height: 820))
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

    func testClampedFrameKeepsPanelInsideVisibleFrameAndMinimumSize() {
        let visible = NSRect(x: 100, y: 50, width: 800, height: 600)
        let offscreen = NSRect(x: 850, y: -100, width: 250, height: 200)

        let frame = ScreenPositioning.clampedFrame(offscreen, to: visible)

        XCTAssertEqual(frame.size, PanelMetrics.minimumPanelSize)
        XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY)
    }

    func testRestoredFrameStaysOnConnectedDisplayWhenItStillIntersects() {
        let primary = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        let saved = NSRect(x: 1700, y: 100, width: 506, height: 820)

        let restored = ScreenPositioning.restoredFrame(
            saved,
            visibleFrames: [primary, secondary],
            fallbackVisibleFrame: primary
        )

        XCTAssertGreaterThanOrEqual(restored.minX, secondary.minX)
        XCTAssertLessThanOrEqual(restored.maxX, secondary.maxX)
    }

    func testSavedFrameOutsideAllDisplaysFallsBackAndClamps() {
        let primary = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        let disconnectedDisplayFrame = NSRect(x: -3000, y: 200, width: 900, height: 850)

        let restored = ScreenPositioning.restoredFrame(
            disconnectedDisplayFrame,
            visibleFrames: [primary, secondary],
            fallbackVisibleFrame: primary
        )

        XCTAssertGreaterThanOrEqual(restored.minX, primary.minX)
        XCTAssertGreaterThanOrEqual(restored.minY, primary.minY)
        XCTAssertLessThanOrEqual(restored.maxX, primary.maxX)
        XCTAssertLessThanOrEqual(restored.maxY, primary.maxY)
    }
}

final class PanelFrameStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PanelFrameStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFrameRoundTripsThroughUserDefaults() {
        let store = PanelFrameStore(defaults: defaults, key: "frame")
        let expected = NSRect(x: 210, y: 120, width: 640, height: 760)

        store.saveFrame(expected)

        XCTAssertEqual(store.loadFrame(), expected)
    }

    func testInvalidSerializedFrameIsRejected() {
        defaults.set("not-a-frame", forKey: "frame")
        let store = PanelFrameStore(defaults: defaults, key: "frame")

        XCTAssertNil(store.loadFrame())
    }
}

@MainActor
final class PanelRootViewLayoutTests: XCTestCase {
    func testDefaultPanelLaysOutExactControlZoneViewportAndDragOverlay() {
        let webView = WKWebView(frame: .zero)
        let root = PanelRootView(webView: webView)
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            root.externalControlZoneView.frame.width,
            PanelMetrics.externalControlZoneWidth,
            accuracy: 0.001
        )
        XCTAssertEqual(
            root.webPanelContainerView.frame.size,
            PanelMetrics.defaultViewportSize
        )
        XCTAssertEqual(root.perimeterDragView.frame, root.bounds)
    }
}

@MainActor
final class PanelPerimeterDragHitTestingTests: XCTestCase {
    func testAllFourPerimeterBandsAreInteractive() {
        let webView = WKWebView(frame: .zero)
        let root = PanelRootView(webView: webView)
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let inset = PanelMetrics.perimeterDragResizeInset
        let halfBand = PanelMetrics.perimeterDragBandWidth / 2
        let bounds = root.bounds
        let points = [
            NSPoint(x: bounds.midX, y: bounds.minY + inset + halfBand),
            NSPoint(x: bounds.midX, y: bounds.maxY - inset - halfBand),
            NSPoint(x: bounds.minX + inset + halfBand, y: bounds.midY),
            NSPoint(x: bounds.maxX - inset - halfBand, y: bounds.midY),
        ]

        for point in points {
            XCTAssertTrue(
                root.hitTest(point) is PanelPerimeterDragView,
                "Expected perimeter drag hit at \(point)"
            )
        }
    }

    func testOutermostResizeLaneIsNotConsumedByDragOverlay() {
        let view = PanelPerimeterDragView(
            frame: NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        )

        let point = NSPoint(x: 1, y: view.bounds.midY)
        XCTAssertNil(view.hitTest(point))
    }

    func testCornersRemainFreeForDiagonalResize() {
        let view = PanelPerimeterDragView(
            frame: NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        )

        let inset = PanelMetrics.perimeterDragResizeInset
        let halfBand = PanelMetrics.perimeterDragBandWidth / 2
        let point = NSPoint(
            x: inset + halfBand,
            y: view.bounds.maxY - inset - halfBand
        )

        XCTAssertNil(view.hitTest(point))
    }

    func testBlankExternalControlZoneStillPassesThroughAwayFromPerimeter() {
        let webView = WKWebView(frame: .zero)
        let root = PanelRootView(webView: webView)
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let blankPoint = NSPoint(
            x: PanelMetrics.externalControlZoneWidth / 2,
            y: root.bounds.midY
        )

        XCTAssertNil(root.hitTest(blankPoint))
    }

    func testWebsiteCenterIsNotConsumedByDragOverlay() {
        let webView = WKWebView(frame: .zero)
        let root = PanelRootView(webView: webView)
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let websitePoint = NSPoint(
            x: PanelMetrics.externalControlZoneWidth + PanelMetrics.defaultViewportSize.width / 2,
            y: root.bounds.midY
        )

        XCTAssertFalse(root.hitTest(websitePoint) is PanelPerimeterDragView)
    }
}
