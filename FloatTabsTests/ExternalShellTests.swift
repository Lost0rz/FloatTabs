import AppKit
import KeyboardShortcuts
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class ExternalShellTests: XCTestCase {
    func testFullscreenRestoreWatchdogUsesStablePublicHierarchyBeforeUnlocking() {
        XCTAssertEqual(
            FullscreenRestoreWatchdog.decision(
                elapsed: 0.1,
                isBackInSourceHierarchy: true,
                stableChecks: 0
            ),
            .poll(stableChecks: 1, delay: 0.05)
        )
        XCTAssertEqual(
            FullscreenRestoreWatchdog.decision(
                elapsed: 0.2,
                isBackInSourceHierarchy: true,
                stableChecks: 2
            ),
            .restored
        )
    }

    func testFullscreenRestoreWatchdogBoundsMissingHierarchyRecovery() {
        XCTAssertEqual(
            FullscreenRestoreWatchdog.decision(
                elapsed: 9.9,
                isBackInSourceHierarchy: false,
                stableChecks: 2
            ),
            .poll(stableChecks: 0, delay: 0.05)
        )
        XCTAssertEqual(
            FullscreenRestoreWatchdog.decision(
                elapsed: 10,
                isBackInSourceHierarchy: false,
                stableChecks: 0
            ),
            .rebuildSource
        )
    }

    func testFullscreenVisibilityRestoresPresentationThatWasVisibleBeforeEntry() {
        var intent = FullscreenVisibilityIntent()

        intent.begin(wasVisible: true)

        XCTAssertTrue(intent.consumeRestore(currentVisibility: false))
        XCTAssertFalse(intent.shouldRestoreNormalPresentation)
    }

    func testExplicitFullscreenDismissalCancelsNormalPresentationRestore() {
        var intent = FullscreenVisibilityIntent()

        intent.begin(wasVisible: true)
        intent.dismissPresentation()

        XCTAssertFalse(intent.consumeRestore(currentVisibility: false))
    }

    func testExplicitFullscreenShowKeepsNormalPresentationAfterRestore() {
        var intent = FullscreenVisibilityIntent()

        intent.begin(wasVisible: false)
        intent.requestPresentation()

        XCTAssertTrue(intent.consumeRestore(currentVisibility: true))
    }

    func testFullscreenSourceSlotCannotBeRemovedWhileWebKitOwnsIt() {
        let sourceID = UUID()

        XCTAssertFalse(
            PanelController.canRemoveSlotDuringFullscreen(
                slotID: sourceID,
                fullscreenSourceSlotID: sourceID,
                sessionIsLocked: true
            )
        )
        XCTAssertTrue(
            PanelController.canRemoveSlotDuringFullscreen(
                slotID: UUID(),
                fullscreenSourceSlotID: sourceID,
                sessionIsLocked: true
            )
        )
        XCTAssertTrue(
            PanelController.canRemoveSlotDuringFullscreen(
                slotID: sourceID,
                fullscreenSourceSlotID: sourceID,
                sessionIsLocked: false
            )
        )
    }

    func testAppLocalCommandsFollowFloatTabsPresentationInsteadOfAccessoryActivationFlag() {
        XCTAssertTrue(
            PanelController.acceptsAppCommands(
                requestedVisibility: true,
                sourceSessionLocked: false
            )
        )
        XCTAssertTrue(
            PanelController.acceptsAppCommands(
                requestedVisibility: false,
                sourceSessionLocked: true
            )
        )
        XCTAssertFalse(
            PanelController.acceptsAppCommands(
                requestedVisibility: false,
                sourceSessionLocked: false
            )
        )
    }

    func testFullscreenSourceHostFollowsShellIntoHostApplicationFullscreenSpaces() {
        let behavior = FullscreenSourceHostController.sourceWindowCollectionBehavior

        XCTAssertTrue(behavior.contains(.managed))
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(behavior.contains(.canJoinAllApplications))
        XCTAssertFalse(behavior.contains(.fullScreenNone))
        XCTAssertFalse(behavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(behavior.contains(.fullScreenPrimary))

        let webKitFullscreenBehavior =
            FullscreenSourceHostController.webKitFullscreenSourceWindowCollectionBehavior
        XCTAssertTrue(webKitFullscreenBehavior.contains(.managed))
        XCTAssertTrue(webKitFullscreenBehavior.contains(.fullScreenNone))
        XCTAssertFalse(webKitFullscreenBehavior.contains(.canJoinAllApplications))
    }

    func testFloatingPanelUsesActivatingShellSemantics() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 20, y: 20, width: 688, height: 844)
        )

        XCTAssertFalse(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(panel.canBecomeKey)
    }

    func testFullscreenCompanionMovesWithTheActiveFullscreenSpace() {
        let panel = FloatingPanel(
            contentRect: NSRect(x: 20, y: 20, width: 688, height: 844)
        )

        panel.setFullscreenCompanionPresentation(true)

        XCTAssertTrue(panel.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(panel.collectionBehavior.contains(.canJoinAllSpaces))
    }

    func testToggleUsesPhysicalShellVisibilityDuringTransitions() {
        XCTAssertTrue(PanelController.shouldPresentAfterToggle(shellIsVisible: false))
        XCTAssertFalse(PanelController.shouldPresentAfterToggle(shellIsVisible: true))
    }

    func testFullscreenSourceIsGroupedWithShellOutsideFullscreen() {
        let shell = FloatingPanel(contentRect: NSRect(x: 20, y: 20, width: 688, height: 844))
        let host = FullscreenSourceHostController(
            container: WebPanelContainerView(),
            resizeHandle: PanelResizeHandleView(),
            resizeReadout: ResizeReadoutView(),
            shellWindow: shell
        )

        XCTAssertTrue(host.window.parent === shell)
        XCTAssertTrue(shell.childWindows?.contains(where: { $0 === host.window }) == true)

        host.window.parent?.removeChildWindow(host.window)
        XCTAssertNil(host.window.parent)
    }

    func testWebFocusPreservesWebKitsExistingInternalResponder() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        let webView = WKWebView(frame: root.bounds)
        let internalEditor = FocusableTestView(frame: NSRect(x: 10, y: 10, width: 50, height: 30))
        window.contentView = root
        root.addSubview(webView)
        webView.addSubview(internalEditor)

        XCTAssertTrue(window.makeFirstResponder(internalEditor))
        XCTAssertTrue(WebViewFocus.focus(webView, in: window))
        XCTAssertTrue(window.firstResponder === internalEditor)
    }

    func testWebFocusRejectsResponderOutsideCurrentWebHierarchy() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
        let unrelatedEditor = FocusableTestView(
            frame: NSRect(x: 320, y: 10, width: 50, height: 30)
        )
        window.contentView = root
        root.addSubview(webView)
        root.addSubview(unrelatedEditor)

        XCTAssertTrue(window.makeFirstResponder(unrelatedEditor))
        XCTAssertFalse(
            WebViewFocus.responderBelongsToWebView(
                window.firstResponder,
                webView: webView,
                window: window
            )
        )
    }

    func testSourceTransientUIContainerCanPlaceChromeAboveWebContent() {
        let shell = FloatingPanel(contentRect: NSRect(x: 20, y: 20, width: 688, height: 844))
        let container = WebPanelContainerView()
        let host = FullscreenSourceHostController(
            container: container,
            resizeHandle: PanelResizeHandleView(),
            resizeReadout: ResizeReadoutView(),
            shellWindow: shell
        )
        let root = try! XCTUnwrap(host.window.contentView)
        let containerIndex = try! XCTUnwrap(root.subviews.firstIndex(where: { $0 === container }))

        let overlay = AddressOverlayView(frame: NSRect(x: 20, y: 20, width: 240, height: 52))
        host.transientUIContainerView.addSubview(overlay)
        let overlayIndex = try! XCTUnwrap(root.subviews.firstIndex(where: { $0 === overlay }))

        XCTAssertTrue(host.transientUIContainerView === root)
        XCTAssertGreaterThan(overlayIndex, containerIndex)
    }

    func testFullscreenSourceSessionStaysLockedUntilRestorePhaseCompletes() {
        var state = FullscreenSourceSessionState.idle

        state = .next(from: state, webKitState: .enteringFullscreen)
        XCTAssertEqual(state, .entering)
        XCTAssertTrue(state.locksSourceHost)

        state = .next(from: state, webKitState: .inFullscreen)
        XCTAssertEqual(state, .fullscreen)
        XCTAssertTrue(state.locksSourceHost)

        state = .next(from: state, webKitState: .exitingFullscreen)
        XCTAssertEqual(state, .exiting)
        XCTAssertTrue(state.locksSourceHost)

        state = .next(from: state, webKitState: .notInFullscreen)
        XCTAssertEqual(state, .restoring)
        XCTAssertTrue(state.locksSourceHost)
    }

    func testFullscreenSourceSessionCanStartASecondEntryAfterAnIncompleteRestore() {
        XCTAssertEqual(
            FullscreenSourceSessionState.next(
                from: .restoring,
                webKitState: .enteringFullscreen
            ),
            .entering
        )
        XCTAssertEqual(
            FullscreenSourceSessionState.next(
                from: .restoring,
                webKitState: .inFullscreen
            ),
            .fullscreen
        )
    }

    func testSourceHostFrameMatchesOnlyTheWebViewport() {
        let shell = NSRect(x: 100, y: 200, width: 688, height: 844)
        let source = FullscreenSourceHostController.sourceFrame(forShellFrame: shell)

        XCTAssertEqual(source.origin.x, 176, accuracy: 0.001)
        XCTAssertEqual(source.origin.y, 212, accuracy: 0.001)
        XCTAssertEqual(source.size.width, 600, accuracy: 0.001)
        XCTAssertEqual(source.size.height, 820, accuracy: 0.001)
    }

    func testSourceHostFrameMatchesCollapsedWebViewport() {
        let shell = NSRect(x: 100, y: 200, width: 688, height: 844)

        let collapsed = FullscreenSourceHostController.sourceFrame(
            forShellFrame: shell,
            leadingInset: PanelMetrics.collapsedRailLeadingInset
        )
        XCTAssertEqual(collapsed.origin.x, 112, accuracy: 0.001)
        XCTAssertEqual(collapsed.origin.y, 212, accuracy: 0.001)
        XCTAssertEqual(collapsed.size.width, 664, accuracy: 0.001)
        XCTAssertEqual(collapsed.size.height, 820, accuracy: 0.001)

        let expandedDefault = FullscreenSourceHostController.sourceFrame(forShellFrame: shell)
        XCTAssertEqual(expandedDefault.origin.x, 176, accuracy: 0.001)
        XCTAssertEqual(expandedDefault.size.width, 600, accuracy: 0.001)
    }

    func testPanelRootKeepsWebContainerOutOfFloatingShellHierarchy() {
        let root = PanelRootView()

        XCTAssertNil(root.webPanelContainerView.superview)
        XCTAssertTrue(root.webViewportLayoutView.superview === root)
    }

    func testFullscreenExitPlaceholderOccupiesShellViewportAndReceivesClicks() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)

        root.installFullscreenExitPlaceholder()
        root.layoutSubtreeIfNeeded()

        XCTAssertTrue(root.fullscreenExitPlaceholderView.superview === root)
        XCTAssertEqual(
            root.fullscreenExitPlaceholderView.frame,
            root.webViewportLayoutView.frame
        )

        let viewportPoint = NSPoint(
            x: root.fullscreenExitPlaceholderView.frame.midX,
            y: root.fullscreenExitPlaceholderView.frame.midY
        )
        XCTAssertNotNil(root.hitTest(viewportPoint))
    }

    func testFullscreenCompanionContainerOccupiesShellViewportAndReceivesClicks() {
        let root = PanelRootView()
        let companion = WebPanelContainerView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)

        root.installFullscreenCompanionContainer(companion)
        root.layoutSubtreeIfNeeded()

        XCTAssertTrue(companion.superview === root)
        XCTAssertEqual(companion.frame, root.webViewportLayoutView.frame)

        let viewportPoint = NSPoint(x: companion.frame.midX, y: companion.frame.midY)
        XCTAssertNotNil(root.hitTest(viewportPoint))

        root.removeFullscreenCompanionContainer(companion)
        XCTAssertNil(companion.superview)
    }

    func testInstallingCompanionReplacesFullscreenExitPlaceholder() {
        let root = PanelRootView()
        let companion = WebPanelContainerView()

        root.installFullscreenExitPlaceholder()
        root.installFullscreenCompanionContainer(companion)

        XCTAssertNil(root.fullscreenExitPlaceholderView.superview)
        XCTAssertTrue(companion.superview === root)
    }

    func testInstallingFullscreenExitPlaceholderReplacesCompanion() {
        let root = PanelRootView()
        let companion = WebPanelContainerView()

        root.installFullscreenCompanionContainer(companion)
        root.installFullscreenExitPlaceholder()

        XCTAssertNil(companion.superview)
        XCTAssertTrue(root.fullscreenExitPlaceholderView.superview === root)
    }

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

    func testWorkspaceAutoHideSuppressionArmsGraceWindowAtPresentation() {
        var suppression = WorkspaceAutoHideSuppression()

        suppression.arm(atUptime: 100)

        XCTAssertTrue(suppression.suppressesAutoHide(nowUptime: 100.1))
        XCTAssertTrue(suppression.suppressesAutoHide(nowUptime: 101))
        XCTAssertTrue(suppression.suppressesAutoHide(nowUptime: 101.499))
        XCTAssertFalse(suppression.suppressesAutoHide(nowUptime: 101.5))
    }

    func testWorkspaceAutoHideSuppressionStartsDisarmed() {
        let suppression = WorkspaceAutoHideSuppression()

        XCTAssertFalse(suppression.suppressesAutoHide(nowUptime: 0))
    }

    func testGlobalShortcutHidesOnlyWhenFloatTabsOwnsFocus() {
        XCTAssertTrue(
            PanelController.shouldHideForGlobalShortcut(
                shellIsVisible: true,
                shellIsKey: true,
                sourceIsKey: false
            )
        )
        XCTAssertTrue(
            PanelController.shouldHideForGlobalShortcut(
                shellIsVisible: true,
                shellIsKey: false,
                sourceIsKey: true
            )
        )
        XCTAssertFalse(
            PanelController.shouldHideForGlobalShortcut(
                shellIsVisible: true,
                shellIsKey: false,
                sourceIsKey: false
            )
        )
        XCTAssertFalse(
            PanelController.shouldHideForGlobalShortcut(
                shellIsVisible: false,
                shellIsKey: true,
                sourceIsKey: true
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

    func testGlobalFirstMouseInsideVisibleSourceDoesNotAutoHidePresentation() {
        XCTAssertTrue(
            PanelController.externalMouseDownIsInsideVisiblePresentation(
                mouseLocation: NSPoint(x: 150, y: 150),
                shellFrame: NSRect(x: 0, y: 0, width: 50, height: 50),
                shellIsVisible: true,
                sourceFrame: NSRect(x: 100, y: 100, width: 200, height: 200),
                sourceIsVisibleAndIdle: true
            )
        )
    }

    func testGlobalMouseOutsidePresentationStillAllowsAutoHide() {
        XCTAssertFalse(
            PanelController.externalMouseDownIsInsideVisiblePresentation(
                mouseLocation: NSPoint(x: 500, y: 500),
                shellFrame: NSRect(x: 0, y: 0, width: 50, height: 50),
                shellIsVisible: true,
                sourceFrame: NSRect(x: 100, y: 100, width: 200, height: 200),
                sourceIsVisibleAndIdle: true
            )
        )
    }

    func testHiddenOrFullscreenSourceDoesNotMaskRealExternalClick() {
        XCTAssertFalse(
            PanelController.externalMouseDownIsInsideVisiblePresentation(
                mouseLocation: NSPoint(x: 150, y: 150),
                shellFrame: .zero,
                shellIsVisible: false,
                sourceFrame: NSRect(x: 100, y: 100, width: 200, height: 200),
                sourceIsVisibleAndIdle: false
            )
        )
    }

    func testPanelAutoHideDecisionRespectsPin() {
        XCTAssertTrue(PanelController.shouldAutoHide(panelIsVisible: true, isPinned: false))
        XCTAssertFalse(PanelController.shouldAutoHide(panelIsVisible: true, isPinned: true))
        XCTAssertFalse(PanelController.shouldAutoHide(panelIsVisible: false, isPinned: false))
    }

    func testPinnedPresentationUsesFloatingWindowLevel() {
        let shell = FloatingPanel(
            contentRect: NSRect(x: 20, y: 20, width: 688, height: 844)
        )
        let host = FullscreenSourceHostController(
            container: WebPanelContainerView(),
            resizeHandle: PanelResizeHandleView(),
            resizeReadout: ResizeReadoutView(),
            shellWindow: shell
        )

        shell.setPinnedPresentation(true)
        host.setPinnedPresentation(true)
        XCTAssertEqual(shell.level, .floating)
        XCTAssertEqual(host.window.level, .floating)

        shell.setPinnedPresentation(false)
        host.setPinnedPresentation(false)
        XCTAssertEqual(shell.level, .normal)
        XCTAssertEqual(host.window.level, .normal)
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
        assertShortcut(first, matches: .returnHome)

        let actionTitles = menu.items
            .filter { !$0.isSeparatorItem }
            .map(\.title)
        XCTAssertEqual(
            actionTitles,
            ["Return to Home", "Reload", "Website Mode", "Window Size", "Zoom", "Profile", "Open in New Tab with Profile", "Residency", "Background Media", "Edit Web App…", "Remove Web App…"]
        )
        let reload = try! XCTUnwrap(menu.item(withTitle: "Reload"))
        assertShortcut(reload, matches: .reload)
        XCTAssertTrue(reload.isEnabled)

        XCTAssertEqual(menu.item(withTitle: "Website Mode")?.submenu?.items.map(\.title), ["Desktop", "Mobile"])
        XCTAssertEqual(
            menu.item(withTitle: "Window Size")?.submenu?.items.filter { !$0.isSeparatorItem }.map(\.title),
            ["Small  420 × 760", "Medium  600 × 820", "Large  820 × 850", "Wide  1080 × 850"]
        )
        let zoomItems = try! XCTUnwrap(menu.item(withTitle: "Zoom")?.submenu?.items)
        XCTAssertEqual(zoomItems[0].title, "Zoom In")
        assertShortcut(zoomItems[0], matches: .zoomIn)
        XCTAssertEqual(zoomItems[1].title, "Zoom Out")
        assertShortcut(zoomItems[1], matches: .zoomOut)
        XCTAssertEqual(zoomItems[2].title, "Reset Zoom")
        assertShortcut(zoomItems[2], matches: .resetZoom)
        XCTAssertTrue(zoomItems[3].isSeparatorItem)

        XCTAssertEqual(menu.item(withTitle: "Residency")?.submenu?.items.map(\.title), ["Hot", "Warm", "Cold"])
        XCTAssertEqual(
            menu.item(withTitle: "Background Media")?.submenu?.items.map(\.title),
            ["Pause When Inactive", "Allow Background Audio"]
        )
        XCTAssertEqual(
            menu.item(withTitle: "Profile")?.submenu?.items.map(\.title),
            ["Default", "", "Manage Profiles…"]
        )
        XCTAssertEqual(
            menu.item(withTitle: "Open in New Tab with Profile")?.submenu?.items.map(\.title),
            ["Default"]
        )
        XCTAssertFalse(actionTitles.contains("Rename…"))
    }

    func testFixedWindowModeDisablesPerTabWindowSizeMenu() {
        let (_, zone) = makeZoneHarness()
        let active = makeProfile(order: 0, name: "GPT")
        zone.apply(profiles: [active], activeTabID: active.id)
        zone.setWindowSizeEditingEnabled(false)
        zone.layoutSubtreeIfNeeded()

        let tab = try! XCTUnwrap(zone.tabView(for: active.id))
        let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: tab.frame.midX, y: tab.frame.midY),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 91,
            clickCount: 1,
            pressure: 1
        )!
        let menu = try! XCTUnwrap(tab.menu(for: event))
        XCTAssertFalse(try! XCTUnwrap(menu.item(withTitle: "Window Size")).isEnabled)
    }

    func testFixedWindowModeNeverWritesManualResizeIntoActiveWebApp() {
        XCTAssertTrue(
            PanelController.shouldPersistManualViewportToActiveTab(
                windowSizeMode: .perWebApp
            )
        )
        XCTAssertFalse(
            PanelController.shouldPersistManualViewportToActiveTab(
                windowSizeMode: .fixed
            )
        )
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

    func testDarkRailReapplyAndNewInactiveTabResolveLayerColorsFromEffectiveAppearance() {
        let (_, zone) = makeZoneHarness()
        zone.appearance = NSAppearance(named: .darkAqua)

        let active = makeProfile(order: 0, name: "Active")
        let inactive = makeProfile(order: 1, name: "Inactive")
        zone.apply(profiles: [active, inactive], activeTabID: active.id)
        zone.layoutSubtreeIfNeeded()

        assertTabFill(
            try! XCTUnwrap(zone.tabView(for: inactive.id)),
            matches: NSColor.controlBackgroundColor.withAlphaComponent(0.82),
            appearance: try! XCTUnwrap(zone.appearance)
        )

        // Hidden → shown synchronization reapplies every profile. A newly
        // inserted, never-hovered Tab follows the same path.
        let newlyAdded = makeProfile(order: 2, name: "New")
        zone.apply(
            profiles: [active, inactive, newlyAdded],
            activeTabID: active.id
        )
        zone.layoutSubtreeIfNeeded()

        assertTabFill(
            try! XCTUnwrap(zone.tabView(for: inactive.id)),
            matches: NSColor.controlBackgroundColor.withAlphaComponent(0.82),
            appearance: try! XCTUnwrap(zone.appearance)
        )
        assertTabFill(
            try! XCTUnwrap(zone.tabView(for: newlyAdded.id)),
            matches: NSColor.controlBackgroundColor.withAlphaComponent(0.82),
            appearance: try! XCTUnwrap(zone.appearance)
        )
    }

    func testLightRailReapplyResolvesLayerColorsFromExplicitLightAppearance() {
        let (_, zone) = makeZoneHarness()
        zone.appearance = NSAppearance(named: .aqua)

        let active = makeProfile(order: 0, name: "Active")
        let inactive = makeProfile(order: 1, name: "Inactive")
        zone.apply(profiles: [active, inactive], activeTabID: active.id)
        zone.layoutSubtreeIfNeeded()

        assertTabFill(
            try! XCTUnwrap(zone.tabView(for: inactive.id)),
            matches: NSColor.controlBackgroundColor.withAlphaComponent(0.82),
            appearance: zone.effectiveAppearance
        )
    }

    func testSystemRailInheritsCurrentHostAppearanceAcrossLightDarkChanges() {
        let (host, zone) = makeZoneHarness()
        zone.appearance = nil
        host.appearance = NSAppearance(named: .darkAqua)

        let active = makeProfile(order: 0, name: "Active")
        let inactive = makeProfile(order: 1, name: "Inactive")
        zone.apply(profiles: [active, inactive], activeTabID: active.id)
        zone.layoutSubtreeIfNeeded()
        zone.refreshAppearance()

        assertTabFill(
            try! XCTUnwrap(zone.tabView(for: inactive.id)),
            matches: NSColor.controlBackgroundColor.withAlphaComponent(0.82),
            appearance: zone.effectiveAppearance
        )

        host.appearance = NSAppearance(named: .aqua)
        zone.refreshAppearance()

        assertTabFill(
            try! XCTUnwrap(zone.tabView(for: inactive.id)),
            matches: NSColor.controlBackgroundColor.withAlphaComponent(0.82),
            appearance: zone.effectiveAppearance
        )
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

    func testRailControlsAcceptFirstMouseForSingleClickActivation() {
        let (_, zone) = makeZoneHarness()
        let active = makeProfile(order: 0, name: "GPT")
        zone.apply(profiles: [active], activeTabID: active.id)
        zone.layoutSubtreeIfNeeded()

        XCTAssertTrue(try! XCTUnwrap(zone.tabView(for: active.id)).acceptsFirstMouse(for: nil))
        XCTAssertTrue(RailFoldControl().acceptsFirstMouse(for: nil))
    }

    func testRailSystemControlsAcceptFirstMouseForSingleClickActivation() {
        XCTAssertTrue(AddWebAppControl().acceptsFirstMouse(for: nil))
        XCTAssertTrue(PinPanelControl().acceptsFirstMouse(for: nil))
        XCTAssertTrue(GlobalSettingsControl().acceptsFirstMouse(for: nil))
    }

    func testRailControlsResetArrowCursorRectsWhenInstalledInWindow() {
        let shell = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        )
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        shell.contentView = root
        let active = makeProfile(order: 0, name: "GPT")
        root.externalControlZoneView.apply(profiles: [active], activeTabID: active.id)
        root.layoutSubtreeIfNeeded()

        let tab = try! XCTUnwrap(root.externalControlZoneView.tabView(for: active.id))
        let addControl = AddWebAppControl(frame: NSRect(x: 0, y: 400, width: 32, height: 32))
        let pinControl = PinPanelControl(frame: NSRect(x: 0, y: 360, width: 32, height: 32))
        let settingsControl = GlobalSettingsControl(frame: NSRect(x: 0, y: 320, width: 32, height: 32))
        root.externalControlZoneView.addSubview(addControl)
        root.externalControlZoneView.addSubview(pinControl)
        root.externalControlZoneView.addSubview(settingsControl)

        for control: NSView in [tab, addControl, pinControl, settingsControl] {
            control.resetCursorRects()
            let center = NSPoint(x: control.bounds.midX, y: control.bounds.midY)
            let centerInZoneSuperview = control.convert(center, to: root)
            XCTAssertNotNil(root.externalControlZoneView.hitTest(centerInZoneSuperview))
        }
    }

    func testResizeHandleLivesInsideWebCornerInsteadOfOuterTransparentGutter() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let webFrame = root.webViewportLayoutView.frame
        let insideWebCorner = NSPoint(x: webFrame.maxX - 4, y: webFrame.minY + 4)
        XCTAssertTrue(root.hitTest(insideWebCorner) is PanelResizeHandleView)

        let outerTransparentCorner = NSPoint(
            x: root.bounds.maxX - 4,
            y: root.bounds.minY + 4
        )
        XCTAssertFalse(root.hitTest(outerTransparentCorner) is PanelResizeHandleView)
    }

    func testMovementTargetsUseMatchingInnerAndOuterDepthOnEveryEdge() {
        XCTAssertEqual(
            PanelMetrics.innerMovementOverlap,
            PanelMetrics.outerInteractionGutter
        )

        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()
        let webFrame = root.webViewportLayoutView.frame

        let shellOuterPoints = [
            NSPoint(x: webFrame.midX, y: webFrame.maxY + 8),
            NSPoint(x: webFrame.midX, y: webFrame.minY - 8),
            NSPoint(x: webFrame.minX - 8, y: webFrame.midY),
            NSPoint(x: webFrame.maxX + 8, y: webFrame.midY),
        ]
        for point in shellOuterPoints {
            XCTAssertTrue(root.hitTest(point) is PanelPerimeterDragView)
        }

        let sourceBounds = NSRect(origin: .zero, size: webFrame.size)
        let sourceInnerPoints = [
            NSPoint(x: sourceBounds.midX, y: sourceBounds.maxY - 8),
            NSPoint(x: sourceBounds.midX, y: sourceBounds.minY + 8),
            NSPoint(x: sourceBounds.minX + 8, y: sourceBounds.midY),
            NSPoint(x: sourceBounds.maxX - 8, y: sourceBounds.midY),
        ]
        let sourceRects = WebSourceEdgeDragView.dragRects(in: sourceBounds)
        for point in sourceInnerPoints {
            XCTAssertTrue(sourceRects.contains(where: { $0.contains(point) }))
        }
    }

    func testRightOuterGutterIsARealMovementTargetInsteadOfClickingThrough() {
        XCTAssertGreaterThan(PanelPerimeterDragView.acquisitionSurfaceAlpha, 0)
        XCTAssertLessThan(PanelPerimeterDragView.acquisitionSurfaceAlpha, 0.01)

        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.layoutSubtreeIfNeeded()

        let rightGutterPoint = NSPoint(x: root.bounds.maxX - 4, y: root.bounds.midY)
        XCTAssertTrue(root.hitTest(rightGutterPoint) is PanelPerimeterDragView)
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
        XCTAssertTrue(PanelPerimeterDragView.dragRects(in: drag.bounds).contains {
            $0.contains(localTop)
        })
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

    func testFoldControlCollapsesRailAndReclaimsRailColumnForWebContent() {
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        let active = makeProfile(order: 0, name: "GPT")
        root.externalControlZoneView.apply(profiles: [active], activeTabID: active.id)
        root.layoutSubtreeIfNeeded()

        root.setTabRailCollapsed(true, animated: false)
        root.layoutSubtreeIfNeeded()

        XCTAssertTrue(root.externalControlZoneView.isRailCollapsed)
        XCTAssertNil(root.externalControlZoneView.activeTabFrame(in: root))
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
            root.webViewportLayoutView.frame.maxX,
            root.bounds.maxX - PanelMetrics.outerInteractionGutter,
            accuracy: 0.001
        )
        XCTAssertTrue(try! XCTUnwrap(
            root.externalControlZoneView.tabView(for: active.id)
        ).isHidden)
    }

    func testFoldControlsLiveInsideBottomLeftPageCorner() {
        let shell = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        )
        let root = PanelRootView()
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        shell.contentView = root
        let host = FullscreenSourceHostController(
            container: root.webPanelContainerView,
            resizeHandle: root.resizeHandleView,
            resizeReadout: root.resizeReadoutView,
            shellWindow: shell
        )
        host.window.contentView?.frame = NSRect(
            origin: .zero,
            size: PanelMetrics.defaultViewportSize
        )
        host.window.contentView?.layoutSubtreeIfNeeded()
        root.layoutSubtreeIfNeeded()

        XCTAssertEqual(host.railFoldControl.frame.minX, 0, accuracy: 0.001)
        XCTAssertEqual(host.railFoldControl.frame.minY, 0, accuracy: 0.001)
        XCTAssertEqual(
            host.railFoldControl.frame.size,
            NSSize(
                width: PanelMetrics.resizeHandleSize,
                height: PanelMetrics.resizeHandleSize
            )
        )

        let webFrame = root.webViewportLayoutView.frame
        let companionFrame = root.companionRailFoldControlView.frame
        XCTAssertEqual(companionFrame.minX, webFrame.minX, accuracy: 0.001)
        XCTAssertEqual(companionFrame.minY, webFrame.minY, accuracy: 0.001)
        XCTAssertTrue(webFrame.contains(companionFrame))
    }

    func testNewTabsRemainHiddenWhileRailIsCollapsed() {
        let (_, zone) = makeZoneHarness()
        zone.setCollapsed(true, animated: false)
        let profile = makeProfile(order: 0, name: "Added While Hidden")

        zone.apply(profiles: [profile], activeTabID: profile.id)
        zone.layoutSubtreeIfNeeded()

        XCTAssertTrue(try! XCTUnwrap(zone.tabView(for: profile.id)).isHidden)
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

    func testStatusItemMenuBarDisplayModesSwitchTitleAndReclaimWidth() {
        XCTAssertEqual(
            StatusItemController.displayTitle(
                for: "ChatGPT",
                displayMode: .iconAndName
            ),
            "ChatGPT"
        )
        XCTAssertEqual(
            StatusItemController.displayTitle(
                for: "ChatGPT",
                displayMode: .iconOnly
            ),
            ""
        )
        XCTAssertEqual(
            StatusItemController.displayTitle(
                for: nil,
                displayMode: .iconAndName
            ),
            "FloatTabs"
        )
        XCTAssertEqual(
            StatusItemController.displayTitle(
                for: nil,
                displayMode: .iconOnly
            ),
            ""
        )
        XCTAssertEqual(
            StatusItemController.imagePosition(for: .iconAndName),
            .imageLeading
        )
        XCTAssertEqual(
            StatusItemController.imagePosition(for: .iconOnly),
            .imageOnly
        )
    }

#if DEBUG
    func testDebugStatusItemShowsTestMarkerAfterIcon() {
        let suiteName = "FloatTabsTests.StatusItemController.TestMarker.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferencesStore = AppPreferencesStore(defaults: defaults)
        preferencesStore.menuBarDisplayMode = .iconOnly
        let controller = StatusItemController(
            onToggle: {},
            isVisible: { false },
            onSettings: {},
            onQuit: {},
            preferencesStore: preferencesStore
        )
        controller.setActiveWebApp(name: "ChatGPT", faviconURL: nil)

        XCTAssertEqual(StatusItemController.buildMarker, "Test")
        XCTAssertEqual(controller.debugStatusButtonTitle, "Test")
        XCTAssertEqual(controller.debugStatusButtonImagePosition, .imageLeading)
    }
#endif

    func testStatusItemModeSwitchUsesLivePreferenceWiringAndPreservesPresentation() {
        let suiteName = "FloatTabsTests.StatusItemController.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferencesStore = AppPreferencesStore(defaults: defaults)
        let controller = StatusItemController(
            onToggle: {},
            isVisible: { false },
            onSettings: {},
            onQuit: {},
            preferencesStore: preferencesStore
        )
        controller.setActiveWebApp(name: "ChatGPT", faviconURL: nil)
        controller.setAttentionPresentation(readyCount: 3, floatTabsVisible: false)

        XCTAssertEqual(preferencesStore.menuBarDisplayMode, .iconAndName)
        XCTAssertEqual(
            controller.debugStatusButtonTitle,
            StatusItemController.buildMarker ?? "ChatGPT"
        )
        XCTAssertEqual(controller.debugStatusButtonImagePosition, .imageLeading)
        XCTAssertEqual(controller.attentionPresentation.badge, .count("3"))
        let iconAndNameImage = controller.debugStatusButtonImageTIFF
        XCTAssertNotNil(iconAndNameImage)

        // This is the production mutation. The test deliberately does not
        // invoke StatusItemController's notification selector directly.
        preferencesStore.menuBarDisplayMode = .iconOnly

        XCTAssertEqual(
            controller.debugStatusButtonTitle,
            StatusItemController.buildMarker ?? ""
        )
        XCTAssertEqual(
            controller.debugStatusButtonImagePosition,
            StatusItemController.buildMarker == nil ? .imageOnly : .imageLeading
        )
        XCTAssertEqual(controller.attentionPresentation.badge, .count("3"))
        XCTAssertEqual(controller.debugStatusButtonImageTIFF, iconAndNameImage)

        controller.setActiveWebApp(name: "Docs", faviconURL: nil)
        XCTAssertEqual(
            controller.debugStatusButtonTitle,
            StatusItemController.buildMarker ?? ""
        )

        preferencesStore.menuBarDisplayMode = .iconAndName

        XCTAssertEqual(
            controller.debugStatusButtonTitle,
            StatusItemController.buildMarker ?? "Docs"
        )
        XCTAssertEqual(controller.debugStatusButtonImagePosition, .imageLeading)
        XCTAssertEqual(controller.attentionPresentation.badge, .count("3"))
        XCTAssertEqual(controller.debugStatusButtonImageTIFF, iconAndNameImage)
    }

    func testStatusItemKeepsSameOriginFaviconAndRejectsStaleCrossOriginCompletions() {
        var completions: [(NSImage?) -> Void] = []
        let controller = StatusItemController(
            onToggle: {},
            isVisible: { false },
            onSettings: {},
            onQuit: {},
            faviconLoader: { _, completion in
                completions.append(completion)
            }
        )
        let siteA = URL(string: "https://chatgpt.com/chat-a")!
        let siteAPathChange = URL(string: "https://chatgpt.com/chat-b")!
        let siteB = URL(string: "https://docs.example.test/page")!

        let imageA = NSImage(size: NSSize(width: 16, height: 16))
        imageA.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        imageA.unlockFocus()
        let imageB = NSImage(size: NSSize(width: 16, height: 16))
        imageB.lockFocus()
        NSColor.systemGreen.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        imageB.unlockFocus()

        controller.setActiveWebApp(name: "ChatGPT", faviconURL: siteA)
        XCTAssertEqual(completions.count, 1)
        completions[0](imageA)
        let imageAProjection = controller.debugStatusButtonImageTIFF

        controller.setActiveWebApp(name: "ChatGPT", faviconURL: siteAPathChange)
        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(
            controller.debugSelectedFaviconOriginKey,
            "https://chatgpt.com"
        )
        XCTAssertEqual(controller.debugStatusButtonImageTIFF, imageAProjection)

        controller.setAttentionPresentation(readyCount: 2, floatTabsVisible: false)
        controller.setActiveWebApp(name: "Docs", faviconURL: siteB)
        XCTAssertEqual(completions.count, 2)
        XCTAssertEqual(
            controller.debugSelectedFaviconOriginKey,
            "https://docs.example.test"
        )
        let crossOriginFallback = controller.debugStatusButtonImageTIFF

        completions[0](imageA)
        XCTAssertEqual(controller.debugStatusButtonImageTIFF, crossOriginFallback)
        XCTAssertEqual(controller.attentionPresentation.badge, .count("2"))

        completions[1](imageB)
        XCTAssertNotEqual(controller.debugStatusButtonImageTIFF, crossOriginFallback)
        XCTAssertEqual(controller.attentionPresentation.badge, .count("2"))
    }

    func testStatusItemProjectsCurrentFaviconInBothMenuBarDisplayModes() {
        let suiteName = "FloatTabsTests.StatusItemController.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferencesStore = AppPreferencesStore(defaults: defaults)
        var completion: ((NSImage?) -> Void)?
        let controller = StatusItemController(
            onToggle: {},
            isVisible: { false },
            onSettings: {},
            onQuit: {},
            preferencesStore: preferencesStore,
            faviconLoader: { _, handler in
                completion = handler
            }
        )
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        image.unlockFocus()

        controller.setActiveWebApp(
            name: "Current Site",
            faviconURL: URL(string: "https://current.example.test/path")!
        )
        completion?(image)
        let currentImage = controller.debugStatusButtonImageTIFF

        XCTAssertEqual(
            controller.debugStatusButtonTitle,
            StatusItemController.buildMarker ?? "Current Site"
        )
        XCTAssertEqual(controller.debugStatusButtonImagePosition, .imageLeading)
        XCTAssertEqual(controller.debugStatusButtonImageTIFF, currentImage)

        preferencesStore.menuBarDisplayMode = .iconOnly

        XCTAssertEqual(
            controller.debugStatusButtonTitle,
            StatusItemController.buildMarker ?? ""
        )
        XCTAssertEqual(
            controller.debugStatusButtonImagePosition,
            StatusItemController.buildMarker == nil ? .imageOnly : .imageLeading
        )
        XCTAssertEqual(controller.debugStatusButtonImageTIFF, currentImage)
    }

    func testStatusItemRejectsStaleFaviconCompletionAfterSelectionChanges() {
        XCTAssertFalse(
            StatusItemController.acceptsFaviconCompletion(
                selectedOriginKey: "https://docs.example",
                completionOriginKey: "https://chatgpt.com"
            )
        )
        XCTAssertTrue(
            StatusItemController.acceptsFaviconCompletion(
                selectedOriginKey: "https://chatgpt.com",
                completionOriginKey: "https://chatgpt.com"
            )
        )
    }

    func testStatusItemAttentionHidesAggregateWhileFloatTabsIsVisible() {
        for readyCount in [0, 1, 5] {
            let presentation = StatusItemController.attentionPresentation(
                readyCount: readyCount,
                floatTabsVisible: true
            )

            XCTAssertEqual(presentation.badge, .none)
        }
    }

    func testStatusItemAttentionUsesDotExactCountAndCappedCountWhileHidden() {
        XCTAssertEqual(
            StatusItemController.attentionPresentation(
                readyCount: 0,
                floatTabsVisible: false
            ).badge,
            .none
        )
        XCTAssertEqual(
            StatusItemController.attentionPresentation(
                readyCount: 1,
                floatTabsVisible: false
            ).badge,
            .dot
        )
        XCTAssertEqual(
            StatusItemController.attentionPresentation(
                readyCount: 2,
                floatTabsVisible: false
            ).badge,
            .count("2")
        )
        XCTAssertEqual(
            StatusItemController.attentionPresentation(
                readyCount: 9,
                floatTabsVisible: false
            ).badge,
            .count("9")
        )
        XCTAssertEqual(
            StatusItemController.attentionPresentation(
                readyCount: 10,
                floatTabsVisible: false
            ).badge,
            .count("9+")
        )
        XCTAssertEqual(
            StatusItemController.attentionPresentation(
                readyCount: 100,
                floatTabsVisible: false
            ).badge,
            .count("9+")
        )
    }

    func testStatusItemAttentionNormalizesNegativeCounts() {
        let presentation = StatusItemController.attentionPresentation(
            readyCount: -1,
            floatTabsVisible: false
        )

        XCTAssertEqual(presentation.readyCount, 0)
        XCTAssertEqual(presentation.badge, .none)
    }

    func testStatusItemAttentionRenderingSupportsFallbackAndCurrentBadge() {
        let presentation = StatusItemController.attentionPresentation(
            readyCount: 3,
            floatTabsVisible: false
        )

        let image = StatusItemController.renderStatusImage(
            favicon: nil,
            attention: presentation
        )

        XCTAssertEqual(image.size, NSSize(width: 16, height: 16))
        XCTAssertNotNil(image.tiffRepresentation)
    }

    func testStatusItemAttentionCountChangeRedrawsAgainstSameFavicon() {
        let source = NSImage(size: NSSize(width: 16, height: 16))
        source.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        source.unlockFocus()

        let countImage = StatusItemController.renderStatusImage(
            favicon: source,
            attention: StatusItemController.attentionPresentation(
                readyCount: 3,
                floatTabsVisible: false
            )
        )
        let dotImage = StatusItemController.renderStatusImage(
            favicon: source,
            attention: StatusItemController.attentionPresentation(
                readyCount: 1,
                floatTabsVisible: false
            )
        )

        XCTAssertNotEqual(countImage.tiffRepresentation, dotImage.tiffRepresentation)
    }

    func testStatusItemAttentionRenderingDoesNotMutateSharedFavicon() {
        let source = NSImage(size: NSSize(width: 16, height: 16))
        source.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        source.unlockFocus()
        let before = source.tiffRepresentation

        _ = StatusItemController.renderStatusImage(
            favicon: source,
            attention: StatusItemController.attentionPresentation(
                readyCount: 2,
                floatTabsVisible: false
            )
        )

        XCTAssertEqual(source.tiffRepresentation, before)
    }

    func testStatusMenuBindsConfiguredToggleAndSettingsShortcuts() {
        let controller = StatusItemController(
            onToggle: {},
            isVisible: { false },
            onSettings: {},
            onQuit: {}
        )

        XCTAssertEqual(
            controller.menuShortcutPresentations["Show FloatTabs"],
            shortcutPresentation(for: .toggleFloatTabs)
        )
        XCTAssertEqual(
            controller.menuShortcutPresentations["Settings…"],
            shortcutPresentation(for: .floatTabsSettings)
        )
    }

    func testStatusItemToggleWaitsUntilEventTrackingModeCompletes() {
        let callback = expectation(description: "deferred status toggle")
        var didRun = false

        StatusItemController.scheduleAfterStatusItemTracking {
            didRun = true
            callback.fulfill()
        }

        XCTAssertFalse(didRun)

        let trackingTimer = Timer(timeInterval: 0.01, repeats: false) { _ in }
        RunLoop.main.add(trackingTimer, forMode: .eventTracking)
        _ = RunLoop.main.run(
            mode: .eventTracking,
            before: Date(timeIntervalSinceNow: 0.1)
        )

        XCTAssertFalse(didRun)
        wait(for: [callback], timeout: 1)
        XCTAssertTrue(didRun)
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

    func testFaviconProviderDiscoversRelativeAbsoluteAndAppleTouchIcons() {
        let baseURL = URL(string: "https://gemini.google.com/app")!
        let html = """
        <!doctype html>
        <head>
          <base href="https://gemini.google.com/">
          <link rel="preconnect" href="https://www.gstatic.com">
          <link rel="icon" type="image/svg+xml" href="icons/gemini.svg">
          <link rel="icon" type="image/png" href="https://www.gstatic.com/gemini.png">
          <link rel="apple-touch-icon" href="/touch-icon.png">
          <link rel="icon" href="javascript:alert(1)">
        </head>
        """

        XCTAssertEqual(
            WebsiteFaviconProvider.discoveredFaviconURLs(
                in: html,
                baseURL: baseURL
            ).map(\.absoluteString),
            [
                "https://gemini.google.com/icons/gemini.svg",
                "https://www.gstatic.com/gemini.png",
                "https://gemini.google.com/touch-icon.png",
            ]
        )
    }

    func testFaviconProviderFallsBackToHeadLinksWhenFaviconEndpointIsNotAnImage() async {
        let pageURL = URL(string: "https://gemini.google.com/app")!
        let svgURL = URL(string: "https://www.gstatic.com/gemini.svg")!
        let pngURL = URL(string: "https://www.gstatic.com/gemini.png")!
        let html = """
        <link rel="icon" type="image/svg+xml" href="\(svgURL.absoluteString)">
        <link rel="icon" type="image/png" href="\(pngURL.absoluteString)">
        """
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        image.unlockFocus()
        let imageData = try! XCTUnwrap(image.tiffRepresentation)
        var requestedURLs: [URL] = []

        let provider = WebsiteFaviconProvider(dataLoader: { request in
            let requestURL = try XCTUnwrap(request.url)
            requestedURLs.append(requestURL)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: requestURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            if requestURL.path == "/favicon.ico"
                || requestURL.path == "/favicon.png"
                || requestURL.path == "/favicon.svg"
                || requestURL.path == "/apple-touch-icon.png"
                || requestURL.path == "/apple-touch-icon-precomposed.png" {
                return (Data(), response)
            }
            if requestURL == pageURL {
                return (Data(html.utf8), response)
            }
            if requestURL == svgURL {
                return (Data("not an image".utf8), response)
            }
            if requestURL == pngURL {
                return (imageData, response)
            }
            throw URLError(.fileDoesNotExist)
        })

        let loaded = expectation(description: "favicon loaded")
        var loadedImage: NSImage?
        provider.load(for: pageURL) { image in
            loadedImage = image
            loaded.fulfill()
        }

        await fulfillment(of: [loaded], timeout: 2)
        XCTAssertNotNil(loadedImage)
        XCTAssertEqual(requestedURLs.last, pngURL)
        XCTAssertTrue(requestedURLs.contains(pageURL))
        XCTAssertTrue(requestedURLs.contains(svgURL))
    }

    func testMoveCursorRectsUseSameGeometryAsWindowDrag() {
        let bounds = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        let topPoint = NSPoint(
            x: bounds.midX,
            y: bounds.maxY - PanelMetrics.outerInteractionGutter / 2
        )
        let websiteCenter = NSPoint(
            x: PanelMetrics.externalControlZoneWidth + PanelMetrics.defaultViewportSize.width / 2,
            y: bounds.midY
        )

        let dragRects = PanelPerimeterDragView.dragRects(in: bounds)
        XCTAssertTrue(dragRects.contains(where: { $0.contains(topPoint) }))
        XCTAssertFalse(dragRects.contains(where: { $0.contains(websiteCenter) }))
    }

    func testExpandedTabFramesAreExcludedFromMovementGeometry() {
        let bounds = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        let expandedTab = NSRect(
            x: 0,
            y: ExternalTabMetrics.topOffset,
            width: ExternalTabMetrics.hoverWidth,
            height: ExternalTabMetrics.tabHeight
        )
        let dragRects = PanelPerimeterDragView.dragRects(
            in: bounds,
            excluding: [expandedTab]
        )

        XCTAssertFalse(
            dragRects.contains(where: { $0.intersects(expandedTab) }),
            "An expanded Tab must own its complete width, including the old Web edge band"
        )
        XCTAssertTrue(
            dragRects.contains(where: {
                $0.contains(NSPoint(x: bounds.maxX - PanelMetrics.outerInteractionGutter / 2, y: 100))
            }),
            "An uncovered rail gap should remain eligible for movement"
        )
    }

    func testPanelRootSynchronizesExpandedTabExclusionIntoMovementHitTesting() {
        let profile = makeProfile(order: 0, name: "expanded-tab")
        let root = PanelRootView(webView: WKWebView(frame: .zero))
        root.frame = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        root.externalControlZoneView.apply(
            profiles: [profile],
            activeTabID: profile.id
        )
        root.layoutSubtreeIfNeeded()

        let tab = try! XCTUnwrap(root.externalControlZoneView.tabView(for: profile.id))
        tab.setHovered(true)
        root.externalControlZoneView.layoutSubtreeIfNeeded()
        root.layoutSubtreeIfNeeded()

        let tabFrame = tab.convert(tab.bounds, to: root.perimeterDragView)
        XCTAssertEqual(tabFrame.width, ExternalTabMetrics.hoverWidth, accuracy: 0.001)
        XCTAssertNil(
            root.perimeterDragView.hitTest(
                NSPoint(x: tabFrame.midX, y: tabFrame.midY)
            ),
            "Movement hit testing must yield to a magnified Tab's complete frame"
        )
    }

    func testCollapsedMoveCursorRectsCoverLeadingGutterOnly() {
        let bounds = NSRect(origin: .zero, size: PanelMetrics.defaultPanelSize)
        let collapsedInset = PanelMetrics.collapsedRailLeadingInset
        let gutterPoint = NSPoint(x: collapsedInset / 2, y: bounds.midY)
        let reclaimedPoint = NSPoint(
            x: collapsedInset + (PanelMetrics.externalControlZoneWidth - collapsedInset) / 2,
            y: bounds.midY
        )
        let websiteCenter = NSPoint(
            x: collapsedInset
                + (bounds.width - collapsedInset - PanelMetrics.outerInteractionGutter) / 2,
            y: bounds.midY
        )

        let dragRects = PanelPerimeterDragView.dragRects(in: bounds, leadingInset: collapsedInset)
        XCTAssertTrue(dragRects.contains(where: { $0.contains(gutterPoint) }))
        XCTAssertFalse(dragRects.contains(where: { $0.contains(reclaimedPoint) }))
        XCTAssertFalse(dragRects.contains(where: { $0.contains(websiteCenter) }))
    }

    private func makeZoneHarness() -> (host: NSView, zone: ExternalControlZoneView) {
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 76, height: 820))
        let zone = ExternalControlZoneView(frame: host.bounds)
        host.addSubview(zone)
        zone.layoutSubtreeIfNeeded()
        return (host, zone)
    }

    private func assertShortcut(
        _ menuItem: NSMenuItem,
        matches name: KeyboardShortcuts.Name,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let shortcut = try! XCTUnwrap(
            KeyboardShortcuts.getShortcut(for: name),
            file: file,
            line: line
        )
        XCTAssertEqual(
            menuItem.keyEquivalent,
            shortcut.nsMenuItemKeyEquivalent ?? "",
            file: file,
            line: line
        )
        XCTAssertEqual(
            menuItem.keyEquivalentModifierMask,
            shortcut.modifiers,
            file: file,
            line: line
        )
    }

    private func assertTabFill(
        _ tab: ExternalWebAppTabView,
        matches expectedColor: @autoclosure () -> NSColor,
        appearance: NSAppearance,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actualCGColor = try! XCTUnwrap(
            tab.layer?.sublayers?.compactMap { ($0 as? CAShapeLayer)?.fillColor }.first,
            file: file,
            line: line
        )
        let actual = try! XCTUnwrap(
            NSColor(cgColor: actualCGColor)?.usingColorSpace(.deviceRGB),
            file: file,
            line: line
        )
        var expected: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            // Resolve a dynamic system color only after selecting the intended
            // Light/Dark appearance. This keeps the assertion independent from
            // the CI runner's own System setting.
            expected = expectedColor().usingColorSpace(.deviceRGB)
        }
        let resolvedExpected = try! XCTUnwrap(expected, file: file, line: line)

        XCTAssertEqual(actual.redComponent, resolvedExpected.redComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.greenComponent, resolvedExpected.greenComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.blueComponent, resolvedExpected.blueComponent, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(actual.alphaComponent, resolvedExpected.alphaComponent, accuracy: 0.01, file: file, line: line)
    }

    private func shortcutPresentation(
        for name: KeyboardShortcuts.Name,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> MenuShortcutPresentation {
        let shortcut = try! XCTUnwrap(
            KeyboardShortcuts.getShortcut(for: name),
            file: file,
            line: line
        )
        return MenuShortcutPresentation(
            keyEquivalent: shortcut.nsMenuItemKeyEquivalent ?? "",
            modifiers: shortcut.modifiers
        )
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

private final class FocusableTestView: NSView {
    override var acceptsFirstResponder: Bool { true }
}
