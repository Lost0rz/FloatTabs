#!/usr/bin/env python3
"""Stage 7: Candidate F Monterey navigation + explicit Website Mode layout.

This stage intentionally runs after prepare_monterey_isolated_runtime.py.
Candidate E established that focus is not causal and that delegate registration /
callback behavior is the crash boundary on real Monterey 12.7.6. Candidate F
therefore keeps a primary WKUIDelegate, replaces the primary navigation delegate
with the smallest lifecycle-only observer, and restores Website Mode strictly as
AppKit host geometry metadata. No WebKit rendering identity is mutated here.
"""

import re
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

# ---------------------------------------------------------------------------
# Navigation: remove the standard SlotNavigationObserver implementation from
# the generated Monterey source. The primary WebView owns exactly one minimal
# lifecycle observer. Policy / response / download delegate callbacks are not
# present in this type.
# ---------------------------------------------------------------------------
observer_path = ROOT / "FloatTabs/Web/SlotNavigationObserver.swift"
text = read_source(observer_path)
minimal_observer = r'''/// Monterey Candidate F navigation lifecycle observer.
///
/// Real Monterey 12.7.6 evidence isolates delegate registration/callback
/// behavior as the failure boundary. Keep the registered navigation delegate
/// deliberately small: URL persistence plus content-process recovery only.
/// Website Mode is AppKit host metadata and never enters a WebKit callback.
@MainActor
final class MontereyNavigationObserver: NSObject, WKNavigationDelegate {
    private weak var webView: WKWebView?
    private let slotID: UUID
    private let onURLChange: @MainActor (UUID, URL) -> Void
    private let onContentProcessTermination: @MainActor (UUID) -> Void

    var isHTTPEntryFallbackPending: Bool { false }

    init(
        slotID: UUID,
        webView: WKWebView,
        onURLChange: @escaping @MainActor (UUID, URL) -> Void,
        onContentProcessTermination: @escaping @MainActor (UUID) -> Void = { _ in }
    ) {
        self.slotID = slotID
        self.webView = webView
        self.onURLChange = onURLChange
        self.onContentProcessTermination = onContentProcessTermination
        super.init()
        webView.navigationDelegate = self
    }

    // Source-compatibility initializer for generated tests and dormant helper
    // seams. The production WebViewPool does not pass Website Mode, navigation
    // policy, download policy, or a load handler into the minimal observer.
    convenience init(
        slotID: UUID,
        webView: WKWebView,
        websiteMode: WebsiteMode,
        navigationCoordinator: WebNavigationCoordinator = WebNavigationCoordinator(),
        downloadCoordinator: DownloadCoordinator? = nil,
        onURLChange: @escaping @MainActor (UUID, URL) -> Void,
        onContentProcessTermination: @escaping @MainActor (UUID) -> Void = { _ in },
        loadHandler: @escaping @MainActor (WKWebView, URL) -> Void = { _, _ in }
    ) {
        _ = websiteMode
        _ = navigationCoordinator
        _ = downloadCoordinator
        _ = loadHandler
        self.init(
            slotID: slotID,
            webView: webView,
            onURLChange: onURLChange,
            onContentProcessTermination: onContentProcessTermination
        )
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        persistSafeCommittedURL(from: webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        persistSafeCommittedURL(from: webView)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        _ = navigation
        _ = error
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        _ = navigation
        _ = error
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        _ = webView
        onContentProcessTermination(slotID)
    }

    func configureHTTPEntryFallback(for url: URL, allowed: Bool) {
        // Candidate F intentionally does not add navigation policy/fallback
        // behavior to the registered delegate while the Monterey crash seam is
        // isolated. Keep the pool API source-compatible without runtime effect.
        _ = url
        _ = allowed
    }

    /// Historical pure regression seam. It is not a WKNavigationDelegate
    /// callback and does not participate in Candidate F runtime navigation.
    static func shouldOpenInCurrentSlot(targetFrame: WKFrameInfo?, url: URL?) -> Bool {
        WebNavigationCoordinator.stage3FallbackDisposition(
            hasTargetFrame: targetFrame != nil,
            url: url
        ) == .loadInCurrentSlot
    }

    /// Historical pure helper retained for generated tests only. Candidate F
    /// does not invoke it from a WebKit delegate callback.
    static func httpFallbackURL(pending: URL?, failingURL: URL?, error: Error) -> URL? {
        guard let pending,
              let failingURL,
              failingURL == pending || failingURL.absoluteString == pending.absoluteString else {
            return nil
        }
        let nsError = error as NSError
        let connectionLevelFailureCodes: Set<Int> = [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorSecureConnectionFailed,
        ]
        guard nsError.domain == NSURLErrorDomain,
              connectionLevelFailureCodes.contains(nsError.code) else {
            return nil
        }
        return WebAppURL.httpFallbackCandidate(for: pending)
    }

    private func persistSafeCommittedURL(from webView: WKWebView) {
        guard let url = webView.url, WebAppURL.isSafe(url) else { return }
        NSLog("[FloatTabs Monterey Candidate F] navigation committed slot=%@", slotID.uuidString)
        onURLChange(slotID, url)
    }
}

// Generated-test source compatibility only. The production pool constructs the
// Monterey-named observer directly, so the primary delegate identity is explicit.
typealias SlotNavigationObserver = MontereyNavigationObserver
'''
text = replace_once_regex(
    text,
    r"/// Owns the per-Slot navigation lifecycle.*\Z",
    minimal_observer,
    label="Candidate F minimal Monterey navigation observer",
    flags=DOTALL,
)
write_source(observer_path, text)

