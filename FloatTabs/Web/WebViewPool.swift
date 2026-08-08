import Foundation
import WebKit

@MainActor
final class WebViewPool {
    typealias InitialLoadHandler = (WKWebView, URL) -> Void

    private var webViews: [UUID: WKWebView] = [:]
    private var navigationObservers: [UUID: SlotNavigationObserver] = [:]
    private var appliedRenderingProfiles: [UUID: WebRenderingProfile] = [:]

    private let onURLChange: @MainActor (UUID, URL) -> Void
    private let initialLoad: InitialLoadHandler

    init(
        onURLChange: @escaping @MainActor (UUID, URL) -> Void,
        initialLoad: @escaping InitialLoadHandler = { webView, url in
            webView.load(URLRequest(url: url))
        }
    ) {
        self.onURLChange = onURLChange
        self.initialLoad = initialLoad
    }

    func webView(for profile: WebAppProfile) -> WKWebView {
        let desiredRendering = profile.renderingProfile.normalized()

        if let existing = webViews[profile.id],
           let appliedRendering = appliedRenderingProfiles[profile.id] {
            if desiredRendering.requiresWebViewRebuild(comparedTo: appliedRendering) {
                return rebuildWebView(for: profile)
            }

            WebViewFactory.applyRuntimeRendering(desiredRendering, to: existing)
            appliedRenderingProfiles[profile.id] = desiredRendering
            return existing
        }

        return createWebView(for: profile)
    }

    func existingWebView(for slotID: UUID) -> WKWebView? {
        webViews[slotID]
    }

    func navigate(slotID: UUID, to url: URL) {
        guard WebAppURL.isSafe(url), let webView = webViews[slotID] else { return }
        webView.load(URLRequest(url: url))
    }

    func remove(slotID: UUID) {
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

    private func rebuildWebView(for profile: WebAppProfile) -> WKWebView {
        navigationObservers.removeValue(forKey: profile.id)
        appliedRenderingProfiles.removeValue(forKey: profile.id)
        webViews.removeValue(forKey: profile.id)
        return createWebView(for: profile)
    }

    private func createWebView(for profile: WebAppProfile) -> WKWebView {
        let rendering = profile.renderingProfile.normalized()
        let webView = WebViewFactory.makeWebView(renderingProfile: rendering)
        let observer = SlotNavigationObserver(
            slotID: profile.id,
            webView: webView,
            websiteMode: rendering.effectiveWebsiteMode,
            onURLChange: onURLChange
        )

        webViews[profile.id] = webView
        navigationObservers[profile.id] = observer
        appliedRenderingProfiles[profile.id] = rendering

        let initialURL = profile.currentURL ?? profile.homeURL
        initialLoad(webView, initialURL)
        return webView
    }
}
