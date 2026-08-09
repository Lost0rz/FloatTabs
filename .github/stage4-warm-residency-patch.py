from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    return text.replace(old, new, 1)


pool_path = Path("FloatTabs/Web/WebViewPool.swift")
pool = pool_path.read_text()
pool = replace_once(
    pool,
    "import Foundation\nimport WebKit\n",
    "import AppKit\nimport Foundation\nimport WebKit\n",
    "WebViewPool imports",
)
pool = replace_once(
    pool,
    """            // Reapply the effective runtime profile, not the persisted base profile.\n            // Narrow compatibility overrides such as ChatGPT Automatic+Mobile must\n            // remain stable when a warm WKWebView is detached and later reused.\n""",
    """            // Reapply the effective runtime profile, not the persisted base profile.\n            // Narrow compatibility overrides such as ChatGPT Automatic+Mobile must\n            // remain stable whenever a warm WKWebView is selected again.\n""",
    "warm identity comment",
)
pool = replace_once(
    pool,
    """    func remove(slotID: UUID) {\n        discardPopupCoordinator(slotID: slotID)\n        navigationObservers.removeValue(forKey: slotID)\n        appliedRenderingProfiles.removeValue(forKey: slotID)\n        lastKnownURLs.removeValue(forKey: slotID)\n        deferredReloadSlotIDs.remove(slotID)\n        webViews.removeValue(forKey: slotID)\n    }\n""",
    """    func remove(slotID: UUID) {\n        discardPopupCoordinator(slotID: slotID)\n        navigationObservers.removeValue(forKey: slotID)\n        appliedRenderingProfiles.removeValue(forKey: slotID)\n        lastKnownURLs.removeValue(forKey: slotID)\n        deferredReloadSlotIDs.remove(slotID)\n        webViews[slotID]?.removeFromSuperview()\n        webViews.removeValue(forKey: slotID)\n    }\n""",
    "remove slot residency",
)
pool = replace_once(
    pool,
    """        deferredReloadSlotIDs.remove(profile.id)\n        webViews.removeValue(forKey: profile.id)\n        return createWebView(\n""",
    """        deferredReloadSlotIDs.remove(profile.id)\n        webViews[profile.id]?.removeFromSuperview()\n        webViews.removeValue(forKey: profile.id)\n        return createWebView(\n""",
    "rebuild slot residency",
)

warm_host = r'''

/// Keeps every warm Slot's WKWebView attached to the same AppKit window.
/// Switching Slots changes only sibling order. Existing WebViews are never
/// removed/re-added merely because another Slot becomes active, so heavy SPA
/// DOM/JS/compositor state can remain warm across ordinary Slot switches.
///
/// Stage 5 owns resource scheduling for these resident inactive views; this
/// Stage 4 boundary is intentionally about state continuity and switch latency.
@MainActor
final class WarmWebViewResidencyCoordinator {
    private unowned let container: WebPanelContainerView
    private weak var hostView: NSView?
    private weak var active: WKWebView?

    init(container: WebPanelContainerView) {
        self.container = container
    }

    var activeWebView: WKWebView? {
        active
    }

    func show(webView: WKWebView) {
        let host: NSView
        if let existingHost = hostView {
            host = existingHost
        } else {
            container.show(webView: webView)
            guard let attachedHost = webView.superview else { return }
            hostView = attachedHost
            host = attachedHost
        }

        if webView.superview !== host {
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.autoresizingMask = [.width, .height]
            webView.frame = host.bounds
            host.addSubview(webView)
        } else {
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.autoresizingMask = [.width, .height]
        }

        // Reordering the existing subviews keeps every resident WKWebView in the
        // same window hierarchy. AppKit moves shared views without remove/re-add.
        var orderedSubviews = host.subviews
        if let index = orderedSubviews.firstIndex(where: { $0 === webView }) {
            let selected = orderedSubviews.remove(at: index)
            orderedSubviews.append(selected)
            host.subviews = orderedSubviews
        }

        for resident in host.subviews.compactMap({ $0 as? WKWebView }) {
            resident.isHidden = false
            resident.alphaValue = 1
            resident.autoresizingMask = [.width, .height]
            if resident.frame != host.bounds {
                resident.frame = host.bounds
            }
        }

        active = webView
    }

    func showEmptyState() {
        if let hostView {
            for resident in hostView.subviews.compactMap({ $0 as? WKWebView }) {
                resident.removeFromSuperview()
            }
        }
        active = nil
        hostView = nil
        container.showEmptyState()
    }
}
'''
if "final class WarmWebViewResidencyCoordinator" not in pool:
    pool += warm_host
