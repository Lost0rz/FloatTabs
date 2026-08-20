#!/usr/bin/env python3
"""Stage 6: isolated Monterey Compatibility Edition runtime semantics.

Collapses every dual-path (macOS 13+ / Monterey) branch left by stages 1-5 to
the Monterey-only behavior, reduces final WebView construction to a stock
WKWebView (no FloatTabsWebView rendering layer, no setRendering during
construction), adapts the test suite to the compatibility contract, and runs
the final static isolation checks.
"""

import re
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from monterey_transform_lib import (
    read_source,
    replace_once_regex,
    replace_span_once,
    require_absent,
    require_present,
    span_of,
    write_source,
)

ROOT = Path(__file__).resolve().parents[2]

DOTALL = re.MULTILINE | re.DOTALL

PROBE_MODE = os.environ.get("FLOATTABS_MONTEREY_PROBE_MODE", "").strip().lower()
PROBE_MODES = {"", "shell", "construct", "attach", "blank", "https"}
if PROBE_MODE not in PROBE_MODES:
    raise SystemExit(
        "error: FLOATTABS_MONTEREY_PROBE_MODE must be one of: "
        "shell, construct, attach, blank, https"
    )

PROBE_MODE_SWIFT = "nil" if not PROBE_MODE else f".{PROBE_MODE}"


def probe_mode_declaration() -> str:
    return f'''enum MontereyProbeMode: String {{
    case shell
    case construct
    case attach
    case blank
    case https

    // This value is generated into the compatibility build. The absent value
    // is the unmodified Candidate B runtime path.
    static let configured: MontereyProbeMode? = {PROBE_MODE_SWIFT}

    var createsWebView: Bool {{
        self != .shell
    }}

    var attachesWebView: Bool {{
        switch self {{
        case .shell, .construct:
            return false
        case .attach, .blank, .https:
            return true
        }}
    }}

    var loadsAboutBlank: Bool {{
        self == .blank
    }}

    var loadsProfileURL: Bool {{
        self == .https
    }}
}}

'''

# ---------------------------------------------------------------------------
# FloatingPanel: Monterey never adopts the macOS-13-only collection behavior.
# ---------------------------------------------------------------------------
floating = ROOT / "FloatTabs/Panel/FloatingPanel.swift"
text = read_source(floating)
text = replace_span_once(
    text,
    r"^    private static var ordinaryCollectionBehavior: NSWindow\.CollectionBehavior \{",
    r"^    private static let fullscreenCompanionCollectionBehavior",
    """    // Monterey Compatibility Edition intentionally keeps a Monterey-only
    // collection behavior. Standard macOS 13+ behavior lives in the standard
    // release and is not carried inside this compatibility package.
    private static let ordinaryCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .ignoresCycle,
    ]

""",
    label="FloatingPanel Monterey-only collection behavior",
)
write_source(floating, text)

# ---------------------------------------------------------------------------
# FullscreenSourceHost: no modern observer, no polling loop. Preserve the
# ordinary source-window geometry/presentation helpers because normal browser
# hosting needs them even with element fullscreen disabled.
# ---------------------------------------------------------------------------
fullscreen = ROOT / "FloatTabs/Panel/FullscreenSourceHost.swift"
text = read_source(fullscreen)

text = replace_once_regex(
    text,
    r"        if #available\(macOS 13\.0, \*\) \{\s*"
    r"observeModernFullscreenState\(of: webView\)\s*"
    r"\} else \{.*?"
    r"legacyFullscreenPollGeneration &\+= 1\s*"
    r"\}",
    """        // Monterey Compatibility Edition: fullscreen observation is disabled.
        // The standard release owns the modern fullscreen implementation.
        legacyFullscreenPollGeneration &+= 1""",
    label="FullscreenSourceHost disabled observation stub",
    flags=DOTALL,
)

# Remove only the modern FullscreenState adapter; the state enum itself stays
# because handleFullscreenStateChange is ordinary source-host infrastructure.
text = replace_span_once(
    text,
    r"^@available\(macOS 13\.0, \*\)\nprivate extension FullscreenWebKitState",
    r"^enum FullscreenSourceSessionState",
    "",
    label="FullscreenSourceHost modern state adapter removal",
)

# Remove the modern observer and the synthetic polling helpers. Do not slice
# through sourceFrame/makeSourceWindow/presentation detection.
text = replace_span_once(
    text,
    r"^    @available\(macOS 13\.0, \*\)\n    private func observeModernFullscreenState",
    r"^    private func startLegacyFullscreenPolling",
    "",
    label="FullscreenSourceHost modern observer removal",
)
text = replace_span_once(
    text,
    r"^    private func startLegacyFullscreenPolling",
    r"^    static func sourceFrame\(",
    "",
    label="FullscreenSourceHost legacy polling removal",
)
write_source(fullscreen, text)

# ---------------------------------------------------------------------------
# WebViewFactory: Monterey-only implementation with a fully stock public
# WebKit construction path.
# ---------------------------------------------------------------------------
web_factory = ROOT / "FloatTabs/Web/WebViewFactory.swift"
text = read_source(web_factory)

compat_make = """    static func makeWebView(
        renderingProfile: WebRenderingProfile = .canonicalDefault
    ) -> WKWebView {
        // Monterey Compatibility Edition: fully stock public WebKit path. The
        // standard release separately owns UA overrides, content-mode
        // selection, injected scrollbar policy, element-fullscreen behavior,
        // and the custom rendering layer.
        NSLog("[FloatTabs Monterey] WebViewFactory.makeWebView begin")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        NSLog("[FloatTabs Monterey] WebViewFactory.makeWebView ready")
        return webView
    }

"""
text = replace_span_once(
    text,
    r"^    static func makeWebView\(",
    r"^    static func makeStageZeroWebView\(",
    compat_make,
    label="WebViewFactory stock WKWebView construction",
)

text = replace_span_once(
    text,
    r"^    static func applyRuntimeRendering\(\n        _ renderingProfile: WebRenderingProfile,\n        to webView: WKWebView\n    \) \{",
    r"^    /// AppKit scrollers stay visually disabled",
    """    static func applyRuntimeRendering(
        _ renderingProfile: WebRenderingProfile,
        to webView: WKWebView
    ) {
        // Monterey Compatibility Edition intentionally leaves stock WKWebView
        // rendering untouched. Persisted rendering metadata remains available
        // to the profile/editor, but it has no runtime WebKit effect here.
        _ = renderingProfile
        _ = webView
    }

    static func applyRuntimeRendering(
        _ renderingProfile: WebRenderingProfile,
        to webView: WKWebView,
        versions: BrowserVersionCatalog
    ) {
        // Keep the overload for source compatibility; Monterey does not apply
        // UA, Website Mode, zoom, content mode, or scroll-hierarchy changes.
        _ = renderingProfile
        _ = webView
        _ = versions
    }

""",
    label="WebViewFactory Monterey-only runtime rendering",
)
write_source(web_factory, text)

