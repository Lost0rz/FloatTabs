import AppKit
import XCTest
@testable import FloatTabs

@MainActor
final class ExternalShellTests: XCTestCase {
    func testActualTabHitAreaReturnsVisibleTabView() {
        let (_, zone) = makeZoneHarness()
        let active = makeProfile(order: 0, name: "GPT")
        zone.apply(profiles: [active], activeTabID: active.id)
        zone.layoutSubtreeIfNeeded()

        let tab = try! XCTUnwrap(zone.tabView(for: active.id))
        let pointInZone = NSPoint(x: tab.frame.midX, y: tab.frame.midY)
        let pointInSuperview = zone.convert(pointInZone, to: zone.superview)

        XCTAssertTrue(zone.hitTest(pointInSuperview) === tab)
    }

    func testBlankZoneDoesNotBecomeFullWidthInvisibleControl() {
        let (_, zone) = makeZoneHarness()
        let active = makeProfile(order: 0, name: "GPT")
        zone.apply(profiles: [active], activeTabID: active.id)
        zone.layoutSubtreeIfNeeded()

        let blankPointInZone = NSPoint(x: 2, y: zone.bounds.midY)
        let blankPointInSuperview = zone.convert(blankPointInZone, to: zone.superview)
        XCTAssertNil(zone.hitTest(blankPointInSuperview))
    }

    func testAddControlUsesActualVisibleHitArea() {
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [], activeTabID: nil)
        zone.layoutSubtreeIfNeeded()