# ---------------------------------------------------------------------------
# WebViewPool: primary navigation delegate is the Monterey minimal observer;
# primary PopupCoordinator remains installed as WKUIDelegate. Candidate B's
# script-free PopupCoordinator initialization was already generated by stage 6.
# ---------------------------------------------------------------------------
pool_path = ROOT / "FloatTabs/Web/WebViewPool.swift"
text = read_source(pool_path)
text = replace_once_regex(
    text,
    r"private var navigationObservers: \[UUID: SlotNavigationObserver\] = \[:\]",
    "private var navigationObservers: [UUID: MontereyNavigationObserver] = [:]",
    label="Candidate F pool observer storage type",
)
text = replace_span_once(
    text,
    r"^        let observer = SlotNavigationObserver\(",
    r"^        let popupCoordinator = PopupCoordinator\(",
    """        let observer = MontereyNavigationObserver(
            slotID: profile.id,
            webView: webView,
            onURLChange: { [weak self] slotID, url in
                guard let self else { return }
                self.lastKnownURLs[slotID] = url
                self.onURLChange(slotID, url)
            },
            onContentProcessTermination: { [weak self] slotID in
                self?.handleContentProcessTermination(slotID: slotID)
            }
        )
""",
    label="Candidate F primary minimal observer creation",
)
write_source(pool_path, text)

# ---------------------------------------------------------------------------
# Website Mode: explicit AppKit host metadata. Neither WebSlotHostView nor
# WebPanelContainerView asks WKWebView / WKWebpagePreferences what mode to use.
# ---------------------------------------------------------------------------
container_path = ROOT / "FloatTabs/Web/WebViewContainer.swift"
text = read_source(container_path)

# Hot-slot host owns explicit mode metadata beside the hosted WKWebView.
text = replace_once_regex(
    text,
    r"    private\(set\) var websiteLayoutScale: CGFloat = 1\n    private var isApplyingWebsiteLayout = false",
    """    private(set) var websiteLayoutScale: CGFloat = 1
    private(set) var websiteMode: WebsiteMode = .desktop
    private var isApplyingWebsiteLayout = false""",
    label="Candidate F WebSlotHost explicit mode storage",
)
text = replace_once_regex(
    text,
    r"    convenience init\(webView: WKWebView\) \{\n        self\.init\(frame: \.zero\)\n        attach\(webView\)\n    \}",
    """    convenience init(
        webView: WKWebView,
        websiteMode: WebsiteMode = .desktop
    ) {
        self.init(frame: .zero)
        self.websiteMode = websiteMode
        attach(webView)
    }""",
    label="Candidate F WebSlotHost explicit mode initializer",
)
text = replace_once_regex(
    text,
    r"^    func attach\(_ webView: WKWebView\) \{",
    """    func setWebsiteMode(_ websiteMode: WebsiteMode) {
        guard self.websiteMode != websiteMode else { return }
        self.websiteMode = websiteMode
        applyWebsiteLayoutIfNeeded()
    }

    func attach(_ webView: WKWebView) {""",
    label="Candidate F WebSlotHost mode update seam",
)
text = replace_once_regex(
    text,
    r"        let mode = \(webView as\? FloatTabsWebView\)\?\.websiteMode\n"
    r"            \?\? \(webView\.configuration\.defaultWebpagePreferences\.preferredContentMode == \.mobile\n"
    r"                \? \.mobile\n"
    r"                : \.desktop\)\n"
    r"        let logicalSize = WebsiteLayoutViewport\.logicalSize\(\n"
    r"            forVisibleSize: visibleSize,\n"
    r"            websiteMode: mode\n"
    r"        \)",
    """        let logicalSize = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: visibleSize,
            websiteMode: websiteMode
        )""",
    label="Candidate F WebSlotHost no WebKit mode inference",
)

