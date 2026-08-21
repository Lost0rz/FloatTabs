#!/usr/bin/env python3
"""MC-B4.0: make the generated Monterey WebView surface strictly 1:1.

This is a build-time transform. The standard source files retain the normal
desktop logical viewport; only the Monterey compatibility generated tree is
rewritten here.
"""

import re
import os
from pathlib import Path

from monterey_transform_lib import (
    read_source,
    replace_exact_once,
    replace_once_regex,
    replace_span_once,
    require_absent,
    require_present,
    write_source,
)

ROOT = Path(os.environ.get("FLOATTABS_TRANSFORM_ROOT", str(Path(__file__).resolve().parents[2])))


ONE_TO_ONE_VIEWPORT = r'''/// Monterey Compatibility Edition uses the visible Window Size as the
/// WebKit viewport. Website Mode is persisted metadata only and never changes
/// WebKit geometry.
enum WebsiteLayoutViewport {
    static func targetCSSWidth(
        forVisibleWidth visibleWidth: CGFloat,
        websiteMode: WebsiteMode
    ) -> CGFloat {
        _ = websiteMode
        return visibleWidth
    }

    static func fittingScale(
        forVisibleWidth visibleWidth: CGFloat,
        websiteMode: WebsiteMode
    ) -> CGFloat {
        _ = visibleWidth
        _ = websiteMode
        return 1
    }

    static func logicalSize(
        forVisibleSize visibleSize: CGSize,
        websiteMode: WebsiteMode
    ) -> CGSize {
        _ = websiteMode
        return visibleSize
    }
}

'''

ONE_TO_ONE_SLOT_LAYOUT = r'''    private func applyWebsiteLayoutIfNeeded() {
        guard !isApplyingWebsiteLayout,
              let webView,
              webView.superview === self,
              frame.width > 0,
              frame.height > 0 else {
            return
        }

        let visibleFrame = NSRect(origin: .zero, size: frame.size)
        isApplyingWebsiteLayout = true
        websiteLayoutScale = 1
        if bounds != visibleFrame {
            bounds = visibleFrame
        }
        if webView.frame != visibleFrame {
            webView.frame = visibleFrame
        }
        if webView.bounds != visibleFrame {
            webView.bounds = visibleFrame
        }
        isApplyingWebsiteLayout = false
    }
'''

ONE_TO_ONE_PANEL_LAYOUT = r'''    private func updateWebsiteLayoutIfNeeded() {
        guard let webView = hostedWebView,
              webView.superview === logicalHostView else { return }

        let visibleSize = clipView.bounds.size
        guard visibleSize.width > 0, visibleSize.height > 0 else { return }

        let visibleFrame = NSRect(origin: .zero, size: visibleSize)
        websiteLayoutScale = 1
        if logicalHostView.bounds != visibleFrame {
            logicalHostView.bounds = visibleFrame
        }
        if webView.frame != visibleFrame {
            webView.frame = visibleFrame
        }
        if webView.bounds != visibleFrame {
            webView.bounds = visibleFrame
        }
    }

'''


def replace_test_method(text: str, method: str, next_method: str, body: str, label: str) -> str:
    return replace_span_once(
        text,
        rf"^    func {method}\(\) \{{",
        rf"^    func {next_method}\(",
        body + "\n\n",
        label=label,
    )