else:
    raise SystemExit("WarmWebViewResidencyCoordinator already exists")
pool_path.write_text(pool)

panel_path = Path("FloatTabs/Panel/PanelController.swift")
panel = panel_path.read_text()
panel = replace_once(
    panel,
    """    private let quickURLOverlayView = QuickURLOverlayView()\n    private let zoomHUDView = ZoomHUDView()\n\n    private var moveHoverController: PanelMoveHoverController?\n""",
    """    private let quickURLOverlayView = QuickURLOverlayView()\n    private let zoomHUDView = ZoomHUDView()\n    private lazy var warmWebViewResidency = WarmWebViewResidencyCoordinator(\n        container: rootView.webPanelContainerView\n    )\n\n    private var moveHoverController: PanelMoveHoverController?\n""",
    "PanelController warm residency property",
)
panel = replace_once(
    panel,
    """        guard let activeProfile = tabStore.activeProfile else {\n            lastSynchronizedActiveID = nil\n            rootView.webPanelContainerView.showEmptyState()\n            return\n        }\n""",
    """        guard let activeProfile = tabStore.activeProfile else {\n            lastSynchronizedActiveID = nil\n            warmWebViewResidency.showEmptyState()\n            return\n        }\n""",
    "PanelController empty state",
)
panel = replace_once(
    panel,
    """        let webView = webViewPool.webView(for: activeProfile)\n        rootView.webPanelContainerView.show(webView: webView)\n        WebViewFactory.configureHiddenScrollers(in: webView)\n""",
    """        let webView = webViewPool.webView(for: activeProfile)\n        warmWebViewResidency.show(webView: webView)\n        WebViewFactory.configureHiddenScrollers(in: webView)\n""",
    "PanelController warm show",
)
panel = replace_once(
    panel,
    """    private func focusActiveWebViewIfAvailable() {\n        guard !quickURLOverlayView.isPresented,\n              let webView = rootView.webPanelContainerView.currentWebView else { return }\n        _ = panel.makeFirstResponder(webView)\n    }\n""",
    """    private func focusActiveWebViewIfAvailable() {\n        guard !quickURLOverlayView.isPresented,\n              let webView = warmWebViewResidency.activeWebView else { return }\n        _ = panel.makeFirstResponder(webView)\n    }\n""",
    "PanelController active focus",
)
panel_path.write_text(panel)

tests_path = Path("FloatTabsTests/WebViewPoolTests.swift")
tests = tests_path.read_text()
anchor = """    private func makePool() -> WebViewPool {\n"""
regression = r'''    func testWarmResidencyKeepsInactiveWebViewsAttachedToWindowAcrossSwitches() {
        let container = WebPanelContainerView(
            frame: NSRect(x: 0, y: 0, width: 600, height: 800)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 800),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        container.frame = window.contentView?.bounds ?? container.frame
        container.layoutSubtreeIfNeeded()

        let residency = WarmWebViewResidencyCoordinator(container: container)
        let first = WebViewFactory.makeWebView()
        let second = WebViewFactory.makeWebView()

        residency.show(webView: first)
        let host = first.superview
        XCTAssertNotNil(host)
        XCTAssertTrue(first.window === window)

        residency.show(webView: second)
        XCTAssertTrue(first.superview === host)
        XCTAssertTrue(second.superview === host)
        XCTAssertTrue(first.window === window)
        XCTAssertTrue(second.window === window)
        XCTAssertTrue(residency.activeWebView === second)
        XCTAssertTrue(host?.subviews.last === second)

        residency.show(webView: first)
        XCTAssertTrue(first.superview === host)
        XCTAssertTrue(second.superview === host)
        XCTAssertTrue(first.window === window)
        XCTAssertTrue(second.window === window)
        XCTAssertTrue(residency.activeWebView === first)
        XCTAssertTrue(host?.subviews.last === first)
    }

'''
tests = replace_once(
    tests,
    anchor,
    regression + anchor,
    "WebViewPoolTests warm residency insertion",
)
tests_path.write_text(tests)

print("Stage 4 warm residency patch applied")