# Transient container owns explicit mode metadata too.
text = replace_once_regex(
    text,
    r"    private var hotHostViews: \[UUID: WebSlotHostView\] = \[:\]\n\n    private\(set\) var websiteLayoutScale: CGFloat = 1",
    """    private var hotHostViews: [UUID: WebSlotHostView] = [:]
    private var hostedWebsiteMode: WebsiteMode = .desktop

    private(set) var websiteLayoutScale: CGFloat = 1""",
    label="Candidate F WebPanel explicit transient mode storage",
)
text = replace_once_regex(
    text,
    r"    func show\(webView: WKWebView\) \{\n        showTransient\(webView: webView, slotID: nil\)\n    \}",
    """    func show(webView: WKWebView) {
        // Legacy test/probe seam only. Product Slot presentation uses the
        // policy-aware overload and always supplies explicit Website Mode.
        showTransient(webView: webView, slotID: nil, websiteMode: .desktop)
    }""",
    label="Candidate F test-only default show seam",
)
text = replace_span_once(
    text,
    r"^    func show\(\n        webView: WKWebView,\n        slotID: UUID,\n        residencyPolicy: SlotResidencyPolicy\n    \) \{",
    r"^    func deactivate\(slotID: UUID, residencyPolicy: SlotResidencyPolicy\) \{",
    """    func show(
        webView: WKWebView,
        slotID: UUID,
        residencyPolicy: SlotResidencyPolicy,
        websiteMode: WebsiteMode
    ) {
        switch residencyPolicy {
        case .hot:
            showHot(webView: webView, slotID: slotID, websiteMode: websiteMode)
        case .warm, .cold:
            showTransient(webView: webView, slotID: slotID, websiteMode: websiteMode)
        }
    }

    // Generated-test compatibility seam. Product code is statically required
    // below to call the explicit Website Mode overload.
    func show(
        webView: WKWebView,
        slotID: UUID,
        residencyPolicy: SlotResidencyPolicy
    ) {
        show(
            webView: webView,
            slotID: slotID,
            residencyPolicy: residencyPolicy,
            websiteMode: .desktop
        )
    }

""",
    label="Candidate F explicit policy-aware container API",
)
text = replace_once_regex(
    text,
    r"        websiteLayoutScale = 1\n        logicalHostView\.bounds =",
    """        websiteLayoutScale = 1
        hostedWebsiteMode = .desktop
        logicalHostView.bounds =""",
    label="Candidate F empty-state mode reset",
)
text = replace_once_regex(
    text,
    r"^    private func showHot\(webView: WKWebView, slotID: UUID\) \{",
    """    private func showHot(
        webView: WKWebView,
        slotID: UUID,
        websiteMode: WebsiteMode
    ) {""",
    label="Candidate F hot show explicit mode signature",
)
text = replace_once_regex(
    text,
    r"        if let existing = hotHostViews\[slotID\] \{\n            host = existing\n            host\.attach\(webView\)\n        \} else \{\n            host = WebSlotHostView\(webView: webView\)",
    """        if let existing = hotHostViews[slotID] {
            host = existing
            host.setWebsiteMode(websiteMode)
            host.attach(webView)
        } else {
            host = WebSlotHostView(webView: webView, websiteMode: websiteMode)""",
    label="Candidate F hot host mode synchronization",
)
text = replace_once_regex(
    text,
    r"^    private func showTransient\(webView: WKWebView, slotID: UUID\?\) \{",
    """    private func showTransient(
        webView: WKWebView,
        slotID: UUID?,
        websiteMode: WebsiteMode
    ) {
        hostedWebsiteMode = websiteMode""",
    label="Candidate F transient show explicit mode signature",
)
text = replace_once_regex(
    text,
    r"        let mode = \(webView as\? FloatTabsWebView\)\?\.websiteMode\n"
    r"            \?\? \(webView\.configuration\.defaultWebpagePreferences\.preferredContentMode == \.mobile\n"
    r"                \? \.mobile\n"
    r"                : \.desktop\)\n"
    r"        let logicalSize = WebsiteLayoutViewport\.logicalSize\(\n"
    r"            forVisibleSize: visibleSize,\n"
    r"            websiteMode: mode\n"
    r"        \)",
    """        let logicalSize = WebsiteLayoutViewport.logicalSize(
            forVisibleSize: visibleSize,
            websiteMode: hostedWebsiteMode
        )""",
    label="Candidate F WebPanel no WebKit mode inference",
)
write_source(container_path, text)

