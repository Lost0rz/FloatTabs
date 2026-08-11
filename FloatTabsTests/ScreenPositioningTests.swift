import AppKit
import WebKit
import XCTest
@testable import FloatTabs

final class PanelMetricsTests: XCTestCase {
    func testDefaultViewportProducesExpectedTotalPanelSize() {
        XCTAssertEqual(
            PanelMetrics.panelSize(forViewport: NSSize(width: 600, height: 820)),
            NSSize(width: 688, height: 844)
        )
        XCTAssertEqual(PanelMetrics.defaultPanelSize, NSSize(width: 688, height: 844))
    }

    func testMinimumViewportProducesExpectedMinimumPanelSize() {
        XCTAssertEqual(
            PanelMetrics.panelSize(forViewport: NSSize(width: 320, height: 400)),
            NSSize(width: 408, height: 424)
        )
        XCTAssertEqual(PanelMetrics.minimumPanelSize, NSSize(width: 408, height: 424))
    }

    func testPanelSizeProducesViewportSizeWithoutShellChrome() {
        XCTAssertEqual(
            PanelMetrics.viewportSize(forPanelSize: NSSize(width: 688, height: 844)),
            NSSize(width: 600, height: 820)
        )
    }

    func testResizeCannotShrinkViewportBelowMinimum() {
        let panelSize = PanelMetrics.clampedPanelSize(NSSize(width: 250, height: 180))
        let viewportSize = PanelMetrics.viewportSize(forPanelSize: panelSize)

        XCTAssertEqual(panelSize, NSSize(width: 408, height: 424))
        XCTAssertEqual(viewportSize, PanelMetrics.minimumViewportSize)
    }

    func testMovementFrameUsesLargeInvisibleTargetAndThinVisibleOutline() {
        XCTAssertEqual(PanelMetrics.outerInteractionGutter, 12)
        XCTAssertEqual(PanelMetrics.innerMovementOverlap, 10)
        XCTAssertEqual(
            PanelMetrics.outerInteractionGutter + PanelMetrics.innerMovementOverlap,
            22
        )
        XCTAssertGreaterThan(
            PanelMetrics.outerInteractionGutter,
            PanelMetrics.innerMovementOverlap
        )
        XCTAssertGreaterThanOrEqual(
            PanelMetrics.webRightInteractionSafety,
            PanelMetrics.outerInteractionGutter
        )
        XCTAssertLessThan(
            PanelMetrics.interactionBorderLineWidth,
            PanelMetrics.outerInteractionGutter
        )
        XCTAssertEqual(PanelMetrics.structuralBorderWidth, 0)
        XCTAssertEqual(PanelMetrics.resizeHandleInset, 0)
    }
}

final class ScreenPositioningTests: XCTestCase {
    func testCenteredFrameUsesRequestedSizeWhenItFits() {
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 1000)

        let frame = ScreenPositioning.centeredFrame(
            size: PanelMetrics.defaultPanelSize,
            in: visible
        )

        XCTAssertEqual(frame.size, NSSize(width: 688, height: 844))
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

    func testFollowPreferredViewportResizesPanelAndPreservesTopEdgeWhenPossible() {
        let visible = NSRect(x: 0, y: 0, width: 1600, height: 1200)
        let current = NSRect(x: 200, y: 220, width: 518, height: 844)
        let frame = ScreenPositioning.frameFollowingPreferredViewport(
            currentFrame: current,
            preferredViewportSize: NSSize(width: 600, height: 800),
            followPreferredSize: true,
            visibleFrame: visible
        )

        XCTAssertEqual(frame.size, PanelMetrics.panelSize(forViewport: NSSize(width: 600, height: 800)))
        XCTAssertEqual(frame.minX, current.minX, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, current.maxY, accuracy: 0.001)
    }

    func testDisabledPreferredViewportFollowLeavesFrameUntouched() {
        let visible = NSRect(x: 0, y: 0, width: 1600, height: 1200)
        let current = NSRect(x: 200, y: 220, width: 518, height: 844)
        let frame = ScreenPositioning.frameFollowingPreferredViewport(
            currentFrame: current,
            preferredViewportSize: NSSize(width: 900, height: 850),
            followPreferredSize: false,
            visibleFrame: visible
        )
        XCTAssertEqual(frame, current)
    }

    func testRestoredFrameStaysOnConnectedDisplayWhenItStillIntersects() {
        let primary = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        let saved = NSRect(
            x: 1700,
            y: 100,
            width: PanelMetrics.defaultPanelSize.width,
            height: PanelMetrics.defaultPanelSize.height
        )

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
        XCTAssertNil(store.loadFrame())
    }
}