        let pointInZone = NSPoint(x: zone.addControlFrame.midX, y: zone.addControlFrame.midY)
        let pointInSuperview = zone.convert(pointInZone, to: zone.superview)
        XCTAssertTrue(zone.hitTest(pointInSuperview) is AddWebAppControl)
    }

    func testPinControlUsesActualVisibleHitAreaAndReflectsPinnedState() {
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [], activeTabID: nil)
        zone.setPinned(true)
        zone.layoutSubtreeIfNeeded()

        let pointInZone = NSPoint(x: zone.pinControlFrame.midX, y: zone.pinControlFrame.midY)
        let pointInSuperview = zone.convert(pointInZone, to: zone.superview)
        let pin = zone.hitTest(pointInSuperview) as? PinPanelControl

        XCTAssertNotNil(pin)
        XCTAssertTrue(pin?.isPinned == true)
        XCTAssertEqual(zone.pinControlFrame.width, ExternalTabMetrics.systemControlNormalWidth, accuracy: 0.001)
    }

    func testWorkspaceAutoHideRequiresAnotherFrontmostApplication() {
        XCTAssertTrue(
            PanelController.shouldAutoHideForActivatedApplication(
                panelIsVisible: true,
                isPinned: false,
                activatedProcessIdentifier: 200,
                ownProcessIdentifier: 100
            )
        )
        XCTAssertFalse(
            PanelController.shouldAutoHideForActivatedApplication(
                panelIsVisible: true,
                isPinned: true,
                activatedProcessIdentifier: 200,
                ownProcessIdentifier: 100
            )
        )
        XCTAssertFalse(
            PanelController.shouldAutoHideForActivatedApplication(
                panelIsVisible: true,
                isPinned: false,
                activatedProcessIdentifier: 100,
                ownProcessIdentifier: 100
            )
        )
    }

    func testPanelAutoHideDecisionRespectsPin() {
        XCTAssertTrue(PanelController.shouldAutoHide(panelIsVisible: true, isPinned: false))
        XCTAssertFalse(PanelController.shouldAutoHide(panelIsVisible: true, isPinned: true))
        XCTAssertFalse(PanelController.shouldAutoHide(panelIsVisible: false, isPinned: false))
    }

    func testCurrentWebAppGearUsesActualVisibleHitAreaWhenSlotIsActive() {
        let (_, zone) = makeZoneHarness()
        let active = makeProfile(order: 0, name: "GPT")
        zone.apply(profiles: [active], activeTabID: active.id)
        zone.layoutSubtreeIfNeeded()

        let pointInZone = NSPoint(
            x: zone.currentControlsFrame.midX,
            y: zone.currentControlsFrame.midY
        )
        let pointInSuperview = zone.convert(pointInZone, to: zone.superview)
        XCTAssertTrue(zone.hitTest(pointInSuperview) is CurrentWebAppControl)
    }

    func testTabContextMenuStartsWithReturnToHome() {
        let (_, zone) = makeZoneHarness()
        let active = makeProfile(order: 0, name: "GPT")
        zone.apply(profiles: [active], activeTabID: active.id)
        zone.layoutSubtreeIfNeeded()

        let tab = try! XCTUnwrap(zone.tabView(for: active.id))
        let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: tab.frame.midX, y: tab.frame.midY),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        )!
        let menu = try! XCTUnwrap(tab.menu(for: event))
        let first = try! XCTUnwrap(menu.items.first)

        XCTAssertEqual(first.title, "Return to Home")
        XCTAssertEqual(first.keyEquivalent, "h")
        XCTAssertEqual(first.keyEquivalentModifierMask, [.command, .shift])

        let actionTitles = menu.items
            .filter { !$0.isSeparatorItem }
            .map(\.title)
        XCTAssertEqual(
            actionTitles,
            ["Return to Home", "Residency", "Background Media", "Edit Web App…", "Remove Web App…"]
        )
        XCTAssertEqual(menu.item(withTitle: "Residency")?.submenu?.items.map(\.title), ["Hot", "Warm", "Cold"])
        XCTAssertEqual(
            menu.item(withTitle: "Background Media")?.submenu?.items.map(\.title),
            ["Pause When Inactive", "Allow Background Audio"]
        )
        XCTAssertFalse(actionTitles.contains("Rename…"))
    }

    func testActiveInactiveAndAddGeometryMatchDesignTokens() {
        let (_, zone) = makeZoneHarness()
        let active = makeProfile(order: 0, name: "GPT")
        let inactive = makeProfile(order: 1, name: "X")
        zone.apply(profiles: [active, inactive], activeTabID: active.id)
        zone.layoutSubtreeIfNeeded()

        let activeView = try! XCTUnwrap(zone.tabView(for: active.id))
        let inactiveView = try! XCTUnwrap(zone.tabView(for: inactive.id))

        XCTAssertEqual(activeView.frame.width, ExternalTabMetrics.activeWidth, accuracy: 0.001)
        XCTAssertEqual(inactiveView.frame.width, ExternalTabMetrics.inactiveWidth, accuracy: 0.001)
        XCTAssertEqual(activeView.frame.height, ExternalTabMetrics.tabHeight, accuracy: 0.001)
        XCTAssertEqual(zone.addControlFrame.width, ExternalTabMetrics.addNormalWidth, accuracy: 0.001)
        XCTAssertEqual(zone.addControlFrame.height, ExternalTabMetrics.addHeight, accuracy: 0.001)
        XCTAssertEqual(zone.currentControlsFrame.width, ExternalTabMetrics.systemControlNormalWidth, accuracy: 0.001)
        XCTAssertEqual(zone.pinControlFrame.width, ExternalTabMetrics.systemControlNormalWidth, accuracy: 0.001)
        XCTAssertLessThan(zone.currentControlsFrame.maxY, zone.pinControlFrame.minY)
    }

    func testTabControlsWinOverPerimeterDragWhenTheyOverlap() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        let active = makeProfile(order: 0, name: "GPT")
        root.externalControlZoneView.apply(profiles: [active], activeTabID: active.id)
        root.layoutSubtreeIfNeeded()

        let tab = try! XCTUnwrap(root.externalControlZoneView.tabView(for: active.id))
        let localPoint = NSPoint(x: 10, y: 40)
        XCTAssertTrue(tab.frame.contains(localPoint))
        let rootPoint = root.externalControlZoneView.convert(localPoint, to: root)

        XCTAssertTrue(root.hitTest(rootPoint) is ExternalWebAppTabView)
    }

    func testMoveHoverTrackingRemainsActiveWhenAppIsInactive() {
        XCTAssertTrue(PanelMoveHoverController.trackingOptions.contains(.activeAlways))
        XCTAssertTrue(PanelMoveHoverController.trackingOptions.contains(.mouseMoved))
        XCTAssertTrue(PanelMoveHoverController.trackingOptions.contains(.mouseEnteredAndExited))
    }

    func testMoveHoverUsesSameHitGeometryAsWindowDrag() {
        let bounds = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        let topPoint = NSPoint(
            x: bounds.midX,
            y: bounds.maxY - PanelMetrics.outerInteractionGutter / 2
        )
        let websiteCenter = NSPoint(
            x: PanelMetrics.externalControlZoneWidth + PanelMetrics.defaultViewportSize.width / 2,
            y: bounds.midY
        )

        XCTAssertTrue(PanelMoveHoverController.isDraggable(point: topPoint, in: bounds))
        XCTAssertFalse(PanelMoveHoverController.isDraggable(point: websiteCenter, in: bounds))
    }

    private func makeZoneHarness() -> (host: NSView, zone: ExternalControlZoneView) {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 76, height: 820))
        let zone = ExternalControlZoneView(frame: host.bounds)
        host.addSubview(zone)
        zone.layoutSubtreeIfNeeded()
        return (host, zone)
    }

    private func makeProfile(order: Int, name: String) -> WebAppProfile {
        WebAppProfile(
            order: order,
            name: name,
            homeURL: URL(string: "https://example.com/\(name)")!,
            createdAt: Date(timeIntervalSince1970: TimeInterval(order)),
            lastUsedAt: Date(timeIntervalSince1970: TimeInterval(order))
        )
    }
}