# Primary caller supplies the profile Website Mode explicitly.
panel_path = ROOT / "FloatTabs/Panel/PanelController.swift"
text = read_source(panel_path)
text = replace_once_regex(
    text,
    r"        rootView\.webPanelContainerView\.show\(\n"
    r"            webView: webView,\n"
    r"            slotID: activeProfile\.id,\n"
    r"            residencyPolicy: activeProfile\.residencyPolicy\n"
    r"        \)",
    """        rootView.webPanelContainerView.show(
            webView: webView,
            slotID: activeProfile.id,
            residencyPolicy: activeProfile.residencyPolicy,
            websiteMode: activeProfile.renderingProfile.effectiveWebsiteMode
        )""",
    label="Candidate F primary explicit Website Mode call",
)
write_source(panel_path, text)

# ---------------------------------------------------------------------------
# Generated tests: stock WKWebView must switch Desktop <-> Mobile geometry on
# the same object; primary delegates must be minimal navigation + Popup UI.
# ---------------------------------------------------------------------------
factory_tests_path = ROOT / "FloatTabsTests/WebViewFactoryTests.swift"
text = read_source(factory_tests_path)
text = replace_span_once(
    text,
    r"^    func testMobileModeFallsBackToDesktopClassHostingOnStockWebView\(\) \{",
    r"^    func testDesktopHostMapsVisibleCenterIntoLogicalWebCoordinates\(",
    """    func testMontereyExplicitWebsiteModeSwitchesStockWebViewWithoutRebuild() {
        _ = NSApplication.shared
        let webView = WebViewFactory.makeWebView(renderingProfile: .canonicalDefault)
        XCTAssertFalse(webView is FloatTabsWebView)

        let slotID = UUID()
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 820)
        )
        container.layoutSubtreeIfNeeded()

        container.show(
            webView: webView,
            slotID: slotID,
            residencyPolicy: .warm,
            websiteMode: .desktop
        )
        container.layoutSubtreeIfNeeded()
        XCTAssertTrue(container.currentWebView === webView)
        XCTAssertEqual(webView.frame.width, 1024, accuracy: 0.001)
        XCTAssertEqual(container.websiteLayoutScale, 600.0 / 1024.0, accuracy: 0.001)
        XCTAssertLessThan(container.websiteLayoutScale, 1)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)

        container.show(
            webView: webView,
            slotID: slotID,
            residencyPolicy: .warm,
            websiteMode: .mobile
        )
        container.layoutSubtreeIfNeeded()
        XCTAssertTrue(container.currentWebView === webView)
        XCTAssertEqual(webView.frame.width, 600, accuracy: 0.001)
        XCTAssertEqual(webView.frame.height, 820, accuracy: 0.001)
        XCTAssertEqual(container.websiteLayoutScale, 1, accuracy: 0.001)
        XCTAssertEqual(webView.pageZoom, 1, accuracy: 0.001)

        container.show(
            webView: webView,
            slotID: slotID,
            residencyPolicy: .warm,
            websiteMode: .desktop
        )
        container.layoutSubtreeIfNeeded()
        XCTAssertTrue(container.currentWebView === webView)
        XCTAssertEqual(webView.frame.width, 1024, accuracy: 0.001)
        XCTAssertEqual(container.websiteLayoutScale, 600.0 / 1024.0, accuracy: 0.001)
    }

""",
    label="Candidate F stock WebView explicit mode switching test",
)
write_source(factory_tests_path, text)