def patch_runtime() -> None:
    path = ROOT / "FloatTabs/Web/WebViewFactory.swift"
    text = read_source(path)
    text = replace_span_once(
        text,
        r"^/// Website Mode owns the responsive layout class",
        r"^@MainActor\nenum WebViewFactory",
        ONE_TO_ONE_VIEWPORT,
        label="MC-B4.0 one-to-one WebsiteLayoutViewport",
    )
    write_source(path, text)

    path = ROOT / "FloatTabs/Web/WebViewContainer.swift"
    text = read_source(path)
    text = replace_span_once(
        text,
        r"^    private func applyWebsiteLayoutIfNeeded\(\) \{",
        r"^}\n\n/// Owns the visible FloatTabs web surface",
        ONE_TO_ONE_SLOT_LAYOUT,
        label="MC-B4.0 WebSlotHostView visible geometry",
    )
    text = replace_span_once(
        text,
        r"^    private func updateWebsiteLayoutIfNeeded\(\) \{",
        r"^    private func updateSemanticColors\(\)",
        ONE_TO_ONE_PANEL_LAYOUT,
        label="MC-B4.0 WebPanelContainerView visible geometry",
    )
    text = replace_exact_once(
        text,
        "No NSScrollView magnification is involved.",
        "No ancestor zoom mapping is involved.",
        label="MC-B4.0 remove obsolete magnification wording",
    )
    write_source(path, text)


def patch_ui() -> None:
    path = ROOT / "FloatTabs/UI/WebAppEditorController.swift"
    text = read_source(path)
    text = replace_exact_once(
        text,
        "    static let websiteModeEnabled = true\n",
        '    static let websiteModeEnabled = false\n'
        '    static let websiteModeDisplayName = "Native · Monterey Compatibility"\n',
        label="MC-B4.0 Website Mode disabled",
    )
    text = replace_exact_once(
        text,
        "        modePopup.addItems(withTitles: WebsiteMode.allCases.map(\\.displayName))\n"
        "        if let index = WebsiteMode.allCases.firstIndex(of: rendering.websiteMode) {\n"
        "            modePopup.selectItem(at: index)\n"
        "        }\n",
        "        modePopup.addItem(withTitle: MontereyCompatibilityUI.websiteModeDisplayName)\n"
        "        modePopup.selectItem(at: 0)\n",
        label="MC-B4.0 honest Website Mode selector",
    )
    text = replace_exact_once(
        text,
        "        orientationPopup.toolTip = devicePopup.toolTip\n",
        "        orientationPopup.toolTip = devicePopup.toolTip\n"
        "        modePopup.isEnabled = MontereyCompatibilityUI.websiteModeEnabled\n"
        "        modePopup.toolTip = MontereyCompatibilityUI.websiteModeDisplayName\n",
        label="MC-B4.0 disabled Website Mode control",
    )
    text = replace_exact_once(
        text,
        "        let modeIndex = modePopup.indexOfSelectedItem\n"
        "        let sizeIndex = sizePopup.indexOfSelectedItem\n",
        "        let sizeIndex = sizePopup.indexOfSelectedItem\n",
        label="MC-B4.0 Website Mode metadata preservation setup",
    )
    text = replace_exact_once(
        text,
        "        guard WebsiteMode.allCases.indices.contains(modeIndex),\n"
        "              SimpleViewportPreset.allCases.indices.contains(sizeIndex),\n",
        "        guard SimpleViewportPreset.allCases.indices.contains(sizeIndex),\n",
        label="MC-B4.0 Website Mode validation removal",
    )
    text = replace_exact_once(
        text,
        "        let mode = WebsiteMode.allCases[modeIndex]\n",
        "        let mode = initialRendering.websiteMode\n",
        label="MC-B4.0 persisted Website Mode metadata",
    )
    write_source(path, text)


