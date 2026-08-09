import AppKit
import Foundation
import WebKit

@MainActor
final class WebViewPool {
    typealias LoadHandler = (WKWebView, URLRequest) -> Void

    private var webViews: [UUID: WKWebView] = [:]
    private var navigationObservers: [UUID: SlotNavigationObserver] = [:]
    private var popupCoordinators: [UUID: PopupCoordinator] = [:]
    private var appliedRenderingProfiles: [UUID: WebRenderingProfile] = [:]

    private let onURLChange: @MainActor (UUID, URL) -> Void
    private let load: LoadHandler

    init(
        onURLChange: @escaping @MainActor (UUID, URL) -> Void,
        initialLoad: @escaping LoadHandler = { webView, request in
            webView.load(request)
        }
    ) {
        self.onURLChange = onURLChange
        load = initialLoad
    }

    func webView(for profile: WebAppProfile) -> WKWebView {
        let desiredRendering = profile.renderingProfile.normalized()

        if let existing = webViews[profile.id],
           let appliedRendering = appliedRenderingProfiles[profile.id] {
            if desiredRendering.requiresWebViewRebuild(comparedTo: appliedRendering) {
                let navigationURL = Self.rebuildNavigationURL(
                    initialURL: existing.backForwardList.currentItem?.initialURL,
                    visibleURL: existing.url,
                    storedCurrentURL: profile.currentURL,
                    homeURL: profile.homeURL
                )
                return rebuildWebView(
                    for: profile,
                    navigationURL: navigationURL
                )
            }

            WebViewFactory.applyRuntimeRendering(desiredRendering, to: existing)
            appliedRenderingProfiles[profile.id] = desiredRendering
            return existing
        }

        return createWebView(
            for: profile,
            navigationURL: profile.currentURL ?? profile.homeURL,
            cachePolicy: .useProtocolCachePolicy
        )
    }

    func existingWebView(for slotID: UUID) -> WKWebView? {
        webViews[slotID]
    }

    func navigate(slotID: UUID, to url: URL) {
        guard WebAppURL.isSafe(url), let webView = webViews[slotID] else { return }
        webView.load(URLRequest(url: url))
    }

    func remove(slotID: UUID) {
        discardPopupCoordinator(slotID: slotID)
        navigationObservers.removeValue(forKey: slotID)
        appliedRenderingProfiles.removeValue(forKey: slotID)
        webViews.removeValue(forKey: slotID)
    }

    func contains(slotID: UUID) -> Bool {
        webViews[slotID] != nil
    }

    var count: Int {
        webViews.count
    }

    static func rebuildNavigationURL(
        initialURL: URL?,
        visibleURL: URL?,
        storedCurrentURL: URL?,
        homeURL: URL
    ) -> URL {
        for candidate in [initialURL, visibleURL, storedCurrentURL, homeURL] {
            if let candidate, WebAppURL.isSafe(candidate) {
                return candidate
            }
        }
        return homeURL
    }

    private func rebuildWebView(
        for profile: WebAppProfile,
        navigationURL: URL
    ) -> WKWebView {
        discardPopupCoordinator(slotID: profile.id)
        navigationObservers.removeValue(forKey: profile.id)
        appliedRenderingProfiles.removeValue(forKey: profile.id)
        webViews.removeValue(forKey: profile.id)
        return createWebView(
            for: profile,
            navigationURL: navigationURL,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
    }

    private func createWebView(
        for profile: WebAppProfile,
        navigationURL: URL,
        cachePolicy: URLRequest.CachePolicy
    ) -> WKWebView {
        let rendering = profile.renderingProfile.normalized()
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let observer = SlotNavigationObserver(
            slotID: profile.id,
            webView: webView,
            websiteMode: rendering.effectiveWebsiteMode,
            onURLChange: onURLChange
        )
        let popupCoordinator = PopupCoordinator(parentWebView: webView)
        webView.uiDelegate = popupCoordinator

        webViews[profile.id] = webView
        navigationObservers[profile.id] = observer
        popupCoordinators[profile.id] = popupCoordinator
        appliedRenderingProfiles[profile.id] = rendering

        let request = URLRequest(
            url: navigationURL,
            cachePolicy: cachePolicy,
            timeoutInterval: 60
        )
        load(webView, request)
        return webView
    }

    private func discardPopupCoordinator(slotID: UUID) {
        popupCoordinators.removeValue(forKey: slotID)?.closeAll()
    }
}

enum NewBrowsingContextDisposition: Equatable {
    case currentSlot
    case temporaryPopup
    case externalBrowser
}

/// Owns temporary browsing contexts created through `target=_blank` or
/// `window.open`. The classifier deliberately uses interaction semantics rather
/// than provider-specific host lists:
///
/// - same-site HTTP(S) stays in the current Slot;
/// - a cross-site user link goes to the default browser;
/// - a cross-site scripted popup is hosted in a temporary child WKWebView;
/// - `about:blank` is a temporary popup because many auth flows create it first;
/// - non-web schemes are handed to the system.
@MainActor
final class PopupCoordinator: NSObject, WKUIDelegate, NSWindowDelegate {
    typealias ExternalOpenHandler = (URL) -> Void