pool_tests_path = ROOT / "FloatTabsTests/WebViewPoolTests.swift"
text = read_source(pool_tests_path)
text = replace_once_regex(
    text,
    r"    func testPooledWebViewsInstallPopupCoordinator\(\) \{\n"
    r"        let pool = makePool\(\)\n"
    r"        let webView = pool\.webView\(for: makeProfile\(name: \"A\"\)\)\n\n"
    r"        XCTAssertTrue\(webView\.uiDelegate is PopupCoordinator\)\n"
    r"    \}",
    """    func testPooledWebViewsInstallCandidateFMinimalNavigationAndPopupDelegates() {
        let pool = makePool()
        let webView = pool.webView(for: makeProfile(name: "A"))

        XCTAssertTrue(webView.navigationDelegate is MontereyNavigationObserver)
        XCTAssertTrue(webView.uiDelegate is PopupCoordinator)
    }""",
    label="Candidate F primary delegate runtime test",
)
write_source(pool_tests_path, text)

# ---------------------------------------------------------------------------
# Candidate F static contract. This runs on generated source in both CI and the
# DMG build and fails closed if source drift reintroduces the isolated WebKit
# delegate/rendering paths.
# ---------------------------------------------------------------------------
prepared_observer = read_source(observer_path)
prepared_pool = read_source(pool_path)
prepared_container = read_source(container_path)
prepared_panel = read_source(panel_path)
prepared_popup = read_source(ROOT / "FloatTabs/Web/PopupCoordinator.swift")
prepared_factory_tests = read_source(factory_tests_path)
prepared_pool_tests = read_source(pool_tests_path)

minimal_span = span_of(
    prepared_observer,
    r"^final class MontereyNavigationObserver: NSObject, WKNavigationDelegate \{",
    r"^typealias SlotNavigationObserver = MontereyNavigationObserver",
    label="Candidate F minimal observer span",
)
for forbidden in [
    "decidePolicyFor",
    "shouldPerformDownload",
    "WKNavigationActionPolicy.download",
    "WKNavigationResponsePolicy.download",
    "didBecome download",
    "preferredContentMode",
    "customUserAgent",
    "applicationNameForUserAgent",
    "pageZoom =",
    "FloatTabsWebView",
    "configureHiddenScrollers",
]:
    require_absent(
        minimal_span,
        forbidden,
        label=f"Candidate F minimal observer crossed forbidden boundary: {forbidden}",
    )
for required in [
    "func webView(_ webView: WKWebView, didCommit",
    "func webView(_ webView: WKWebView, didFinish",
    "didFail navigation:",
    "didFailProvisionalNavigation",
    "webViewWebContentProcessDidTerminate",
    "webView.navigationDelegate = self",
    "persistSafeCommittedURL",
]:
    require_present(
        minimal_span,
        required,
        label=f"Candidate F minimal observer lifecycle missing: {required}",
    )

primary_create_span = span_of(
    prepared_pool,
    r"^    private func createWebView\(",
    r"^        return webView\n    \}",
    label="Candidate F primary WebViewPool creation span",
)
for required in [
    "let observer = MontereyNavigationObserver(",
    "let popupCoordinator = PopupCoordinator(",
    "webView.uiDelegate = popupCoordinator",
]:
    require_present(
        primary_create_span,
        required,
        label=f"Candidate F primary delegate path missing: {required}",
    )
require_absent(
    primary_create_span,
    "let observer = SlotNavigationObserver(",
    label="Candidate F primary pool restored standard observer name",
)

popup_init_span = span_of(
    prepared_popup,
    r"^    init\(\n        parentWebView: WKWebView,\n        openExternal: @escaping ExternalOpenHandler",
    r"^    static func disposition\(",
    label="Candidate F PopupCoordinator primary initializer",
)
for forbidden in [
    "addUserScript",
    "userContentController.add(",
    "controller.add(self, name:",
    "installCurrentSlotWindowOpenPolicy(on: parentWebView)",
    "installExplicitLinkContextMenu(on: parentWebView)",
]:
    require_absent(
        popup_init_span,
        forbidden,
        label=f"Candidate F PopupCoordinator primary initialization injected content: {forbidden}",
    )