# Monterey keeps persisted rendering metadata but none of those settings have
# a runtime WebKit effect. Make the compatibility-only rebuild decision a no-op
# so warm slots are never destructively recreated for inert profile changes.
profile = ROOT / "FloatTabs/Tabs/WebRenderingProfile.swift"
text = read_source(profile)
text = replace_span_once(
    text,
    r"^    func requiresWebViewRebuild\(comparedTo previous: WebRenderingProfile\) -> Bool \{",
    r"^    private enum CodingKeys:",
    """    func requiresWebViewRebuild(comparedTo previous: WebRenderingProfile) -> Bool {
        // Monterey Compatibility Edition has no runtime rendering mutation;
        // profile metadata changes therefore never require WKWebView rebuild.
        _ = previous
        return false
    }

""",
    label="WebRenderingProfile Monterey no-op rebuild decision",
)
write_source(profile, text)
text = read_source(web_factory)

# ---------------------------------------------------------------------------
# PopupCoordinator: retain native delegate functionality, but keep the
# primary Monterey WebView free of JavaScript and script-message injection.
# Floating child windows retain their optional link/window behavior.
# ---------------------------------------------------------------------------
popup = ROOT / "FloatTabs/Web/PopupCoordinator.swift"
text = read_source(popup)
text = replace_span_once(
    text,
    r"^    init\(\n        parentWebView: WKWebView,\n        openExternal: @escaping ExternalOpenHandler = \{ url in\n            _ = NSWorkspace\.shared\.open\(url\)\n        \},\n        uploadCoordinator: UploadCoordinator\? = nil,\n        downloadCoordinator: DownloadCoordinator\? = nil\n    \) \{",
    r"^    static func disposition\(",
    """    init(
        parentWebView: WKWebView,
        openExternal: @escaping ExternalOpenHandler = { url in
            _ = NSWorkspace.shared.open(url)
        },
        uploadCoordinator: UploadCoordinator? = nil,
        downloadCoordinator: DownloadCoordinator? = nil
    ) {
        self.parentWebView = parentWebView
        self.openExternal = openExternal
        self.uploadCoordinator = uploadCoordinator ?? UploadCoordinator()
        self.downloadCoordinator = downloadCoordinator ?? DownloadCoordinator()
        super.init()

        // Monterey Compatibility Edition: the primary pool-created WebView
        // remains genuinely stock. Keep this coordinator as the native
        // WKUIDelegate/WKNavigationDelegate surface, but do not install
        // JavaScript, user scripts, or script-message handlers here.
    }

""",
    label="PopupCoordinator primary WebView no-injection initialization",
)
write_source(popup, text)
text = read_source(web_factory)

text = replace_once_regex(
    text,
    r"    static func configureHiddenScrollers\(in webView: WKWebView\) \{\s*"
    r"guard #available\(macOS 13\.0, \*\) else \{ return \}\s*"
    r"for scrollView in descendantScrollViews\(in: webView\) \{\s*"
    r"guard needsHiddenScrollerConfiguration\(scrollView\) else \{ continue \}\s*"
    r"configureHiddenScrollerStyle\(scrollView\)\s*"
    r"\}\s*"
    r"\}",
    """    static func configureHiddenScrollers(in webView: WKWebView) {
        // Monterey Compatibility Edition intentionally leaves WebKit's internal
        // AppKit scroll hierarchy untouched.
    }""",
    label="WebViewFactory no-op hidden scrollers",
)
write_source(web_factory, text)

# ---------------------------------------------------------------------------
# PanelController restore / typed-address persistence: compatibility semantics
# are used unconditionally inside this edition.
# ---------------------------------------------------------------------------
panel = ROOT / "FloatTabs/Panel/PanelController.swift"
text = read_source(panel)
text = replace_once_regex(
    text,
    r"^struct FullscreenVisibilityIntent",
    probe_mode_declaration() + "struct FullscreenVisibilityIntent",
    label="Monterey probe mode declaration",
)
text = replace_once_regex(
    text,
    r"        if #available\(macOS 13\.0, \*\) \{\s*"
    r"synchronizeSlotState\(\)\s*"
    r"\} else \{.*?"
    r"PanelController initialized without WebView restore\"\)\s*"
    r"\}",
    """        // Monterey Compatibility Edition defers saved WebView restoration until
        // explicit presentation; the standard release keeps its own eager path.
        NSLog("[FloatTabs Monterey] PanelController initialized without WebView restore")""",
    label="PanelController Monterey-only lazy restore",
    flags=DOTALL,
)
text = replace_once_regex(
    text,
    r"        if #available\(macOS 13\.0, \*\) \{\s*"
    r"tabStore\.updateCurrentURL\(id: id, url: normalized\.url\)\s*"
    r"\} else \{\s*"
    r"NSLog\(\"\[FloatTabs Monterey\] address commit begin slot=%@\", id\.uuidString\)\s*"
    r"\}\s*"
    r"webViewPool\.navigate\(\s*"
    r"slotID: id,\s*"
    r"to: normalized\.url,\s*"
    r"allowHTTPEntryFallback: normalized\.schemeWasInferred\s*"
    r"\)\s*"
    r"if #available\(macOS 13\.0, \*\) \{.*?"
    r"address navigation submitted slot=%@\", id\.uuidString\)\s*"
    r"\}",
    """        NSLog("[FloatTabs Monterey] address commit begin slot=%@", id.uuidString)
        webViewPool.navigate(
            slotID: id,
            to: normalized.url,
            allowHTTPEntryFallback: normalized.schemeWasInferred
        )
        NSLog("[FloatTabs Monterey] address navigation submitted slot=%@", id.uuidString)""",
    label="PanelController Monterey-only typed address",
    flags=DOTALL,
)
write_source(panel, text)