    private weak var parentWebView: WKWebView?
    private var childPanels: [ObjectIdentifier: NSPanel] = [:]
    private let openExternal: ExternalOpenHandler

    init(
        parentWebView: WKWebView,
        openExternal: @escaping ExternalOpenHandler = { url in
            _ = NSWorkspace.shared.open(url)
        }
    ) {
        self.parentWebView = parentWebView
        self.openExternal = openExternal
        super.init()
    }

    static func disposition(
        navigationType: WKNavigationType,
        sourceURL: URL?,
        targetURL: URL?
    ) -> NewBrowsingContextDisposition {
        guard let targetURL else {
            return .temporaryPopup
        }

        let scheme = targetURL.scheme?.lowercased()
        if scheme == "about" {
            return .temporaryPopup
        }

        guard WebNavigationCoordinator.isWebURL(targetURL) else {
            return .externalBrowser
        }

        if WebNavigationCoordinator.isSameSite(sourceURL, targetURL) {
            return .currentSlot
        }

        return navigationType == .linkActivated
            ? .externalBrowser
            : .temporaryPopup
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let sourceURL = navigationAction.sourceFrame.request.url ?? webView.url
        let targetURL = navigationAction.request.url

        switch Self.disposition(
            navigationType: navigationAction.navigationType,
            sourceURL: sourceURL,
            targetURL: targetURL
        ) {
        case .currentSlot:
            webView.load(navigationAction.request)
            return nil

        case .externalBrowser:
            if let targetURL {
                openExternal(targetURL)
            }
            return nil

        case .temporaryPopup:
            return makeTemporaryPopup(
                sourceWebView: webView,
                configuration: configuration,
                targetURL: targetURL
            )
        }
    }

    func webViewDidClose(_ webView: WKWebView) {
        close(webView: webView, restoreFocus: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              let childWebView = panel.contentView as? WKWebView else {
            return
        }

        childPanels.removeValue(forKey: ObjectIdentifier(childWebView))
        restoreParentFocus()
    }

    func closeAll() {
        let webViews = childPanels.compactMap { _, panel in
            panel.contentView as? WKWebView
        }
        for webView in webViews {
            close(webView: webView, restoreFocus: false)
        }
    }

    private func makeTemporaryPopup(
        sourceWebView: WKWebView,
        configuration: WKWebViewConfiguration,
        targetURL: URL?
    ) -> WKWebView {
        let popupWebView = WKWebView(frame: .zero, configuration: configuration)
        popupWebView.allowsBackForwardNavigationGestures = true
        popupWebView.customUserAgent = sourceWebView.customUserAgent
        popupWebView.uiDelegate = self

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = targetURL?.host ?? "Web Login"
        panel.contentView = popupWebView
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        if let parentWindow = sourceWebView.window {
            panel.level = parentWindow.level
            panel.collectionBehavior = parentWindow.collectionBehavior
            parentWindow.addChildWindow(panel, ordered: .above)
        }

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        childPanels[ObjectIdentifier(popupWebView)] = panel
        return popupWebView
    }

    private func close(webView: WKWebView, restoreFocus: Bool) {
        guard let panel = childPanels.removeValue(forKey: ObjectIdentifier(webView)) else {
            if restoreFocus {
                restoreParentFocus()
            }
            return
        }

        if let parentWindow = parentWebView?.window {
            parentWindow.removeChildWindow(panel)
        }
        panel.orderOut(nil)
        panel.close()

        if restoreFocus {
            restoreParentFocus()
        }
    }

    private func restoreParentFocus() {
        guard let parentWebView,
              let parentWindow = parentWebView.window else {
            return
        }
        parentWindow.makeKeyAndOrderFront(nil)
        _ = parentWindow.makeFirstResponder(parentWebView)
    }
}
