import Foundation
import WebKit

@MainActor
final class WebViewPool {
    typealias InitialLoadHandler = (WKWebView, URL) -> Void

    private var webViews: [UUID: WKWebView] = [:]
    private var navigationObservers: [UUID: SlotNavigationObserver] = [:]

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
        if let existing = webViews[profile.id] {
            return existing
        }

        let webView = WebViewFactory.makeWebView()
        let observer = SlotNavigationObserver(
            slotID: profile.id,
            webView: webView,
            onURLChange: onURLChange
        )

        webViews[profile.id] = webView
        navigationObservers[profile.id] = observer

        let initialURL = profile.currentURL ?? profile.homeURL
        initialLoad(webView, initialURL)
        return webView
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
        webViews.removeValue(forKey: slotID)
    }

    func contains(slotID: UUID) -> Bool {
        webViews[slotID] != nil
    }

    var count: Int {
        webViews.count
    }
}