def patch_factory_tests() -> None:
    path = ROOT / "FloatTabsTests/WebViewFactoryTests.swift"
    text = read_source(path)
    text = replace_test_method(
        text,
        "testWebsiteLayoutViewportMapsVisibleWidthsToDistinctDesktopExperiences",
        "testMediumDesktopHostUsesBalancedLogicalLayoutWithoutPageZoomFit",
        '''    func testWebsiteLayoutViewportIsOneToOneForDesktopAndMobileMetadata() {
        for mode in WebsiteMode.allCases {
            XCTAssertEqual(
                WebsiteLayoutViewport.targetCSSWidth(forVisibleWidth: 420, websiteMode: mode),
                420,
                accuracy: 0.001
            )
            XCTAssertEqual(
                WebsiteLayoutViewport.fittingScale(forVisibleWidth: 420, websiteMode: mode),
                1,
                accuracy: 0.001
            )
            XCTAssertEqual(
                WebsiteLayoutViewport.logicalSize(
                    forVisibleSize: CGSize(width: 420, height: 760),
                    websiteMode: mode
                ),
                CGSize(width: 420, height: 760)
            )
        }
    }''',
        "MC-B4.0 viewport tests",
    )
    text = replace_test_method(
        text,
        "testMediumDesktopHostUsesBalancedLogicalLayoutWithoutPageZoomFit",
        "testVisibleResizeMovesBetweenDesktopExperienceClassesWithoutPageZoomFit",
        '''    func testMediumDesktopHostUsesVisibleOneToOneGeometry() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 600, height: 820))

        XCTAssertEqual(container.bounds.size, NSSize(width: 600, height: 820))
        XCTAssertEqual(webView.frame, NSRect(x: 0, y: 0, width: 600, height: 820))
        XCTAssertEqual(webView.bounds, webView.frame)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(webView.magnification, 1, accuracy: 0.001)
    }''',
        "MC-B4.0 warm geometry test",
    )
    text = replace_test_method(
        text,
        "testVisibleResizeMovesBetweenDesktopExperienceClassesWithoutPageZoomFit",
        "testSmallDesktopModeUsesCompactResponsiveCSSClass",
        '''    func testVisibleResizeKeepsOneToOneGeometry() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 600, height: 820))

        container.setFrameSize(NSSize(width: 820, height: 850))
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        XCTAssertEqual(container.bounds.size, NSSize(width: 820, height: 850))
        XCTAssertEqual(webView.frame, NSRect(x: 0, y: 0, width: 820, height: 850))
        XCTAssertEqual(webView.bounds, webView.frame)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
    }''',
        "MC-B4.0 resize geometry test",
    )
    text = replace_test_method(
        text,
        "testSmallDesktopModeUsesCompactResponsiveCSSClass",
        "testMontereyExplicitWebsiteModeControlsHostLayoutWithoutWebKitMutation",
        '''    func testSmallDesktopModeUsesNativeVisibleGeometry() {
        let rendering = WebRenderingProfile.canonicalDefault.settingSimplePreset(.small)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let container = host(webView, visibleSize: NSSize(width: 420, height: 760))

        XCTAssertEqual(container.bounds.size, NSSize(width: 420, height: 760))
        XCTAssertEqual(webView.frame, NSRect(x: 0, y: 0, width: 420, height: 760))
        XCTAssertEqual(webView.bounds, webView.frame)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
    }''',
        "MC-B4.0 small geometry test",
    )
    text = replace_test_method(
        text,
        "testMontereyExplicitWebsiteModeControlsHostLayoutWithoutWebKitMutation",
        "testDesktopHostMapsVisibleCenterIntoLogicalWebCoordinates",
        '''    func testWebsiteModeMetadataDoesNotChangeOneToOneGeometry() {
        var loadedRequests: [URLRequest] = []
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) }
        )
        var profile = WebAppProfile(
            order: 0,
            name: "ExplicitWebsiteMode",
            homeURL: URL(string: "https://example.com")!
        )
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 820)
        )

        let desktop = pool.webView(for: profile)
        container.show(webView: desktop, slotID: profile.id, residencyPolicy: .warm, websiteMode: .desktop)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(desktop.frame, NSRect(x: 0, y: 0, width: 600, height: 820))

        profile.renderingProfile = profile.renderingProfile.settingWebsiteMode(.mobile)
        let mobile = pool.webView(for: profile)
        XCTAssertTrue(desktop === mobile)
        container.show(webView: mobile, slotID: profile.id, residencyPolicy: .warm, websiteMode: .mobile)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(mobile.frame, NSRect(x: 0, y: 0, width: 600, height: 820))
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(loadedRequests.count, 1)
    }''',
        "MC-B4.0 Website Mode no-rebuild test",
    )
    text = replace_test_method(
        text,
        "testDesktopHostMapsVisibleCenterIntoLogicalWebCoordinates",
        "testHotHostsPreserveInactiveViewportAcrossDifferentSlotSizes",
        '''    func testDesktopHostPointConversionIsIdentity() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 600, height: 820))

        let sourcePoint = NSPoint(x: 300, y: 410)
        let webPoint = webView.convert(sourcePoint, from: container)
        XCTAssertEqual(webPoint.x, sourcePoint.x, accuracy: 0.001)
        XCTAssertEqual(webPoint.y, sourcePoint.y, accuracy: 0.001)
    }''',
        "MC-B4.0 point conversion test",
    )
    text = replace_test_method(
        text,
        "testHotHostsPreserveInactiveViewportAcrossDifferentSlotSizes",
        "testDesktopLogicalHostKeepsNativeWindowClickHitTestingWorking",
        '''    func testHotHostsUseVisibleOneToOneGeometry() {
        _ = NSApplication.shared
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 820)
        )
        let window = NSWindow(
            contentRect: container.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        let firstID = UUID()
        let first = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)

        container.show(webView: first, slotID: firstID, residencyPolicy: .hot)
        container.layoutSubtreeIfNeeded()

        XCTAssertEqual(first.frame, NSRect(x: 0, y: 0, width: 600, height: 820))
        XCTAssertEqual(first.bounds, first.frame)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertTrue(first.window === window)
        window.orderOut(nil)
    }''',
        "MC-B4.0 hot geometry test",
    )
    text = replace_test_method(
        text,
        "testDesktopLogicalHostKeepsNativeWindowClickHitTestingWorking",
        "testNewWindowPolicyRoutesBlankWebLinksIntoCurrentSlot",
        '''    func testDesktopLogicalHostKeepsNativeWindowClickHitTestingWorking() {
        _ = NSApplication.shared
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 820)
        )
        container.show(webView: webView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 820),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        XCTAssertEqual(webView.frame, NSRect(x: 0, y: 0, width: 600, height: 820))
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
        window.orderOut(nil)
    }''',
        "MC-B4.0 logical host geometry test",
    )
    text = replace_test_method(
        text,
        "testUserZoomStaysIndependentFromDesktopHostLayoutFit",
        "testNavigationObserverRestoresWebsiteModeWithoutDiscardingUserZoom",
        '''    func testUserZoomStaysIndependentFromOneToOneHostGeometry() {
        let rendering = WebRenderingProfile.canonicalDefault.settingZoom(1.25)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let container = host(webView, visibleSize: NSSize(width: 600, height: 820))
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(webView.frame, NSRect(x: 0, y: 0, width: 600, height: 820))
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(webView.magnification, 1, accuracy: 0.001)
    }''',
        "MC-B4.0 zoom geometry test",
    )
    text = replace_once_regex(
        text,
        r"^    func testNavigationObserverRestoresWebsiteModeWithoutDiscardingUserZoom\(\) \{",
        "    func testNavigationObserverRestoresWebsiteModeWithoutDiscardingUserZoom() {",
        label="MC-B4.0 navigation test anchor",
    )
    for stale in ["600.0 / 1024.0", "1080.0 / 1440.0", "webView.frame.width, 1024", "webView.frame.width, 720"]:
        require_absent(text, stale, label=f"MC-B4.0 stale geometry test {stale}")
    write_source(path, text)