# ---------------------------------------------------------------------------
# Candidate C first-presentation probes: generated only when explicitly
# requested. The normal Candidate B path remains byte-for-byte untouched by
# this section when FLOATTABS_MONTEREY_PROBE_MODE is absent.
# ---------------------------------------------------------------------------
if PROBE_MODE:
    text = replace_once_regex(
        text,
        r"    private var needsFocusAfterApplicationActivation = false\n",
        """    private var needsFocusAfterApplicationActivation = false
    private var montereyProbeWebView: WKWebView?

""",
        label="Monterey probe strong WebView retention property",
    )

    probe_load = ""
    if PROBE_MODE == "blank":
        probe_load = """
        webView.load(URLRequest(url: URL(string: \"about:blank\")!))
"""
    elif PROBE_MODE == "https":
        probe_load = """
        if let profile = tabStore.activeProfile {
            let destination = profile.currentURL ?? profile.homeURL
            webView.load(URLRequest(url: destination))
        }
"""

    probe_webkit_action = ""
    if PROBE_MODE == "shell":
        probe_webkit_action = """    // C0: the shell is the complete first-presentation boundary.
"""
    else:
        probe_webkit_action = f'''    private func performMontereyProbe() {{
        guard montereyProbeWebView == nil else {{ return }}
        let webView = WebViewFactory.makeWebView()
        montereyProbeWebView = webView
'''
        if PROBE_MODE in {"attach", "blank", "https"}:
            probe_webkit_action += """        rootView.webPanelContainerView.show(webView: webView)
        sourceHostController.window.orderFrontRegardless()
"""
        probe_webkit_action += probe_load
        probe_webkit_action += "    }\n\n"

    probe_deferred_action = ""
    if PROBE_MODE != "shell":
        probe_deferred_action = """        // C1-C4: let the shell presentation reach WindowServer first.
        DispatchQueue.main.async { [weak self] in
            self?.performMontereyProbe()
        }
"""

    probe_show = f'''    func showFloatTabs() {{
        let presentationUptime = ProcessInfo.processInfo.systemUptime
        lastPresentationUptime = presentationUptime
        workspaceAutoHideSuppression.arm(atUptime: presentationUptime)
        requestedVisibility = true
        synchronizeAppearance()

        capturePreviousApplication()
        positionPanelForCurrentScreens()
        synchronizeFixedViewportAfterPositioning()
        synchronizeSourceHostFrame(display: false)
        needsFocusAfterApplicationActivation = !NSApp.isActive

        // Candidate C deliberately presents only the shell before any WebKit
        // construction, attachment, or navigation boundary under test.
        panel.orderFrontRegardless()
        activateFloatTabs()
        panel.makeKeyAndOrderFront(nil)
        if NSApp.isActive {{
            needsFocusAfterApplicationActivation = false
        }}
{probe_deferred_action}    }}

{probe_webkit_action}'''
    text = replace_span_once(
        text,
        r"^    func showFloatTabs\(\) \{",
        r"^    func hideFloatTabs\(\) \{",
        probe_show,
        label="Monterey Candidate C first-presentation probe",
    )
    text = replace_once_regex(
        text,
        r"    private func synchronizeSlotState\(\) \{\n",
        """    private func synchronizeSlotState() {
        guard MontereyProbeMode.configured == nil else { return }
""",
        label="Monterey probe lifecycle bypass",
    )
    write_source(panel, text)

# ---------------------------------------------------------------------------
# SlotNavigationObserver: committed-URL persistence only.
# ---------------------------------------------------------------------------
observer = ROOT / "FloatTabs/Web/SlotNavigationObserver.swift"
text = read_source(observer)
text = replace_span_once(
    text,
    r"^        if #available\(macOS 13\.0, \*\) \{\s*observation = webView\.observe\(",
    r"\n\n        webView\.navigationDelegate = self",
    """        // Monterey Compatibility Edition persists only committed URLs.
        NSLog("[FloatTabs Monterey] navigation observer ready slot=%@", slotID.uuidString)""",
    label="SlotNavigationObserver committed-only observation",
)
text = replace_once_regex(
    text,
    r"        if #available\(macOS 13\.0, \*\) \{\s*"
    r"// URL KVO preserves the accepted modern persistence behavior\.\s*"
    r"\} else if let url = webView\.url, WebAppURL\.isSafe\(url\) \{",
    """        if let url = webView.url, WebAppURL.isSafe(url) {""",
    label="SlotNavigationObserver Monterey-only committed persistence",
)
write_source(observer, text)

# ---------------------------------------------------------------------------
# Test contract: the standard suite asserts standard-edition behaviors that
# the compatibility edition intentionally strips. Adapt those expectations to
# the Monterey contract so CI verifies the compatibility behavior itself.
# ---------------------------------------------------------------------------
tests = ROOT / "FloatTabsTests/WebViewFactoryTests.swift"
text = read_source(tests)

text = replace_once_regex(
    text,
    r"        if #available\(macOS 12\.3, \*\) \{\s*"
    r"XCTAssertTrue\(webView\.configuration\.preferences\.isElementFullscreenEnabled\)\s*"
    r"\}",
    """        if #available(macOS 12.3, *) {
            // Monterey Compatibility Edition: element fullscreen is never
            // enabled by this package, so the preference stays off.
            XCTAssertFalse(webView.configuration.preferences.isElementFullscreenEnabled)
        }""",
    label="WebViewFactoryTests stage-zero fullscreen contract",
)

text = replace_span_once(
    text,
    r"^    func testAutomaticMobileUsesCurrentIPhoneSafariIdentity\(\) \{",
    r"^    func testWebsiteLayoutViewportMapsVisibleWidthsToDistinctDesktopExperiences\(",
    """    func testAutomaticMobileUsesCurrentIPhoneSafariIdentity() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingZoom(1.25)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)

        // Monterey Compatibility Edition: stock WKWebView baseline. Construction
        // applies no UA identity, no content-mode preference, and no rendering
        // layer; WebKit owns its native user agent and default zoom.
        XCTAssertTrue(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertFalse(webView is FloatTabsWebView)
        XCTAssertTrue((webView.customUserAgent ?? "").isEmpty)
        XCTAssertTrue((webView.configuration.applicationNameForUserAgent ?? "").isEmpty)

        loadTestHTML(in: webView)
        let hasMobileRuntimeIdentity = evaluateNumber(
            "navigator.userAgent.includes('iPhone') ? 1 : 0",
            in: webView
        )
        XCTAssertEqual(hasMobileRuntimeIdentity, 0, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
    }

""",
    label="WebViewFactoryTests mobile identity contract",
)

text = replace_span_once(
    text,
    r"^    func testMediumDesktopHostUsesBalancedLogicalLayoutWithoutPageZoomFit\(\) \{",
    r"^    func testVisibleResizeMovesBetweenDesktopExperienceClassesWithoutPageZoomFit\(",
    """    func testMediumDesktopHostUsesBalancedLogicalLayoutWithoutPageZoomFit() {
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        let container = host(webView, visibleSize: NSSize(width: 600, height: 820))

        // Monterey Compatibility Edition: desktop hosting stays on the stock
        // WKWebView; there is no FloatTabsWebView layout-scale participant.
        XCTAssertEqual(container.bounds.size, NSSize(width: 600, height: 820))
        XCTAssertEqual(webView.frame.width, 1024, accuracy: 0.001)
        XCTAssertEqual(webView.frame.height, 1400, accuracy: 0.001)
        XCTAssertEqual(webView.bounds.size, webView.frame.size)
        XCTAssertEqual(container.websiteLayoutScale, 600.0 / 1024.0, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(webView.magnification, 1, accuracy: 0.001)
    }

""",
    label="WebViewFactoryTests medium desktop host contract",
)

