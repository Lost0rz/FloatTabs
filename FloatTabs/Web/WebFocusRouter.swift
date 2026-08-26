import Combine
import OSLog
import WebKit

@MainActor
final class WebFocusRouter: ObservableObject {
    @Published private(set) var currentTarget: WebFocusTarget = .unavailable
    @Published private(set) var currentWebsiteIdentifier: String?

    private(set) weak var currentWebView: WKWebView?
    private(set) var currentAdapter: (any WebSiteAdapter)?
    private let registry: WebSiteAdapterRegistry
    private let logger = Logger(subsystem: "com.lost0rz.FloatTabs", category: "WebFocus")

    var onTransition: ((WebFocusTransition) -> Void)?

    init(registry: WebSiteAdapterRegistry = WebSiteAdapterRegistry()) {
        self.registry = registry
    }

    func setCurrentWebView(_ webView: WKWebView?) {
        guard currentWebView !== webView else { return }
        currentWebView = webView
        currentAdapter = nil
        currentWebsiteIdentifier = nil
        currentTarget = .unavailable

        guard let webView else { return }
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            await self.refreshRecognition(for: webView)
        }
    }

    /// Re-identifies the adapter and DOM on navigation/SPA transitions. The
    /// toggle path also calls this implicitly, so a refresh never depends on a
    /// stale DOM node or a stale adapter decision.
    func refreshRecognition() async {
        guard let webView = currentWebView else {
            currentAdapter = nil
            currentWebsiteIdentifier = nil
            currentTarget = .unavailable
            return
        }
        await refreshRecognition(for: webView)
    }

    func refreshRecognition(for webView: WKWebView) async {
        guard currentWebView === webView else { return }
        let adapter = await registry.adapter(for: webView.url, webView: webView)
        currentAdapter = adapter
        currentWebsiteIdentifier = adapter.identifier
        do {
            currentTarget = try await adapter.currentFocus(in: webView)
        } catch {
            currentTarget = .unavailable
        }
    }

    @discardableResult
    func togglePrimaryFocus() async -> WebFocusTransition {
        guard let webView = currentWebView else {
            return recordFailure(
                websiteIdentifier: currentWebsiteIdentifier ?? "unavailable",
                from: currentTarget,
                to: .unavailable,
                reason: WebFocusAdapterError.noWebView.localizedDescription
            )
        }

        let adapter = await registry.adapter(for: webView.url, webView: webView)
        currentAdapter = adapter
        currentWebsiteIdentifier = adapter.identifier

        let from: WebFocusTarget
        do {
            from = try await adapter.currentFocus(in: webView)
        } catch {
            from = .unavailable
        }
        currentTarget = from

        // An unclear or non-primary focus always defaults to the input. This
        // keeps the first invocation useful after load, refresh, or tab switch.
        let destination: WebFocusTarget = from == .input ? .page : .input
        do {
            let focused = try await adapter.togglePrimaryFocus(in: webView)
            currentTarget = focused
            return recordSuccess(
                websiteIdentifier: adapter.identifier,
                from: from,
                to: focused
            )
        } catch {
            currentTarget = .unavailable
            return recordFailure(
                websiteIdentifier: adapter.identifier,
                from: from,
                to: destination,
                reason: error.localizedDescription
            )
        }
    }

    private func recordSuccess(
        websiteIdentifier: String,
        from: WebFocusTarget,
        to: WebFocusTarget
    ) -> WebFocusTransition {
        let transition = WebFocusTransition(
            websiteIdentifier: websiteIdentifier,
            from: from,
            to: to,
            succeeded: true,
            failureReason: nil
        )
        logger.info(
            "focus toggle site=\(websiteIdentifier, privacy: .public) from=\(from.rawValue, privacy: .public) to=\(to.rawValue, privacy: .public) success=true"
        )
        onTransition?(transition)
        return transition
    }

    private func recordFailure(
        websiteIdentifier: String,
        from: WebFocusTarget,
        to: WebFocusTarget,
        reason: String
    ) -> WebFocusTransition {
        let transition = WebFocusTransition(
            websiteIdentifier: websiteIdentifier,
            from: from,
            to: to,
            succeeded: false,
            failureReason: reason
        )
        logger.error(
            "focus toggle site=\(websiteIdentifier, privacy: .public) from=\(from.rawValue, privacy: .public) to=\(to.rawValue, privacy: .public) success=false reason=\(reason, privacy: .public)"
        )
        onTransition?(transition)
        return transition
    }
}