def patch_geometry_regression_tests() -> None:
    path = ROOT / "FloatTabsTests/WebsiteLayoutGeometryRegressionTests.swift"
    text = read_source(path)
    text = replace_test_method(
        text,
        "testLogicalViewportAlwaysProducesIntegralLogicalFrames",
        "testRepeatedLayoutPassesLeaveTransientHostGeometryUntouched",
        '''    func testLogicalViewportIsAlwaysVisibleOneToOne() {
        let visibleSizes = presetVisibleSizes() + [
            CGSize(width: 521.3, height: 733.7),
            CGSize(width: 720, height: 900),
            CGSize(width: 960.5, height: 780.25),
        ]
        for visibleSize in visibleSizes {
            for mode in WebsiteMode.allCases {
                XCTAssertEqual(
                    WebsiteLayoutViewport.logicalSize(forVisibleSize: visibleSize, websiteMode: mode),
                    visibleSize
                )
                XCTAssertEqual(
                    WebsiteLayoutViewport.fittingScale(forVisibleWidth: visibleSize.width, websiteMode: mode),
                    1,
                    accuracy: 0.001
                )
            }
        }
    }''',
        "MC-B4.0 regression viewport test",
    )
    text = replace_test_method(
        text,
        "testRepeatedLayoutPassesLeaveTransientHostGeometryUntouched",
        "testRepeatedLayoutPassesLeaveHotHostGeometryUntouched",
        '''    func testRepeatedLayoutPassesLeaveTransientHostGeometryUntouched() {
        _ = NSApplication.shared
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = WebPanelContainerView(frame: NSRect(origin: .zero, size: mediumVisible))
        container.show(webView: webView)
        let window = borderlessWindow(content: container)
        container.layoutSubtreeIfNeeded()
        let expected = NSRect(origin: .zero, size: mediumVisible)

        for _ in 0..<3 {
            container.layoutSubtreeIfNeeded()
            webView.layoutSubtreeIfNeeded()
        }

        XCTAssertEqual(webView.frame, expected)
        XCTAssertEqual(webView.bounds, expected)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
        window.orderOut(nil)
    }''',
        "MC-B4.0 transient regression test",
    )
    text = replace_test_method(
        text,
        "testRepeatedLayoutPassesLeaveHotHostGeometryUntouched",
        "testResizeRoundtripIsDeterministic",
        '''    func testRepeatedLayoutPassesLeaveHotHostGeometryUntouched() {
        _ = NSApplication.shared
        let container = WebPanelContainerView(frame: NSRect(origin: .zero, size: mediumVisible))
        let window = borderlessWindow(content: container)
        let slotID = UUID()
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        container.show(webView: webView, slotID: slotID, residencyPolicy: .hot)
        container.layoutSubtreeIfNeeded()
        let expected = NSRect(origin: .zero, size: mediumVisible)

        for _ in 0..<3 { container.layoutSubtreeIfNeeded() }

        XCTAssertEqual(webView.frame, expected)
        XCTAssertEqual(webView.bounds, expected)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
        window.orderOut(nil)
    }''',
        "MC-B4.0 hot regression test",
    )
    text = replace_test_method(
        text,
        "testResizeRoundtripIsDeterministic",
        "testDynamicCJKContentKeepsHostingGeometryAndInjectionStable",
        '''    func testResizeRoundtripIsDeterministic() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: mediumVisible)
        let initialFrame = webView.frame

        container.setFrameSize(largeVisible)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(webView.frame, NSRect(origin: .zero, size: largeVisible))

        container.setFrameSize(mediumVisible)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(webView.frame, initialFrame)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
    }''',
        "MC-B4.0 resize regression test",
    )
    text = replace_test_method(
        text,
        "testDynamicCJKContentKeepsHostingGeometryAndInjectionStable",
        "testHiddenScrollerConfigurationIsIdempotent",
        '''    func testDynamicCJKContentKeepsHostingGeometryAndInjectionStable() {
        _ = NSApplication.shared
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = WebPanelContainerView(frame: NSRect(origin: .zero, size: mediumVisible))
        container.show(webView: webView)
        let window = borderlessWindow(content: container)
        container.layoutSubtreeIfNeeded()
        let expected = NSRect(origin: .zero, size: mediumVisible)

        loadDynamicCJKFixture(in: webView)
        waitForTicks(1.5)

        XCTAssertEqual(webView.frame, expected)
        XCTAssertEqual(webView.bounds, expected)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(evaluateNumber("window.innerWidth", in: webView), 600, accuracy: 1.5)
        XCTAssertEqual(
            evaluateNumber("document.querySelectorAll('#floattabs-hidden-scrollbar-style').length", in: webView),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(evaluateNumber("document.querySelectorAll('#status').length", in: webView), 1, accuracy: 0.001)
        window.orderOut(nil)
    }''',
        "MC-B4.0 dynamic regression test",
    )
    text = replace_span_once(
        text,
        r"^    func testOneToOneViewportDebugOverrideHostsAtNativeScale\(\) \{",
        r"^    // MARK: - Fixture",
        '''    func testOneToOneViewportDebugOverrideHostsAtNativeScale() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: mediumVisible)
        XCTAssertEqual(webView.frame, NSRect(origin: .zero, size: mediumVisible))
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
    }
    #endif

''',
        label="MC-B4.0 debug regression test",
    )
    for stale in ["1024", "1280", "600.0 / 1024.0", "mediumVisible.width / logicalSize.width"]:
        # The fixture itself has unrelated numeric values; only fail on old
        # geometry assertions that survived the method replacements.
        if stale in text and stale in {"600.0 / 1024.0", "mediumVisible.width / logicalSize.width"}:
            require_absent(text, stale, label=f"MC-B4.0 stale regression geometry {stale}")
    write_source(path, text)