text = replace_span_once(
    text,
    r"^    func testMobileModeRemainsNativeOneToOneAtWideWindowSize\(\) \{",
    r"^    func testDesktopHostMapsVisibleCenterIntoLogicalWebCoordinates\(",
    """    func testMobileModeFallsBackToDesktopClassHostingOnStockWebView() {
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let container = host(webView, visibleSize: NSSize(width: 1080, height: 850))
        loadTestHTML(in: webView)

        // Monterey Compatibility Edition: the stock WKWebView carries no
        // Website Mode, so hosting conservatively maps the visible surface to
        // the standard desktop experience class instead of native 1:1.
        let cssWidth = evaluateNumber("document.body.clientWidth", in: webView)
        XCTAssertEqual(container.bounds.width, 1080, accuracy: 0.001)
        XCTAssertEqual(webView.frame.width, 1440, accuracy: 0.001)
        XCTAssertEqual(container.websiteLayoutScale, 1080.0 / 1440.0, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(cssWidth, 1440, accuracy: 3)
    }

""",
    label="WebViewFactoryTests mobile host fallback contract",
)

text = replace_span_once(
    text,
    r"^    func testUserZoomStaysIndependentFromDesktopHostLayoutFit\(\) \{",
    r"^    func testNavigationObserverRestoresWebsiteModeWithoutDiscardingUserZoom\(",
    """    func testUserZoomStaysIndependentFromDesktopHostLayoutFit() {
        // Monterey Compatibility Edition: construction and warm reuse never
        // apply persisted rendering metadata to the stock WKWebView.
        let desktopRendering = WebRenderingProfile.canonicalDefault.settingZoom(1.25)
        let desktopWebView = WebViewFactory.makeWebView(renderingProfile: desktopRendering)
        let desktopContainer = host(desktopWebView, visibleSize: NSSize(width: 600, height: 820))

        XCTAssertEqual(desktopContainer.websiteLayoutScale, 600.0 / 1024.0, accuracy: 0.001)
        XCTAssertEqual(desktopWebView.frame.width, 1024, accuracy: 0.001)
        XCTAssertEqual(desktopWebView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(desktopWebView.magnification, 1, accuracy: 0.001)

        let mobileRendering = desktopRendering
            .settingWebsiteMode(.mobile)
            .settingSimplePreset(.wide)
        let mobileWebView = WebViewFactory.makeWebView(renderingProfile: mobileRendering)
        let mobileContainer = host(mobileWebView, visibleSize: NSSize(width: 1080, height: 850))

        // Stock WKWebView hosting conservatively uses the desktop experience
        // class; zoom stays neutral at construction in both modes.
        XCTAssertEqual(mobileContainer.websiteLayoutScale, 1080.0 / 1440.0, accuracy: 0.001)
        XCTAssertEqual(mobileWebView.frame.width, 1440, accuracy: 0.001)
        XCTAssertEqual(mobileWebView.pageZoom, 1, accuracy: 0.001)
        XCTAssertEqual(mobileWebView.magnification, 1, accuracy: 0.001)
    }

""",
    label="WebViewFactoryTests zoom neutrality contract",
)

text = replace_span_once(
    text,
    r"^    func testNavigationObserverRestoresWebsiteModeWithoutDiscardingUserZoom\(\) \{",
    r"^    func testMacOSSafariRuntimeUsesNativeWebKitUAWithSafariSuffix\(",
    """    func testNavigationObserverRestoresWebsiteModeWithoutDiscardingUserZoom() {
        // Monterey Compatibility Edition: navigation finish must not mutate the
        // stock WKWebView; there is no rendering layer to restore.
        let rendering = WebRenderingProfile.canonicalDefault
            .settingWebsiteMode(.mobile)
            .settingZoom(1.25)
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        _ = host(webView, visibleSize: NSSize(width: 900, height: 850))

        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .mobile,
            onURLChange: { _, _ in }
        )
        observer.webView(webView, didFinish: nil)

        XCTAssertFalse(webView is FloatTabsWebView)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)
    }

""",
    label="WebViewFactoryTests navigation observer contract",
)

text = replace_span_once(
    text,
    r"^    func testMacOSSafariRuntimeUsesNativeWebKitUAWithSafariSuffix\(\) \{",
    r"^    func testSafariCompatibilityIdentityUsesResolvedWebKitVersion\(",
    """    func testMacOSSafariRuntimeUsesNativeWebKitUAWithSafariSuffix() {
        // Monterey Compatibility Edition: the stock WKWebView keeps WebKit's
        // native UA; no application-name suffix is applied at construction.
        let rendering = WebRenderingProfile.canonicalDefault
            .settingBrowserIdentity(.macosSafari)

        XCTAssertNil(
            UserAgentProvider.customUserAgent(
                for: rendering,
                versions: versions
            )
        )

        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        XCTAssertTrue((webView.configuration.applicationNameForUserAgent ?? "").isEmpty)
        XCTAssertTrue((webView.customUserAgent ?? "").isEmpty)
    }

""",
    label="WebViewFactoryTests native UA contract",
)

text = replace_span_once(
    text,
    r"^    func testNavigationFinishRestoresHiddenScrollerPolicyAfterWebKitReenablesIt\(\) \{",
    r"^    func testConfiguredScrollerIsCompletelyHiddenAtRest\(",
    """    func testNavigationFinishRestoresHiddenScrollerPolicyAfterWebKitReenablesIt() {
        // Monterey Compatibility Edition: WebKit's internal scroll hierarchy is
        // deliberately untouched at navigation boundaries.
        let webView = WebViewFactory.makeWebView()
        let simulatedWebKitScrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: 300, height: 500)
        )
        simulatedWebKitScrollView.scrollerStyle = .legacy
        simulatedWebKitScrollView.autohidesScrollers = false
        simulatedWebKitScrollView.hasVerticalScroller = true
        simulatedWebKitScrollView.hasHorizontalScroller = true
        webView.addSubview(simulatedWebKitScrollView)

        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in }
        )
        observer.webView(webView, didFinish: nil)

        XCTAssertEqual(simulatedWebKitScrollView.scrollerStyle, .legacy)
        XCTAssertFalse(simulatedWebKitScrollView.autohidesScrollers)
        XCTAssertTrue(simulatedWebKitScrollView.hasVerticalScroller)
        XCTAssertTrue(simulatedWebKitScrollView.hasHorizontalScroller)
    }

""",
    label="WebViewFactoryTests scroller neutrality contract",
)