@MainActor
final class FloatingPanelResizePolicyTests: XCTestCase {
    func testNativeResizeStyleIsDisabled() {
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize))
        XCTAssertFalse(panel.styleMask.contains(.resizable))
    }

    func testCrossDisplayRearmOnlyTargetsHiddenStaleActiveSpaceWindow() {
        let screenA = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let screenB = NSRect(x: 1920, y: 183, width: 1024, height: 666)

        XCTAssertTrue(
            FloatingPanel.shouldRearmReusableFullscreenWindow(
                fullscreenState: .notInFullscreen,
                isSameWebView: true,
                windowIsVisible: false,
                windowIsOnActiveSpace: true,
                windowScreenFrame: screenB,
                targetScreenFrame: screenA
            )
        )

        XCTAssertFalse(
            FloatingPanel.shouldRearmReusableFullscreenWindow(
                fullscreenState: .notInFullscreen,
                isSameWebView: true,
                windowIsVisible: false,
                windowIsOnActiveSpace: false,
                windowScreenFrame: screenB,
                targetScreenFrame: screenA
            ),
            "The real-Mac success baseline had activeSpace=false and must remain untouched"
        )

        XCTAssertFalse(
            FloatingPanel.shouldRearmReusableFullscreenWindow(
                fullscreenState: .notInFullscreen,
                isSameWebView: true,
                windowIsVisible: false,
                windowIsOnActiveSpace: true,
                windowScreenFrame: screenA,
                targetScreenFrame: screenA
            ),
            "Same-display re-entry must not disturb WebKit's reusable fullscreen window"
        )

        XCTAssertFalse(
            FloatingPanel.shouldRearmReusableFullscreenWindow(
                fullscreenState: .notInFullscreen,
                isSameWebView: true,
                windowIsVisible: true,
                windowIsOnActiveSpace: true,
                windowScreenFrame: screenB,
                targetScreenFrame: screenA
            )
        )

        XCTAssertFalse(
            FloatingPanel.shouldRearmReusableFullscreenWindow(
                fullscreenState: .enteringFullscreen,
                isSameWebView: true,
                windowIsVisible: false,
                windowIsOnActiveSpace: true,
                windowScreenFrame: screenB,
                targetScreenFrame: screenA
            )
        )

        XCTAssertFalse(
            FloatingPanel.shouldRearmReusableFullscreenWindow(
                fullscreenState: .notInFullscreen,
                isSameWebView: false,
                windowIsVisible: false,
                windowIsOnActiveSpace: true,
                windowScreenFrame: screenB,
                targetScreenFrame: screenA
            )
        )
    }
}

@MainActor
final class PanelRootViewLayoutTests: XCTestCase {
    func testDefaultPanelKeepsRequestedViewportInsideThinExternalFrame() {
        let webView = WKWebView(frame: .zero)
        let root = PanelRootView(webView: webView)
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            root.externalControlZoneView.frame.size,
            NSSize(
                width: PanelMetrics.externalControlZoneWidth,
                height: PanelMetrics.defaultViewportSize.height
            )
        )
        XCTAssertEqual(
            root.externalControlZoneView.frame.minY,
            PanelMetrics.outerInteractionGutter,
            accuracy: 0.001
        )
        XCTAssertEqual(root.webPanelContainerView.frame.size, PanelMetrics.defaultViewportSize)
        XCTAssertEqual(
            root.webPanelContainerView.frame.minY,
            PanelMetrics.outerInteractionGutter,
            accuracy: 0.001
        )
        XCTAssertEqual(
            root.webPanelContainerView.frame.maxX,
            root.bounds.maxX - PanelMetrics.outerInteractionGutter,
            accuracy: 0.001
        )
        XCTAssertEqual(root.perimeterDragView.frame, root.bounds)
        XCTAssertEqual(root.interactionBorderView.frame, root.bounds)
        XCTAssertEqual(root.resizeHandleView.frame.width, PanelMetrics.resizeHandleSize, accuracy: 0.001)
        XCTAssertEqual(root.resizeHandleView.frame.height, PanelMetrics.resizeHandleSize, accuracy: 0.001)
        XCTAssertEqual(
            root.resizeHandleView.frame.maxX,
            root.webPanelContainerView.frame.maxX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            root.resizeHandleView.frame.minY,
            root.webPanelContainerView.frame.minY,
            accuracy: 0.001
        )
    }

    func testAnimatedBorderNeverConsumesMouseInput() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        XCTAssertNil(root.interactionBorderView.hitTest(root.interactionBorderView.bounds.center))
    }
}

@MainActor
final class PanelPerimeterDragHitTestingTests: XCTestCase {
    func testTopBottomAndBlankExternalZoneMoveWindow() {
        let webView = WKWebView(frame: .zero)
        let root = PanelRootView(webView: webView)
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let halfGutter = PanelMetrics.outerInteractionGutter / 2
        let points = [
            NSPoint(x: PanelMetrics.externalControlZoneWidth / 2, y: root.bounds.midY),
            NSPoint(x: root.webPanelContainerView.frame.midX, y: root.bounds.maxY - halfGutter),
            NSPoint(x: root.webPanelContainerView.frame.midX, y: root.bounds.minY + halfGutter),
        ]

        for point in points {
            XCTAssertTrue(
                root.hitTest(point) is PanelPerimeterDragView,
                "Expected external movement target at \(point)"
            )
        }
    }