def patch_ui_test() -> None:
    path = ROOT / "FloatTabsTests/WebViewPoolTests.swift"
    text = read_source(path)
    text = replace_exact_once(
        text,
        "        XCTAssertTrue(MontereyCompatibilityUI.websiteModeEnabled)\n",
        "        XCTAssertFalse(MontereyCompatibilityUI.websiteModeEnabled)\n"
        "        XCTAssertEqual(MontereyCompatibilityUI.websiteModeDisplayName, \"Native · Monterey Compatibility\")\n",
        label="MC-B4.0 UI honesty test",
    )
    write_source(path, text)


def patch_pool_geometry_test() -> None:
    path = ROOT / "FloatTabsTests/WebViewPoolTests.swift"
    text = read_source(path)
    text = replace_test_method(
        text,
        "testMontereyExplicitWebsiteModeSwitchRetainsResidentWebView",
        "testPooledWebViewsUsePersistentWebsiteDataStore",
        '''    func testMontereyExplicitWebsiteModeSwitchRetainsResidentWebView() {
        var loadedRequests: [URLRequest] = []
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) }
        )
        var profile = makeProfile(name: "LayoutSwitch")
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 820)
        )
        let expected = NSRect(x: 0, y: 0, width: 600, height: 820)

        let desktop = pool.webView(for: profile)
        container.show(webView: desktop, slotID: profile.id, residencyPolicy: .warm, websiteMode: .desktop)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(desktop.frame, expected)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)

        profile.renderingProfile = profile.renderingProfile.settingWebsiteMode(.mobile)
        let mobile = pool.webView(for: profile)
        XCTAssertTrue(desktop === mobile)
        container.show(webView: mobile, slotID: profile.id, residencyPolicy: .warm, websiteMode: .mobile)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(mobile.frame, expected)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)

        profile.renderingProfile = profile.renderingProfile.settingWebsiteMode(.desktop)
        let restored = pool.webView(for: profile)
        XCTAssertTrue(mobile === restored)
        container.show(webView: restored, slotID: profile.id, residencyPolicy: .warm, websiteMode: .desktop)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(restored.frame, expected)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(loadedRequests.count, 1)
    }''',
        "MC-B4.0 pool Website Mode geometry test",
    )
    write_source(path, text)