text = replace_span_once(
    text,
    r"^    func testWebViewInstallsPermanentContentScrollbarSuppression\(\) \{",
    r"^    func testContentScrollbarSuppressionPreservesDocumentScrolling\(",
    """    func testWebViewInstallsPermanentContentScrollbarSuppression() {
        // Monterey Compatibility Edition: no user scripts are injected; the
        // scrollbar-suppression script belongs to the standard release only.
        let webView = WebViewFactory.makeWebView()
        XCTAssertTrue(webView.configuration.userContentController.userScripts.isEmpty)
    }

""",
    label="WebViewFactoryTests no-injection contract",
)

text = replace_once_regex(
    text,
    r"^        XCTAssertEqual\(styleInstalled, 1, accuracy: 0\.001\)$",
    """        // Monterey Compatibility Edition: nothing is injected, so the count
        // must stay at zero while document scrolling keeps working.
        XCTAssertEqual(styleInstalled, 0, accuracy: 0.001)""",
    label="WebViewFactoryTests scrollbar style count contract",
)
write_source(tests, text)

pool_tests = ROOT / "FloatTabsTests/WebViewPoolTests.swift"
text = read_source(pool_tests)
text = replace_once_regex(
    text,
    r"        XCTAssertEqual\(second\.pageZoom, 1\.25, accuracy: 0\.001\)$",
    """        // Monterey Compatibility Edition: zoom metadata is persisted but
        // runtime rendering is intentionally untouched on warm reuse.
        XCTAssertEqual(second.pageZoom, first.pageZoom, accuracy: 0.001)""",
    label="WebViewPoolTests zoom no-op contract",
)
text = replace_span_once(
    text,
    r"^    func testBrowserIdentityChangeRebuildsOnlyAffectedSlotAndRestoresURL\(\) \{",
    r"^    func testRebuildNavigationURLPrefersInitialRequestBeforeRedirectedURL\(",
    """    func testBrowserIdentityChangeDoesNotReplaceResidentSlotAndNavigationStillWorks() {
        var loadedRequests: [URLRequest] = []
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) }
        )
        var profile = makeProfile(name: "Identity")
        let firstView = pool.webView(for: profile)

        profile.renderingProfile = profile.renderingProfile
            .settingBrowserIdentity(.windowsChrome)
        let reused = pool.webView(for: profile)
        let destination = URL(string: "https://example.com/identity-change")!
        pool.navigate(slotID: profile.id, to: destination)

        XCTAssertTrue(firstView === reused)
        XCTAssertTrue(reused.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue((reused.customUserAgent ?? "").isEmpty)
        XCTAssertEqual(loadedRequests.count, 2)
        XCTAssertEqual(loadedRequests.last?.url, destination)
        XCTAssertEqual(pool.count, 1)
    }

""",
    label="WebViewPoolTests browser identity no-op contract",
)
text = replace_span_once(
    text,
    r"^    func testAutomaticWebsiteModeCanMoveDesktopMobileAndBackWithoutSticking\(\) \{",
    r"^    func testChatGPTMobileAutomaticUsesDesktopPointerCompatibilityIdentity\(",
    """    func testAutomaticWebsiteModeCanMoveDesktopMobileAndBackWithoutSticking() {
        var loadedRequests: [URLRequest] = []
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) }
        )
        var profile = makeProfile(name: "A")

        // Monterey Compatibility Edition: inert Website Mode metadata does not
        // replace the resident stock WKWebView or reload its navigation.
        let desktop = pool.webView(for: profile)
        let initialZoom = desktop.pageZoom
        XCTAssertEqual(
            desktop.configuration.defaultWebpagePreferences.preferredContentMode,
            .recommended
        )
        XCTAssertTrue((desktop.configuration.applicationNameForUserAgent ?? "").isEmpty)
        XCTAssertTrue((desktop.customUserAgent ?? "").isEmpty)

        profile.renderingProfile = profile.renderingProfile.settingWebsiteMode(.mobile)
        let mobile = pool.webView(for: profile)
        XCTAssertTrue(desktop === mobile)
        XCTAssertEqual(
            mobile.configuration.defaultWebpagePreferences.preferredContentMode,
            .recommended
        )
        XCTAssertTrue((mobile.customUserAgent ?? "").isEmpty)

        profile.renderingProfile = profile.renderingProfile.settingWebsiteMode(.desktop)
        let desktopAgain = pool.webView(for: profile)
        XCTAssertTrue(mobile === desktopAgain)
        XCTAssertEqual(
            desktopAgain.configuration.defaultWebpagePreferences.preferredContentMode,
            .recommended
        )
        XCTAssertTrue((desktopAgain.configuration.applicationNameForUserAgent ?? "").isEmpty)
        XCTAssertTrue((desktopAgain.customUserAgent ?? "").isEmpty)
        XCTAssertEqual(desktopAgain.pageZoom, initialZoom, accuracy: 0.001)
        XCTAssertEqual(loadedRequests.count, 1)
        XCTAssertEqual(loadedRequests[0].cachePolicy, .useProtocolCachePolicy)
        XCTAssertEqual(pool.count, 1)
    }

""",
    label="WebViewPoolTests website-mode rebuild contract",
)
text = replace_span_once(
    text,
    r"^    func testChatGPTMobileAutomaticUsesDesktopPointerCompatibilityIdentity\(\) \{",
    r"^    func testChatGPTMobileAutomaticWarmReuseKeepsCompatibilityIdentityWithoutReload\(",
    """    func testChatGPTMobileAutomaticUsesDesktopPointerCompatibilityIdentity() {
        // Monterey Compatibility Edition: the ChatGPT site policy still resolves
        // a desktop-pointer runtime profile, but construction stays on the
        // stock WKWebView without any UA override.
        let pool = makePool()
        var profile = makeProfile(
            name: "ChatGPT",
            homeURL: URL(string: "https://chatgpt.com/")!
        )
        profile.renderingProfile = profile.renderingProfile.settingWebsiteMode(.mobile)

        let webView = pool.webView(for: profile)

        XCTAssertEqual(
            webView.configuration.defaultWebpagePreferences.preferredContentMode,
            .recommended
        )
        XCTAssertTrue((webView.customUserAgent ?? "").isEmpty)
    }

""",
    label="WebViewPoolTests ChatGPT identity contract",
)
text = replace_span_once(
    text,
    r"^    func testChatGPTMobileAutomaticWarmReuseKeepsCompatibilityIdentityWithoutReload\(\) \{",
    r"^    func testDevicePresetChangeDoesNotRebuildOrAlterBrowserIdentity\(",
    """    func testChatGPTMobileAutomaticWarmReuseKeepsCompatibilityIdentityWithoutReload() {
        // Monterey Compatibility Edition: warm reuse must not introduce a UA
        // override on the stock WKWebView.
        var loadedRequests: [URLRequest] = []
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) }
        )
        var profile = makeProfile(
            name: "ChatGPT",
            homeURL: URL(string: "https://chatgpt.com/")!
        )
        profile.renderingProfile = profile.renderingProfile.settingWebsiteMode(.mobile)

        let first = pool.webView(for: profile)
        let second = pool.webView(for: profile)
        let third = pool.webView(for: profile)

        XCTAssertTrue(first === second)
        XCTAssertTrue(second === third)
        XCTAssertEqual(loadedRequests.count, 1)
        XCTAssertTrue((first.customUserAgent ?? "").isEmpty)
        XCTAssertTrue((second.customUserAgent ?? "").isEmpty)
        XCTAssertTrue((third.customUserAgent ?? "").isEmpty)
    }

""",
    label="WebViewPoolTests warm reuse contract",
)
text = replace_once_regex(
    text,
    r"^    func testPooledWebViewsUsePersistentWebsiteDataStore\(\) \{",
    """    func testMontereyFullPoolCreationIsStockAndScriptFree() {
        var loadedRequests: [URLRequest] = []
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, request in loadedRequests.append(request) }
        )
        var profile = makeProfile(name: "PrimaryCreation")
        profile.renderingProfile = profile.renderingProfile
            .settingWebsiteMode(.mobile)
            .settingBrowserIdentity(.iphoneChrome)
            .settingZoom(1.25)

        let first = pool.webView(for: profile)

        XCTAssertFalse(first is FloatTabsWebView)
        XCTAssertTrue(first.configuration.websiteDataStore.isPersistent)
        XCTAssertTrue(first.configuration.userContentController.userScripts.isEmpty)
        XCTAssertTrue((first.customUserAgent ?? "").isEmpty)
        XCTAssertTrue((first.configuration.applicationNameForUserAgent ?? "").isEmpty)
        XCTAssertEqual(
            first.configuration.defaultWebpagePreferences.preferredContentMode,
            .recommended
        )
        XCTAssertEqual(first.pageZoom, 1, accuracy: 0.001)

        // Warm reuse must preserve identity and must not reapply inert metadata.
        first.pageZoom = 1.35
        let warm = pool.webView(for: profile)
        XCTAssertTrue(first === warm)
        XCTAssertEqual(warm.pageZoom, 1.35, accuracy: 0.001)
        XCTAssertTrue(warm.configuration.userContentController.userScripts.isEmpty)

        profile.renderingProfile = profile.renderingProfile
            .settingWebsiteMode(.desktop)
            .settingBrowserIdentity(.windowsChrome)
        let metadataChanged = pool.webView(for: profile)
        XCTAssertTrue(warm === metadataChanged)
        XCTAssertEqual(metadataChanged.pageZoom, 1.35, accuracy: 0.001)
        XCTAssertTrue(metadataChanged.configuration.userContentController.userScripts.isEmpty)
        XCTAssertEqual(loadedRequests.count, 1)
        XCTAssertEqual(pool.count, 1)
    }

    func testMontereyPanelControllerDefersSavedWebViewRestoreUntilPresentation() {
        _ = NSApplication.shared
        let profile = makeProfile(name: "Saved")
        let repository = MemoryProfileRepository(
            state: StoredWebAppState(
                version: StoredWebAppState.currentVersion,
                profiles: [profile],
                lastActiveTabID: profile.id
            )
        )
        let tabStore = TabStore(repository: repository)
        let pool = makePool()
        let defaults = UserDefaults(
            suiteName: "FloatTabsMontereyLazyRestore.\\(UUID().uuidString)"
        )!
        let controller = PanelController(
            tabStore: tabStore,
            webViewPool: pool,
            frameStore: PanelFrameStore(
                defaults: defaults,
                key: "FloatTabsMontereyLazyRestore.frame"
            ),
            preferencesStore: AppPreferencesStore(defaults: defaults)
        )

        // Monterey Compatibility Edition: initialization alone must not create
        // or load the saved slot; presentation is the explicit restore boundary.
        XCTAssertEqual(pool.count, 0)
        controller.showFloatTabs()
        XCTAssertEqual(pool.count, 1)
        controller.hideFloatTabs()
    }

    func testMontereyWarmReuseDoesNotMutatePageZoomOrStockRendering() {
        let pool = makePool()
        var profile = makeProfile(name: "WarmRendering")
        profile.renderingProfile = profile.renderingProfile
            .settingWebsiteMode(.mobile)
            .settingBrowserIdentity(.iphoneChrome)
            .settingZoom(1.25)

        let initial = pool.webView(for: profile)
        initial.pageZoom = 1.35
        let reused = pool.webView(for: profile)

        XCTAssertTrue(initial === reused)
        XCTAssertFalse(initial is FloatTabsWebView)
        XCTAssertEqual(initial.configuration.defaultWebpagePreferences.preferredContentMode, .recommended)
        XCTAssertTrue((initial.configuration.applicationNameForUserAgent ?? "").isEmpty)
        XCTAssertTrue((initial.customUserAgent ?? "").isEmpty)
        XCTAssertEqual(reused.pageZoom, 1.35, accuracy: 0.001)
    }

    func testPooledWebViewsUsePersistentWebsiteDataStore() {""",
    label="WebViewPoolTests warm rendering no-op contract",
)
if PROBE_MODE:
    text = replace_once_regex(
        text,
        r"        controller\.showFloatTabs\(\)\n        XCTAssertEqual\(pool\.count, 1\)",
        """        controller.showFloatTabs()
        // Candidate C intentionally bypasses the normal pool/lifecycle path;
        // each probe owns only the boundary named by its generated mode.
        XCTAssertEqual(pool.count, 0)""",
        label="WebViewPoolTests Candidate C lifecycle bypass contract",
    )
    expected_creates = "true" if PROBE_MODE != "shell" else "false"
    expected_attaches = "true" if PROBE_MODE in {"attach", "blank", "https"} else "false"
    expected_blank = "true" if PROBE_MODE == "blank" else "false"
    expected_https = "true" if PROBE_MODE == "https" else "false"
    text = replace_once_regex(
        text,
        r"^    func testPooledWebViewsUsePersistentWebsiteDataStore\(\) \{",
        f'''    func testMontereyGeneratedPresentationProbeContract() {{
        guard let mode = MontereyProbeMode.configured else {{
            return XCTFail("Candidate C probe mode was not generated")
        }}
        XCTAssertEqual(mode.rawValue, "{PROBE_MODE}")
        XCTAssertEqual(mode.createsWebView, {expected_creates})
        XCTAssertEqual(mode.attachesWebView, {expected_attaches})
        XCTAssertEqual(mode.loadsAboutBlank, {expected_blank})
        XCTAssertEqual(mode.loadsProfileURL, {expected_https})
    }}

    func testPooledWebViewsUsePersistentWebsiteDataStore() {{''',
        label="WebViewPoolTests Candidate C generated probe contract",
    )