    func testConfiguredTopBottomInnerOverlapAlsoMovesWindow() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let halfOverlap = PanelMetrics.innerMovementOverlap / 2
        let x = root.webPanelContainerView.frame.midX
        let points = [
            NSPoint(x: x, y: root.webPanelContainerView.frame.maxY - halfOverlap),
            NSPoint(x: x, y: root.webPanelContainerView.frame.minY + halfOverlap),
        ]

        for point in points {
            XCTAssertTrue(root.hitTest(point) is PanelPerimeterDragView)
        }
    }

    func testMovementDoesNotExtendDeeperThanConfiguredOverlap() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let x = root.webPanelContainerView.frame.midX
        let inset = PanelMetrics.innerMovementOverlap + 2
        let points = [
            NSPoint(x: x, y: root.webPanelContainerView.frame.maxY - inset),
            NSPoint(x: x, y: root.webPanelContainerView.frame.minY + inset),
        ]

        for point in points {
            XCTAssertFalse(root.hitTest(point) is PanelPerimeterDragView)
        }
    }

    func testRightWebEdgeIsNeverConsumedByMovementLayer() {
        let webView = WKWebView(frame: .zero)
        let root = PanelRootView(webView: webView)
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let rightWebEdge = NSPoint(
            x: root.webPanelContainerView.frame.maxX - 1,
            y: root.webPanelContainerView.frame.midY
        )

        XCTAssertFalse(root.hitTest(rightWebEdge) is PanelPerimeterDragView)
        XCTAssertFalse(root.hitTest(rightWebEdge) is PanelResizeHandleView)
    }

    func testRightOuterGutterIsSafeShellButNotMovementTarget() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let rightGutterPoint = NSPoint(
            x: root.bounds.maxX - PanelMetrics.outerInteractionGutter / 2,
            y: root.bounds.midY
        )

        let hit = root.hitTest(rightGutterPoint)
        XCTAssertFalse(hit is PanelPerimeterDragView)
        XCTAssertTrue(hit === root)
    }

    func testMovementOverlapWithWebIsLimitedToConfiguredTopBottomDepth() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        var overlappingRectCount = 0
        for rect in PanelPerimeterDragView.dragRects(in: root.bounds) {
            let overlap = rect.intersection(root.webPanelContainerView.frame)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            overlappingRectCount += 1
            XCTAssertLessThanOrEqual(
                overlap.height,
                PanelMetrics.innerMovementOverlap + 0.001
            )
        }
        XCTAssertEqual(overlappingRectCount, 2)
    }

    func testDirectWindowDragOriginUsesGlobalPointerDelta() {
        let origin = PanelPerimeterDragView.destinationOrigin(
            startingWindowOrigin: NSPoint(x: 100, y: 200),
            startingMouseLocation: NSPoint(x: 400, y: 500),
            currentMouseLocation: NSPoint(x: 455, y: 470)
        )

        XCTAssertEqual(origin.x, 155, accuracy: 0.001)
        XCTAssertEqual(origin.y, 170, accuracy: 0.001)
    }

    func testBottomRightCornerIsDedicatedResizeHandle() {
        let webView = WKWebView(frame: .zero)
        let root = PanelRootView(webView: webView)
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let point = NSPoint(
            x: root.resizeHandleView.frame.midX,
            y: root.resizeHandleView.frame.midY
        )
        XCTAssertTrue(root.hitTest(point) is PanelResizeHandleView)
    }

    func testResizeHandleWinsOverBottomMovementBand() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let point = NSPoint(
            x: root.resizeHandleView.frame.midX,
            y: root.resizeHandleView.frame.midY
        )
        XCTAssertTrue(root.webPanelContainerView.frame.contains(point))
        XCTAssertTrue(root.hitTest(point) is PanelResizeHandleView)
    }

    func testWebsiteCenterIsNotConsumedByDragOrResizeOverlay() {
        let webView = WKWebView(frame: .zero)
        let root = PanelRootView(webView: webView)
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let websitePoint = NSPoint(
            x: root.webPanelContainerView.frame.midX,
            y: root.webPanelContainerView.frame.midY
        )

        XCTAssertFalse(root.hitTest(websitePoint) is PanelPerimeterDragView)
        XCTAssertFalse(root.hitTest(websitePoint) is PanelResizeHandleView)
    }

    func testResizeReadoutUsesViewportPixelsAndOneDecimalRatio() {
        XCTAssertEqual(
            ResizeReadoutView.text(forViewportSize: NSSize(width: 430, height: 820)),
            "430.0 × 820.0 px  ·  W/H 0.5"
        )
    }
}

private extension NSRect {
    var center: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}