def patch_app_preferences_geometry_test() -> None:
    path = ROOT / "FloatTabsTests/AppPreferencesStoreTests.swift"
    text = read_source(path)
    text = replace_test_method(
        text,
        "testFloatingWindowSizingUsesVisibleViewportInsteadOfDesktopLogicalFrame",
        "testFloatingWindowSizingFallsBackToStandaloneWebViewFrame",
        '''    func testFloatingWindowSizingUsesVisibleViewportInsteadOfDesktopLogicalFrame() {
        _ = NSApplication.shared
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 820)
        )
        let window = NSWindow(
            contentRect: container.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = container

        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        container.show(webView: webView)
        container.layoutSubtreeIfNeeded()
        webView.layoutSubtreeIfNeeded()

        XCTAssertEqual(webView.frame, NSRect(x: 0, y: 0, width: 600, height: 820))
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)

        let visibleSize = PopupCoordinator.visibleSourceSize(for: webView)
        XCTAssertEqual(visibleSize.width, 600, accuracy: 0.001)
        XCTAssertEqual(visibleSize.height, 820, accuracy: 0.001)
        window.orderOut(nil)
    }''',
        "MC-B4.0 AppPreferences visible geometry test",
    )
    write_source(path, text)


GEOMETRY_TESTS = r'''

@MainActor
final class MontereyOneToOneGeometryTests: XCTestCase {
    func testWarmColdAndHotHostsUseVisibleOneToOneGeometry() {
        _ = NSApplication.shared
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 600, height: 820))
        let window = NSWindow(contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = container
        let profiles: [(SlotResidencyPolicy, UUID)] = [(.warm, UUID()), (.cold, UUID()), (.hot, UUID())]
        for (policy, slotID) in profiles {
            let webView = WebViewFactory.makeWebView()
            container.show(webView: webView, slotID: slotID, residencyPolicy: policy)
            container.layoutSubtreeIfNeeded()
            let expected = NSRect(x: 0, y: 0, width: 600, height: 820)
            XCTAssertEqual(webView.frame, expected, "\(policy)")
            XCTAssertEqual(webView.bounds, expected, "\(policy)")
            XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
        }
        window.orderOut(nil)
    }

    func testPointConversionIsIdentityThroughProductionHostHierarchy() {
        let webView = WebViewFactory.makeWebView()
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 600, height: 820))
        container.show(webView: webView)
        let source = NSPoint(x: 300, y: 410)
        let converted = webView.convert(source, from: container)
        XCTAssertEqual(converted.x, source.x, accuracy: 0.001)
        XCTAssertEqual(converted.y, source.y, accuracy: 0.001)
    }

    func testResetCreatedWebViewReturnsToOneToOneGeometry() {
        let webView = WebViewFactory.makeWebView()
        let container = WebPanelContainerView(frame: NSRect(x: 0, y: 0, width: 420, height: 760))
        container.show(webView: webView)
        container.layoutSubtreeIfNeeded()
        XCTAssertEqual(webView.frame, NSRect(x: 0, y: 0, width: 420, height: 760))
        XCTAssertEqual(webView.bounds, webView.frame)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
    }

    func testWebsiteModeMetadataDoesNotRebuildOrChangeGeometry() {
        let desktop = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault.settingWebsiteMode(.desktop))
        let mobile = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault.settingWebsiteMode(.mobile))
        let desktopContainer = WebSlotHostView(webView: desktop)
        let mobileContainer = WebSlotHostView(webView: mobile)
        desktopContainer.frame = NSRect(x: 0, y: 0, width: 600, height: 820)
        mobileContainer.frame = desktopContainer.frame
        desktopContainer.layoutSubtreeIfNeeded()
        mobileContainer.layoutSubtreeIfNeeded()
        XCTAssertEqual(desktop.frame, mobile.frame)
        XCTAssertEqual(desktop.frame, NSRect(x: 0, y: 0, width: 600, height: 820))
        XCTAssertFalse(desktop === mobile)
        XCTAssertEqual(desktopContainer.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(mobileContainer.websiteLayoutScale, 1, accuracy: 0.001)
    }

    func testWebsiteModeUIIsDisabledAndHonest() {
        XCTAssertFalse(MontereyCompatibilityUI.websiteModeEnabled)
        XCTAssertEqual(MontereyCompatibilityUI.websiteModeDisplayName, "Native · Monterey Compatibility")
    }
}
'''