write_source(pool_tests, text)

tab_store_tests = ROOT / "FloatTabsTests/TabStoreTests.swift"
text = read_source(tab_store_tests)
text = replace_span_once(
    text,
    r"^    func testOnlyBrowserIdentityOrWebsiteModeRequiresWebViewRebuild\(\) \{",
    r"^}\n\nfinal class WebAppURLTests",
    """    func testRenderingProfileChangesDoNotRequireWebViewRebuildInMontereyRuntime() {
        let base = WebRenderingProfile.canonicalDefault

        // Rendering metadata remains persisted and editable, but every WebKit
        // rendering mutation is disabled in the Monterey compatibility edition.
        XCTAssertFalse(base.settingZoom(1.25).requiresWebViewRebuild(comparedTo: base))
        XCTAssertFalse(base.settingViewport(CGSize(width: 600, height: 800)).requiresWebViewRebuild(comparedTo: base))
        XCTAssertFalse(base.settingDevicePreset(id: "iphone-17-pro").requiresWebViewRebuild(comparedTo: base))
        XCTAssertFalse(base.settingBrowserIdentity(.windowsChrome).requiresWebViewRebuild(comparedTo: base))
        XCTAssertFalse(base.settingWebsiteMode(.mobile).requiresWebViewRebuild(comparedTo: base))
    }

""",
    label="TabStoreTests Monterey no-op rebuild contract",
)
write_source(tab_store_tests, text)

