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