def patch_tests() -> None:
    patch_factory_tests()
    patch_geometry_regression_tests()
    patch_ui_test()
    patch_pool_geometry_test()
    patch_app_preferences_geometry_test()
    path = ROOT / "FloatTabsTests/WebViewFactoryTests.swift"
    text = read_source(path)
    text = text + GEOMETRY_TESTS
    write_source(path, text)


def verify_contract() -> None:
    factory = read_source(ROOT / "FloatTabs/Web/WebViewFactory.swift")
    container = read_source(ROOT / "FloatTabs/Web/WebViewContainer.swift")
    ui = read_source(ROOT / "FloatTabs/UI/WebAppEditorController.swift")
    tests = read_source(ROOT / "FloatTabsTests/WebViewFactoryTests.swift")
    pool_tests = read_source(ROOT / "FloatTabsTests/WebViewPoolTests.swift")
    app_preferences_tests = read_source(ROOT / "FloatTabsTests/AppPreferencesStoreTests.swift")

    for required in [
        "return visibleWidth",
        "return visibleSize",
        "return 1",
        "final class FloatTabsWebView",
    ]:
        require_present(factory, required, label="MC-B4.0 viewport contract")
    for forbidden in [
        "compactCSSWidth", "balancedCSSWidth", "standardCSSWidth", "expandedCSSWidth",
        "preferredContentMode", "FloatTabsWebView(frame:", "webView.pageZoom = rendering.zoom",
    ]:
        require_absent(factory, forbidden, label=f"MC-B4.0 forbidden factory geometry/runtime {forbidden}")
    for forbidden in [
        "WebsiteLayoutViewport.logicalSize", "preferredContentMode", "pageZoom", "magnification",
        "setFrameSize", "setBoundsSize", "transform =",
    ]:
        require_absent(container, forbidden, label=f"MC-B4.0 forbidden container workaround {forbidden}")
    for required in [
        "if webView.frame != visibleFrame",
        "if webView.bounds != visibleFrame",
        "websiteLayoutScale = 1",
    ]:
        require_present(container, required, label="MC-B4.0 host geometry contract")
    require_present(ui, "static let websiteModeEnabled = false", label="MC-B4.0 disabled UI")
    require_present(ui, "Native · Monterey Compatibility", label="MC-B4.0 honest UI label")
    require_present(tests, "final class MontereyOneToOneGeometryTests", label="MC-B4.0 tests")
    require_present(pool_tests, "XCTAssertFalse(MontereyCompatibilityUI.websiteModeEnabled)", label="MC-B4.0 UI test")
    require_absent(tests, "600.0 / 1024.0", label="MC-B4.0 stale scale assertion")
    require_absent(tests, "1080.0 / 1440.0", label="MC-B4.0 stale scale assertion")
    require_absent(pool_tests, "600.0 / 1024.0", label="MC-B4.0 stale pool scale assertion")
    require_absent(app_preferences_tests, "webView.frame.width, 1024", label="MC-B4.0 stale AppPreferences geometry assertion")


def main() -> None:
    patch_runtime()
    patch_ui()
    patch_tests()
    verify_contract()
    print("Applied MC-B4.0 one-to-one Monterey WebView geometry transform.")


if __name__ == "__main__":
    main()