geometry_tests = ROOT / "FloatTabsTests/WebsiteLayoutGeometryRegressionTests.swift"
text = read_source(geometry_tests)
text = replace_once_regex(
    text,
    r"^        XCTAssertEqual\(mainFrameStyleCount, 1, accuracy: 0\.001\)$",
    """        // Monterey Compatibility Edition: no scrollbar-suppression style is
        // injected, so the count must stay at zero.
        XCTAssertEqual(mainFrameStyleCount, 0, accuracy: 0.001)""",
    label="WebsiteLayoutGeometryRegressionTests injection contract",
)
write_source(geometry_tests, text)

# ---------------------------------------------------------------------------
# Final static contract: hard isolation assertions plus the stock-WKWebView
# baseline. These are intentionally stronger than availability checks.
# ---------------------------------------------------------------------------
prepared_floating = read_source(floating)
prepared_fullscreen = read_source(fullscreen)
prepared_web = read_source(web_factory)
prepared_popup = read_source(popup)
prepared_pool = read_source(ROOT / "FloatTabs/Web/WebViewPool.swift")
prepared_panel = read_source(panel)
prepared_observer = read_source(observer)
prepared_tests = read_source(tests)
prepared_pool_tests = read_source(pool_tests)
prepared_geometry_tests = read_source(geometry_tests)

require_absent(
    prepared_floating,
    ".canJoinAllApplications",
    label="standard macOS 13 collection behavior leaked into compatibility edition",
)
require_absent(
    prepared_fullscreen,
    "observeModernFullscreenState",
    label="modern fullscreen observer leaked into compatibility edition",
)
require_absent(
    prepared_fullscreen,
    "WKWebView.FullscreenState",
    label="modern FullscreenState API leaked into compatibility edition",
)
for required_helper in [
    "static func sourceFrame(",
    "static func isWebKitFullscreenPresentationActive(",
    "private static func makeSourceWindow(",
]:
    require_present(
        prepared_fullscreen,
        required_helper,
        label="ordinary source-host helper was removed",
    )

# The final WebViewFactory creation path must be a stock WKWebView.
make_span = span_of(
    prepared_web,
    r"^    static func makeWebView\(",
    r"^    static func makeStageZeroWebView\(",
    label="final makeWebView span",
)
require_present(
    make_span,
    "WKWebView(frame:",
    label="stock WKWebView construction missing from compatibility edition",
)
for forbidden in [
    "FloatTabsWebView(frame:",
    ".setRendering(",
    "preferredContentMode",
    "applicationNameForUserAgent",
    "isElementFullscreenEnabled",
    "hiddenScrollbarUserScript",
    "BrowserVersionCatalog.current",
    "if #available",
]:
    require_absent(
        make_span,
        forbidden,
        label=f"standard WebView behavior leaked into compatibility makeWebView: {forbidden}",
    )

runtime_rendering_span = span_of(
    prepared_web,
    r"^    static func applyRuntimeRendering\(\n        _ renderingProfile: WebRenderingProfile,\n        to webView: WKWebView\n    \) \{",
    r"^    /// AppKit scrollers stay visually disabled",
    label="final applyRuntimeRendering span",
)
for forbidden in [
    ".setRendering(",
    "pageZoom =",
    "customUserAgent =",
    "preferredContentMode",
    "applicationNameForUserAgent",
    "hiddenScrollbarUserScript",
    "FloatTabsWebView",
]:
    require_absent(
        runtime_rendering_span,
        forbidden,
        label=f"Monterey applyRuntimeRendering mutated stock WebKit: {forbidden}",
    )
require_present(
    runtime_rendering_span,
    "_ = renderingProfile\n        _ = webView",
    label="Monterey applyRuntimeRendering no-op overload",
)
require_present(
    read_source(profile),
    "return false\n    }",
    label="Monterey profile rebuild decision is not a no-op",
)

# The primary pool-created WebView may retain PopupCoordinator's native
# delegate surface, but its initializer must not mutate WKWebKit content.
popup_init_span = span_of(
    prepared_popup,
    r"^    init\(\n        parentWebView: WKWebView,\n        openExternal: @escaping ExternalOpenHandler",
    r"^    static func disposition\(",
    label="final PopupCoordinator primary initializer span",
)
for forbidden in [
    "installCurrentSlotWindowOpenPolicy(on: parentWebView)",
    "installExplicitLinkContextMenu(on: parentWebView)",
    "addUserScript",
    "controller.add(self, name:",
    "userContentController.add(",
]:
    require_absent(
        popup_init_span,
        forbidden,
        label=f"Monterey PopupCoordinator primary initializer injected WebKit content: {forbidden}",
    )
for required in [
    "self.parentWebView = parentWebView",
    "self.openExternal = openExternal",
    "self.uploadCoordinator = uploadCoordinator ?? UploadCoordinator()",
    "self.downloadCoordinator = downloadCoordinator ?? DownloadCoordinator()",
    "super.init()",
]:
    require_present(
        popup_init_span,
        required,
        label=f"PopupCoordinator native initialization missing: {required}",
    )

primary_create_span = span_of(
    prepared_pool,
    r"^    private func createWebView\(",
    r"^        return webView\n    \}",
    label="final WebViewPool primary creation span",
)
for required in [
    "WebViewFactory.makeWebView",
    "SlotNavigationObserver(",
    "PopupCoordinator(",
    "webView.uiDelegate = popupCoordinator",
    "load(webView, request)",
]:
    require_present(
        primary_create_span,
        required,
        label=f"primary WebViewPool creation path missing: {required}",
    )
