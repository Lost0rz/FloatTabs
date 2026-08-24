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
        XCTAssertEqual(PanelMetrics.innerMovementOverlap, 12)
        XCTAssertEqual(
            PanelMetrics.outerInteractionGutter + PanelMetrics.innerMovementOverlap,
            24
        )
        XCTAssertEqual(
            PanelMetrics.outerInteractionGutter,
            PanelMetrics.innerMovementOverlap
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

    func testClampingToPreferredDisplayMovesFrameOffThePreviousDisplay() {
        let displayA = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let displayB = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        let frameOnB = NSRect(x: 1700, y: 100, width: 688, height: 844)

        let moved = ScreenPositioning.clampedFrame(frameOnB, to: displayA)

        XCTAssertGreaterThanOrEqual(moved.minX, displayA.minX)
        XCTAssertLessThanOrEqual(moved.maxX, displayA.maxX)
        XCTAssertFalse(moved.intersects(displayB))
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
        let store = PanelFrameStore(defaults: defaults, key: "frame")
        XCTAssertNil(store.loadFrame())
    }
}

@MainActor
final class FloatingPanelResizePolicyTests: XCTestCase {
    func testNativeResizeStyleIsDisabled() {
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize))
        XCTAssertFalse(panel.styleMask.contains(.resizable))
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
        XCTAssertEqual(root.webViewportLayoutView.frame.size, PanelMetrics.defaultViewportSize)
        XCTAssertEqual(
            root.webViewportLayoutView.frame.minY,
            PanelMetrics.outerInteractionGutter,
            accuracy: 0.001
        )
        XCTAssertEqual(
            root.webViewportLayoutView.frame.maxX,
            root.bounds.maxX - PanelMetrics.outerInteractionGutter,
            accuracy: 0.001
        )
        XCTAssertEqual(root.perimeterDragView.frame, root.bounds)
        XCTAssertEqual(root.interactionBorderView.frame, root.bounds)
        XCTAssertEqual(root.resizeHandleView.frame.width, PanelMetrics.resizeHandleSize, accuracy: 0.001)
        XCTAssertEqual(root.resizeHandleView.frame.height, PanelMetrics.resizeHandleSize, accuracy: 0.001)
        XCTAssertEqual(
            root.resizeHandleView.frame.maxX,
            root.webViewportLayoutView.frame.maxX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            root.resizeHandleView.frame.minY,
            root.webViewportLayoutView.frame.minY,
            accuracy: 0.001
        )
    }

    func testAnimatedBorderNeverConsumesMouseInput() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        XCTAssertNil(root.interactionBorderView.hitTest(root.interactionBorderView.bounds.center))
    }

    func testCollapsedPanelKeepsViewportFlushAgainstTwelvePointLeadingGutter() {
        let webView = WKWebView(frame: .zero)
        let root = PanelRootView(webView: webView)
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        root.setTabRailCollapsed(true, animated: false)
        root.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            root.externalControlZoneView.frame.width,
            PanelMetrics.collapsedRailLeadingInset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            root.webViewportLayoutView.frame.minX,
            PanelMetrics.collapsedRailLeadingInset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            root.webViewportLayoutView.frame.width,
            PanelMetrics.defaultViewportSize.width + PanelMetrics.externalControlZoneWidth
                - PanelMetrics.collapsedRailLeadingInset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            root.resizeHandleView.frame.maxX,
            root.webViewportLayoutView.frame.maxX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            root.companionRailFoldControlView.frame.minX,
            PanelMetrics.collapsedRailLeadingInset,
            accuracy: 0.001
        )
    }

    func testRailCollapseRoundTripRestoresExactNominalViewport() {
        let webView = WKWebView(frame: .zero)
        let root = PanelRootView(webView: webView)
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()
        let expandedFrame = root.webViewportLayoutView.frame

        root.setTabRailCollapsed(true, animated: false)
        root.layoutSubtreeIfNeeded()
        root.setTabRailCollapsed(false, animated: false)
        root.layoutSubtreeIfNeeded()

        XCTAssertEqual(root.webViewportLayoutView.frame, expandedFrame)
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
            NSPoint(x: root.webViewportLayoutView.frame.midX, y: root.bounds.maxY - halfGutter),
            NSPoint(x: root.webViewportLayoutView.frame.midX, y: root.bounds.minY + halfGutter),
        ]

        for point in points {
            XCTAssertTrue(
                root.hitTest(point) is PanelPerimeterDragView,
                "Expected external movement target at \(point)"
            )
        }
    }

    func testCollapsedLeftGutterRemainsMovementTarget() {
        let webView = WKWebView(frame: .zero)
        let root = PanelRootView(webView: webView)
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        root.setTabRailCollapsed(true, animated: false)
        root.layoutSubtreeIfNeeded()

        let gutterPoint = NSPoint(
            x: PanelMetrics.collapsedRailLeadingInset / 2,
            y: root.bounds.midY
        )
        XCTAssertTrue(root.hitTest(gutterPoint) is PanelPerimeterDragView)
    }

    func testCollapsedDragBandsAvoidReclaimedContentArea() {
        let webView = WKWebView(frame: .zero)
        let root = PanelRootView(webView: webView)
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        root.setTabRailCollapsed(true, animated: false)
        root.layoutSubtreeIfNeeded()

        let reclaimedColumn = NSRect(
            x: PanelMetrics.collapsedRailLeadingInset,
            y: 2 * PanelMetrics.outerInteractionGutter,
            width: PanelMetrics.externalControlZoneWidth - PanelMetrics.collapsedRailLeadingInset,
            height: root.bounds.height - 4 * PanelMetrics.outerInteractionGutter
        )
        for rect in PanelPerimeterDragView.dragRects(
            in: root.bounds,
            leadingInset: PanelMetrics.collapsedRailLeadingInset
        ) {
            let overlap = rect.intersection(reclaimedColumn)
            XCTAssertTrue(overlap.isNull || overlap.isEmpty)
        }

        let reclaimedPoint = NSPoint(
            x: PanelMetrics.collapsedRailLeadingInset + reclaimedColumn.width / 2,
            y: root.bounds.midY
        )
        XCTAssertFalse(root.hitTest(reclaimedPoint) is PanelPerimeterDragView)
    }

    func testCollapsedShellMovementBandsStayOutsideReclaimedWebFrame() {
        let webView = WKWebView(frame: .zero)
        let root = PanelRootView(webView: webView)
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        root.setTabRailCollapsed(true, animated: false)
        root.layoutSubtreeIfNeeded()

        for rect in PanelPerimeterDragView.dragRects(
            in: root.bounds,
            leadingInset: PanelMetrics.collapsedRailLeadingInset
        ) {
            let overlap = rect.intersection(root.webViewportLayoutView.frame)
            XCTAssertTrue(overlap.isNull || overlap.isEmpty)
        }
    }

    func testConfiguredInnerOverlapMovesSourceFromEveryEdge() {
        let bounds = NSRect(origin: .zero, size: PanelMetrics.defaultViewportSize)
        let halfOverlap = PanelMetrics.innerMovementOverlap / 2
        let points = [
            NSPoint(x: bounds.midX, y: bounds.maxY - halfOverlap),
            NSPoint(x: bounds.midX, y: bounds.minY + halfOverlap),
            NSPoint(x: bounds.minX + halfOverlap, y: bounds.midY),
            NSPoint(x: bounds.maxX - halfOverlap, y: bounds.midY),
        ]
        let dragRects = WebSourceEdgeDragView.dragRects(in: bounds)

        for point in points {
            XCTAssertTrue(dragRects.contains(where: { $0.contains(point) }))
        }
    }

    func testMovementDoesNotExtendDeeperThanConfiguredOverlap() {
        let bounds = NSRect(origin: .zero, size: PanelMetrics.defaultViewportSize)
        let inset = PanelMetrics.innerMovementOverlap + 2
        let points = [
            NSPoint(x: bounds.midX, y: bounds.maxY - inset),
            NSPoint(x: bounds.midX, y: bounds.minY + inset),
            NSPoint(x: bounds.minX + inset, y: bounds.midY),
            NSPoint(x: bounds.maxX - inset, y: bounds.midY),
        ]
        let dragRects = WebSourceEdgeDragView.dragRects(in: bounds)

        for point in points {
            XCTAssertFalse(dragRects.contains(where: { $0.contains(point) }))
        }
    }

    func testRightWebEdgeIsOwnedBySourceMovementLayer() {
        let bounds = NSRect(origin: .zero, size: PanelMetrics.defaultViewportSize)
        let rightWebEdge = NSPoint(
            x: bounds.maxX - 1,
            y: bounds.midY
        )

        XCTAssertTrue(
            WebSourceEdgeDragView.dragRects(in: bounds)
                .contains(where: { $0.contains(rightWebEdge) })
        )
    }

    func testRightOuterGutterIsMovementTarget() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let rightGutterPoint = NSPoint(
            x: root.bounds.maxX - PanelMetrics.outerInteractionGutter / 2,
            y: root.bounds.midY
        )

        let hit = root.hitTest(rightGutterPoint)
        XCTAssertTrue(hit is PanelPerimeterDragView)
    }

    func testShellMovementBandsStayOutsideWebBecauseSourceOwnsInnerDepth() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        for rect in PanelPerimeterDragView.dragRects(in: root.bounds) {
            let overlap = rect.intersection(root.webViewportLayoutView.frame)
            XCTAssertTrue(overlap.isNull || overlap.isEmpty)
        }
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
        XCTAssertTrue(root.webViewportLayoutView.frame.contains(point))
        XCTAssertTrue(root.hitTest(point) is PanelResizeHandleView)
    }

    func testWebsiteCenterIsNotConsumedByDragOrResizeOverlay() {
        let webView = WKWebView(frame: .zero)
        let root = PanelRootView(webView: webView)
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let websitePoint = NSPoint(
            x: root.webViewportLayoutView.frame.midX,
            y: root.webViewportLayoutView.frame.midY
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