slot_host_span = span_of(
    prepared_container,
    r"^final class WebSlotHostView: NSView \{",
    r"^/// Owns the visible FloatTabs web surface",
    label="Candidate F WebSlotHost span",
)
for forbidden in [
    "FloatTabsWebView",
    "preferredContentMode",
    "customUserAgent",
    "applicationNameForUserAgent",
    "pageZoom =",
]:
    require_absent(
        slot_host_span,
        forbidden,
        label=f"Candidate F WebSlotHost inferred/mutated WebKit rendering: {forbidden}",
    )
for required in [
    "private(set) var websiteMode: WebsiteMode = .desktop",
    "func setWebsiteMode(_ websiteMode: WebsiteMode)",
    "websiteMode: websiteMode",
]:
    require_present(
        slot_host_span,
        required,
        label=f"Candidate F WebSlotHost explicit mode missing: {required}",
    )

panel_container_span = span_of(
    prepared_container,
    r"^final class WebPanelContainerView: NSView \{",
    r"\Z",
    label="Candidate F WebPanelContainer span",
    flags=DOTALL,
)
for forbidden in [
    "FloatTabsWebView",
    "preferredContentMode",
    "customUserAgent",
    "applicationNameForUserAgent",
    "pageZoom =",
]:
    require_absent(
        panel_container_span,
        forbidden,
        label=f"Candidate F WebPanelContainer inferred/mutated WebKit rendering: {forbidden}",
    )
for required in [
    "private var hostedWebsiteMode: WebsiteMode = .desktop",
    "websiteMode: WebsiteMode",
    "websiteMode: hostedWebsiteMode",
]:
    require_present(
        panel_container_span,
        required,
        label=f"Candidate F WebPanelContainer explicit mode missing: {required}",
    )

primary_show_span = span_of(
    prepared_panel,
    r"^    private func synchronizeSlotState\(\) \{",
    r"^    private func synchronizeResidentIndicators\(\) \{",
    label="Candidate F primary slot synchronization span",
)
require_present(
    primary_show_span,
    "websiteMode: activeProfile.renderingProfile.effectiveWebsiteMode",
    label="Candidate F primary caller did not pass explicit Website Mode",
)

for source_path in sorted((ROOT / "FloatTabs").rglob("*.swift")):
    source = source_path.read_text(encoding="utf-8")
    if source_path == container_path:
        continue
    # No product source may infer Website Mode from WKWebpagePreferences as a
    # Candidate F host-layout fallback. Standard-edition declarations can still
    # exist elsewhere, but primary Monterey presentation is guarded above.
    if "webPanelContainerView.show(" in source and source_path == panel_path:
        require_present(
            primary_show_span,
            "websiteMode: activeProfile.renderingProfile.effectiveWebsiteMode",
            label="Candidate F PanelController explicit Website Mode",
        )

require_present(
    prepared_factory_tests,
    "testMontereyExplicitWebsiteModeSwitchesStockWebViewWithoutRebuild",
    label="Candidate F Desktop/Mobile geometry test missing",
)
for expected in [
    "XCTAssertEqual(webView.frame.width, 1024",
    "XCTAssertEqual(webView.frame.width, 600",
    "XCTAssertEqual(container.websiteLayoutScale, 1",
    "XCTAssertTrue(container.currentWebView === webView)",
]:
    require_present(
        prepared_factory_tests,
        expected,
        label=f"Candidate F geometry identity assertion missing: {expected}",
    )
require_present(
    prepared_pool_tests,
    "XCTAssertTrue(webView.navigationDelegate is MontereyNavigationObserver)",
    label="Candidate F navigation delegate runtime assertion missing",
)
require_present(
    prepared_pool_tests,
    "XCTAssertTrue(webView.uiDelegate is PopupCoordinator)",
    label="Candidate F UI delegate runtime assertion missing",
)

print("Applied Monterey Candidate F minimal navigation + explicit Website Mode layout.")
