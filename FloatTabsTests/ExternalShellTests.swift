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

    func testExternalMouseAutoHideDoesNotRequireFrontmostApplicationChange() {
        XCTAssertTrue(
            PanelController.shouldAutoHideForExternalMouseDown(
                panelIsVisible: true,
                isPinned: false
            )
        )
        XCTAssertFalse(
            PanelController.shouldAutoHideForExternalMouseDown(
                panelIsVisible: true,
                isPinned: true
            )
        )
        XCTAssertFalse(
            PanelController.shouldAutoHideForExternalMouseDown(
                panelIsVisible: false,
                isPinned: false
            )
        )
    }

    func testPanelAutoHideDecisionRespectsPin() {
        XCTAssertTrue(PanelController.shouldAutoHide(panelIsVisible: true, isPinned: false))
        XCTAssertFalse(PanelController.shouldAutoHide(panelIsVisible: true, isPinned: true))
        XCTAssertFalse(PanelController.shouldAutoHide(panelIsVisible: false, isPinned: false))
    }

    func testGlobalSettingsGearUsesActualVisibleHitAreaWithoutActiveSlot() {
        let (_, zone) = makeZoneHarness()
        zone.apply(profiles: [], activeTabID: nil)
        zone.layoutSubtreeIfNeeded()

        let pointInZone = NSPoint(
            x: zone.settingsControlFrame.midX,
            y: zone.settingsControlFrame.midY
        )
        let pointInSuperview = zone.convert(pointInZone, to: zone.superview)
        XCTAssertTrue(zone.hitTest(pointInSuperview) is GlobalSettingsControl)
    }

    func testTabContextMenuStartsWithReturnToHome() {
        let (_, zone) = makeZoneHarness()
        let active = makeProfile(order: 0, name: "GPT")
        zone.apply(profiles: [active], activeTabID: active.id)
        zone.setResidentSlotIDs([active.id])
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
            ["Return to Home", "Reload", "Website Mode", "Window Size", "Zoom", "Residency", "Background Media", "Edit Web App…", "Remove Web App…"]
        )
        let reload = try! XCTUnwrap(menu.item(withTitle: "Reload"))
        XCTAssertEqual(reload.keyEquivalent, "r")
        XCTAssertEqual(reload.keyEquivalentModifierMask, [.command])
        XCTAssertTrue(reload.isEnabled)

        XCTAssertEqual(menu.item(withTitle: "Website Mode")?.submenu?.items.map(\.title), ["Desktop", "Mobile"])
        XCTAssertEqual(
            menu.item(withTitle: "Window Size")?.submenu?.items.filter { !$0.isSeparatorItem }.map(\.title),
            ["Small  390 × 780", "Medium  430 × 820", "Large  600 × 800", "Wide  900 × 850"]
        )
        let zoomItems = try! XCTUnwrap(menu.item(withTitle: "Zoom")?.submenu?.items)
        XCTAssertEqual(zoomItems[0].title, "Zoom In")
        XCTAssertEqual(zoomItems[0].keyEquivalent, "+")
        XCTAssertEqual(zoomItems[0].keyEquivalentModifierMask, [.command])
        XCTAssertEqual(zoomItems[1].title, "Zoom Out")
        XCTAssertEqual(zoomItems[1].keyEquivalent, "-")
        XCTAssertEqual(zoomItems[1].keyEquivalentModifierMask, [.command])
        XCTAssertEqual(zoomItems[2].title, "Reset Zoom")
        XCTAssertEqual(zoomItems[2].keyEquivalent, "0")
        XCTAssertEqual(zoomItems[2].keyEquivalentModifierMask, [.command])
        XCTAssertTrue(zoomItems[3].isSeparatorItem)

        XCTAssertEqual(menu.item(withTitle: "Residency")?.submenu?.items.map(\.title), ["Hot", "Warm", "Cold"])
        XCTAssertEqual(
            menu.item(withTitle: "Background Media")?.submenu?.items.map(\.title),
            ["Pause When Inactive", "Allow Background Audio"]
        )
        XCTAssertFalse(actionTitles.contains("Rename…"))
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
        let (_, zone) = makeZoneHarness()
        let active = makeProfile(order: 0, name: "GPT")
        let inactive = makeProfile(order: 1, name: "X")
        zone.apply(profiles: [active, inactive], activeTabID: active.id)
        zone.layoutSubtreeIfNeeded()

        let activeView = try! XCTUnwrap(zone.tabView(for: active.id))
        let inactiveView = try! XCTUnwrap(zone.tabView(for: inactive.id))

        XCTAssertEqual(activeView.frame.width, ExternalTabMetrics.activeWidth, accuracy: 0.001)
        XCTAssertEqual(inactiveView.frame.width, ExternalTabMetrics.collapsedWidth, accuracy: 0.001)
        XCTAssertFalse(activeView.isShowingLabel)
        XCTAssertFalse(inactiveView.isShowingLabel)
        XCTAssertEqual(activeView.frame.height, ExternalTabMetrics.tabHeight, accuracy: 0.001)
        XCTAssertEqual(zone.addControlFrame.width, ExternalTabMetrics.addNormalWidth, accuracy: 0.001)
        XCTAssertEqual(zone.addControlFrame.height, ExternalTabMetrics.addHeight, accuracy: 0.001)
        XCTAssertEqual(zone.settingsControlFrame.width, ExternalTabMetrics.systemControlNormalWidth, accuracy: 0.001)
        XCTAssertEqual(zone.pinControlFrame.width, ExternalTabMetrics.systemControlNormalWidth, accuracy: 0.001)
        XCTAssertEqual(activeView.frame.maxX, zone.bounds.maxX, accuracy: 0.001)
        XCTAssertEqual(
            inactiveView.frame.maxX,
            zone.bounds.maxX - PanelMetrics.interactionBorderOutset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            zone.addControlFrame.maxX,
            zone.bounds.maxX - PanelMetrics.interactionBorderOutset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            zone.settingsControlFrame.maxX,
            zone.bounds.maxX - PanelMetrics.interactionBorderOutset,
            accuracy: 0.001
        )
        XCTAssertEqual(
            zone.pinControlFrame.maxX,
            zone.bounds.maxX - PanelMetrics.interactionBorderOutset,
            accuracy: 0.001
        )
        XCTAssertLessThan(zone.settingsControlFrame.maxY, zone.pinControlFrame.minY)
    }

    func testInactiveTabHoverCanBeClearedWithoutLeavingExpandedGeometry() {
        let (_, zone) = makeZoneHarness()
        let active = makeProfile(order: 0, name: "GPT")
        let inactive = makeProfile(order: 1, name: "X")
        zone.apply(profiles: [active, inactive], activeTabID: active.id)
        zone.layoutSubtreeIfNeeded()

        let inactiveView = try! XCTUnwrap(zone.tabView(for: inactive.id))
        inactiveView.setHovered(true)
        XCTAssertEqual(inactiveView.preferredWidth, ExternalTabMetrics.hoverWidth, accuracy: 0.001)
        XCTAssertTrue(inactiveView.isShowingLabel)

        inactiveView.setHovered(false)
        XCTAssertEqual(inactiveView.preferredWidth, ExternalTabMetrics.collapsedWidth, accuracy: 0.001)
        XCTAssertFalse(inactiveView.isShowingLabel)
    }

    func testTabControlsWinOverPerimeterDragWhenTheyOverlap() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        let active = makeProfile(order: 0, name: "GPT")
        root.externalControlZoneView.apply(profiles: [active], activeTabID: active.id)
        root.layoutSubtreeIfNeeded()

        let tab = try! XCTUnwrap(root.externalControlZoneView.tabView(for: active.id))
        let localPoint = NSPoint(x: tab.frame.midX, y: tab.frame.midY)
        XCTAssertTrue(tab.frame.contains(localPoint))
        let rootPoint = root.externalControlZoneView.convert(localPoint, to: root)

        XCTAssertTrue(root.hitTest(rootPoint) is ExternalWebAppTabView)
    }

    func testResizeHandleUsesExpandedFirstMouseHitTarget() {
        XCTAssertGreaterThanOrEqual(PanelMetrics.resizeHandleSize, 40)
        let handle = PanelResizeHandleView(frame: NSRect(x: 100, y: 100, width: 40, height: 40))
        XCTAssertTrue(handle.acceptsFirstMouse(for: nil))
        XCTAssertTrue(handle.hitTest(NSPoint(x: 102, y: 102)) === handle)
        XCTAssertNil(handle.hitTest(NSPoint(x: 150, y: 150)))
    }

    func testResizeHandleLivesInsideWebCornerInsteadOfOuterTransparentGutter() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let webFrame = root.webPanelContainerView.frame
        let insideWebCorner = NSPoint(x: webFrame.maxX - 4, y: webFrame.minY + 4)
        XCTAssertTrue(root.hitTest(insideWebCorner) is PanelResizeHandleView)

        let outerTransparentCorner = NSPoint(
            x: root.bounds.maxX - 4,
            y: root.bounds.minY + 4
        )
        XCTAssertFalse(root.hitTest(outerTransparentCorner) is PanelResizeHandleView)
    }

    func testTopAndBottomMoveTargetsIncludeReliableInPageArea() {
        XCTAssertGreaterThanOrEqual(PanelMetrics.innerMovementOverlap, 10)

        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()
        let webFrame = root.webPanelContainerView.frame

        let topInside = NSPoint(x: webFrame.midX, y: webFrame.maxY - 8)
        let bottomInside = NSPoint(x: webFrame.midX, y: webFrame.minY + 8)
        XCTAssertTrue(root.hitTest(topInside) is PanelPerimeterDragView)
        XCTAssertTrue(root.hitTest(bottomInside) is PanelPerimeterDragView)
    }

    func testPanelRootConsumesTransparentInWindowGapsInsteadOfClickingThrough() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let rightGutterPoint = NSPoint(x: root.bounds.maxX - 4, y: root.bounds.midY)
        XCTAssertTrue(root.hitTest(rightGutterPoint) === root)
    }

    func testPerimeterDragHitTestUsesSameLocalGeometryAsMoveCursor() {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 2400, height: 2400))
        let drag = PanelPerimeterDragView(frame: NSRect(
            x: 1000,
            y: 1000,
            width: PanelMetrics.defaultPanelSize.width,
            height: PanelMetrics.defaultPanelSize.height
        ))
        host.addSubview(drag)

        let localTop = NSPoint(
            x: drag.bounds.midX,
            y: drag.bounds.maxY - PanelMetrics.outerInteractionGutter / 2
        )
        XCTAssertTrue(PanelMoveHoverController.isDraggable(point: localTop, in: drag.bounds))
        let topInHost = drag.convert(localTop, to: host)
        XCTAssertTrue(drag.hitTest(topInHost) === drag)

        let localWebCenter = NSPoint(
            x: PanelMetrics.externalControlZoneWidth + PanelMetrics.defaultViewportSize.width / 2,
            y: drag.bounds.midY
        )
        let webCenterInHost = drag.convert(localWebCenter, to: host)
        XCTAssertNil(drag.hitTest(webCenterInHost))
    }

    func testActiveTabExpandsAnimatedPanelOutlineIntoRail() {
        let web = NSRect(x: 76, y: 12, width: 430, height: 820)
        let activeTab = NSRect(x: 36, y: 720, width: 40, height: 32)
        let path = PanelInteractionBorderView.outlinePath(
            webFrame: web,
            activeTabFrame: activeTab,
            clippingBounds: NSRect(x: 0, y: 0, width: 518, height: 844)
        )
        XCTAssertLessThan(path.boundingBox.minX, web.minX - 10)
        XCTAssertGreaterThanOrEqual(path.boundingBox.maxX, web.maxX)
    }

    func testFaviconColorStateTracksResidentRuntimeInsteadOfActiveSelection() {
        let (_, zone) = makeZoneHarness()
        let activeButReleased = makeProfile(order: 0, name: "Active")
        let inactiveButResident = makeProfile(order: 1, name: "Warm")
        zone.apply(
            profiles: [activeButReleased, inactiveButResident],
            activeTabID: activeButReleased.id
        )
        zone.setResidentSlotIDs([inactiveButResident.id])
        zone.layoutSubtreeIfNeeded()

        XCTAssertFalse(try! XCTUnwrap(zone.tabView(for: activeButReleased.id)).isResidentRuntime)
        XCTAssertTrue(try! XCTUnwrap(zone.tabView(for: inactiveButResident.id)).isResidentRuntime)
    }

    func testStatusItemTitleUsesSelectedWebAppName() {
        XCTAssertEqual(StatusItemController.displayTitle(for: "ChatGPT"), "ChatGPT")
        XCTAssertEqual(StatusItemController.displayTitle(for: "  X  "), "X")
        XCTAssertEqual(StatusItemController.displayTitle(for: nil), "FloatTabs")
    }

    func testStatusItemFaviconIdentityUsesSelectedWebsiteOrigin() {
        XCTAssertEqual(
            StatusItemController.faviconOriginKey(for: URL(string: "https://x.com/home")),
            "https://x.com"
        )
        XCTAssertEqual(
            StatusItemController.faviconOriginKey(for: URL(string: "https://chatgpt.com/c/123")),
            "https://chatgpt.com"
        )
        XCTAssertNil(StatusItemController.faviconOriginKey(for: nil))
    }

    func testFaviconURLUsesWebsiteOriginWithoutThirdPartyService() {
        let input = URL(string: "https://example.com/a/b?q=1")!
        XCTAssertEqual(
            WebsiteFaviconProvider.faviconURL(for: input)?.absoluteString,
            "https://example.com/favicon.ico"
        )
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