for forbidden in [
    "addUserScript",
    "userContentController.add(",
    "userContentController.addUserScript(",
    "customUserAgent =",
    "preferredContentMode =",
    "pageZoom =",
]:
    require_absent(
        primary_create_span,
        forbidden,
        label=f"primary WebViewPool creation path mutated WebKit: {forbidden}",
    )

# No FloatTabsWebView may be constructed anywhere in the compatibility app.
for source_path in sorted((ROOT / "FloatTabs").rglob("*.swift")):
    require_absent(
        source_path.read_text(),
        "FloatTabsWebView(frame:",
        label=f"FloatTabsWebView construction survived in {source_path.relative_to(ROOT)}",
    )
require_absent(
    prepared_web,
    "preferredContentMode",
    label="preferredContentMode survived in compatibility WebViewFactory",
)
require_absent(
    prepared_web,
    "applicationNameForUserAgent",
    label="applicationNameForUserAgent survived in compatibility WebViewFactory",
)
require_present(
    prepared_web,
    "final class FloatTabsWebView: WKWebView",
    label="FloatTabsWebView type removed (peripheral as? paths must keep compiling)",
)

# Lazy restore semantics must survive.
require_present(
    prepared_panel,
    "[FloatTabs Monterey] PanelController initialized without WebView restore",
    label="lazy restore breadcrumb missing",
)
for marker in [
    "PanelController initialized without WebView restore",
    "address commit begin slot=",
]:
    marker_index = prepared_panel.find(marker)
    nearby = prepared_panel[max(0, marker_index - 220): marker_index + 220]
    require_absent(
        nearby,
        "if #available(macOS 13.0, *)",
        label=f"standard runtime branch still surrounds compatibility marker: {marker}",
    )
require_absent(
    prepared_observer,
    "observation = webView.observe(\\.url",
    label="provisional URL KVO leaked into compatibility edition",
)
require_present(
    prepared_observer,
    "[FloatTabs Monterey] navigation committed slot=",
    label="committed-URL persistence missing",
)

# Test contract markers.
for required_marker in [
    "Monterey Compatibility Edition: stock WKWebView baseline",
    "Monterey Compatibility Edition: desktop hosting stays on the stock",
    "Monterey Compatibility Edition: navigation finish must not mutate the",
]:
    require_present(
        prepared_tests,
        required_marker,
        label="WebViewFactoryTests compatibility contract missing",
    )
require_absent(
    prepared_tests,
    "= tryUnwrapFloatTabsWebView(",
    label="WebViewFactoryTests still unwraps FloatTabsWebView",
)
require_present(
    prepared_pool_tests,
    "Monterey Compatibility Edition: inert Website Mode metadata does not",
    label="WebViewPoolTests compatibility contract missing",
)
require_present(
    prepared_pool_tests,
    "testMontereyFullPoolCreationIsStockAndScriptFree",
    label="full WebViewPool creation contract missing",
)
require_present(
    prepared_pool_tests,
    "testMontereyPanelControllerDefersSavedWebViewRestoreUntilPresentation",
    label="WebViewPoolTests lazy restore contract missing",
)
require_present(
    prepared_geometry_tests,
    "XCTAssertEqual(mainFrameStyleCount, 0, accuracy: 0.001)",
    label="WebsiteLayoutGeometryRegressionTests compatibility contract missing",
)

if PROBE_MODE:
    require_present(
        prepared_panel,
        f"static let configured: MontereyProbeMode? = .{PROBE_MODE}",
        label="Candidate C generated probe mode is missing",
    )
    probe_presentation_span = span_of(
        prepared_panel,
        r"^    func showFloatTabs\(\) \{",
        r"^    func hideFloatTabs\(\) \{",
        label="Candidate C first-presentation span",
    )
    for forbidden in [
        "synchronizeSlotState()",
        "slotLifecycleCoordinator",
        "sourceHostController.observeFullscreenState",
        "focusActiveWebViewIfAvailable",
        "WebViewPool",
        "PopupCoordinator",
        "SlotNavigationObserver",
        "evaluateJavaScript",
        "addUserScript",
        "navigationDelegate",
        "uiDelegate",
        "pageZoom",
        "setRendering(",
        "customUserAgent",
        "preferredContentMode",
    ]:
        require_absent(
            probe_presentation_span,
            forbidden,
            label=f"Candidate C {PROBE_MODE} probe crossed forbidden boundary: {forbidden}",
        )
    require_present(
        probe_presentation_span,
        "panel.orderFrontRegardless()",
        label="Candidate C probe does not present the shell first",
    )

    if PROBE_MODE == "shell":
        for forbidden in [
            "DispatchQueue.main.async",
            "WebViewFactory.makeWebView",
            "webPanelContainerView.show(webView:",
            ".load(URLRequest",
        ]:
            require_absent(
                probe_presentation_span,
                forbidden,
                label=f"C0 shell probe crossed boundary: {forbidden}",
            )
    else:
        require_present(
            probe_presentation_span,
            "DispatchQueue.main.async",
            label=f"Candidate C {PROBE_MODE} probe was not deferred",
        )
        require_present(
            probe_presentation_span,
            "WebViewFactory.makeWebView()",
            label=f"Candidate C {PROBE_MODE} probe did not construct a stock WebView",
        )
        require_present(
            probe_presentation_span,
            "montereyProbeWebView = webView",
            label=f"Candidate C {PROBE_MODE} probe did not retain its WebView",
        )
        if PROBE_MODE in {"attach", "blank", "https"}:
            require_present(
                probe_presentation_span,
                "rootView.webPanelContainerView.show(webView: webView)",
                label=f"Candidate C {PROBE_MODE} probe did not use the host attach path",
            )
        else:
            require_absent(
                probe_presentation_span,
                "webPanelContainerView.show(webView:",
                label="C1 construct probe attached the WebView",
            )
        if PROBE_MODE == "construct":
            require_absent(
                probe_presentation_span,
                ".load(URLRequest",
                label="C1 construct probe loaded a URL",
            )
        elif PROBE_MODE == "blank":
            require_present(
                probe_presentation_span,
                'URL(string: "about:blank")!',
                label="C3 blank probe missing about:blank load",
            )
        elif PROBE_MODE == "https":
            require_present(
                probe_presentation_span,
                "let destination = profile.currentURL ?? profile.homeURL",
                label="C4 HTTPS probe missing profile URL selection",
            )
            require_present(
                probe_presentation_span,
                "webView.load(URLRequest(url: destination))",
                label="C4 HTTPS probe missing plain load",
            )
    require_present(
        prepared_pool_tests,
        "testMontereyGeneratedPresentationProbeContract",
        label="Candidate C generated probe test is missing",
    )

print("Applied isolated Monterey Compatibility Edition runtime semantics.")
