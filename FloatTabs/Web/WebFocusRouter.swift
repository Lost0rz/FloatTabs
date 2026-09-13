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
    private let diagnostics: any RuntimeDiagnosticRecording
    private let logger = Logger(subsystem: "com.lost0rz.FloatTabs", category: "WebFocus")

    var onTransition: ((WebFocusTransition) -> Void)?

    init(
        registry: WebSiteAdapterRegistry = WebSiteAdapterRegistry(),
        diagnostics: any RuntimeDiagnosticRecording = RuntimeDiagnosticNoopRecorder()
    ) {
        self.registry = registry
        self.diagnostics = diagnostics
    }

    func setCurrentWebView(_ webView: WKWebView?) {
        guard currentWebView !== webView else { return }
        diagnostics.record(
            event: "web_focus.webview_changed",
            level: .debug,
            subsystem: "focus",
            fields: ["has_webview": .bool(webView != nil)]
        )
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
            diagnostics.record(
                event: "web_focus.recognition",
                level: .debug,
                subsystem: "focus",
                fields: [
                    "site": .string(adapter.identifier),
                    "target": .string(currentTarget.rawValue),
                    "success": .bool(true)
                ]
            )
        } catch {
            currentTarget = .unavailable
            var fields = RuntimeDiagnosticPrivacy.sanitizedErrorCategory(error)
            fields["success"] = .bool(false)
            diagnostics.record(
                event: "web_focus.recognition",
                level: .warning,
                subsystem: "focus",
                fields: fields
            )
        }
    }

    /// Initialize the website's primary input focus after FloatTabs is
    /// presented from another application. Native NSWindow focus alone is not
    /// enough for WebKit: keyboard navigation can remain associated with the
    /// previously active application until the page has a DOM input focus.
    @discardableResult
    func captureInputTargetForExternalVoice() async -> Bool {
        guard let webView = currentWebView else { return false }
        let adapter = await registry.adapter(for: webView.url, webView: webView)
        currentAdapter = adapter
        currentWebsiteIdentifier = adapter.identifier
        do {
            let captured = try await adapter.captureInputTargetForVoice(in: webView)
            logger.debug(
                "voice focus target captured=\(captured, privacy: .public) site=\(adapter.identifier, privacy: .public)"
            )
            diagnostics.record(
                event: "web_focus.capture_voice_target",
                level: .info,
                subsystem: "focus",
                fields: [
                    "site": .string(adapter.identifier),
                    "captured": .bool(captured)
                ]
            )
            return captured
        } catch {
            logger.error(
                "voice focus target capture failed site=\(adapter.identifier, privacy: .public) reason=\(error.localizedDescription, privacy: .public)"
            )
            diagnostics.record(
                event: "web_focus.failed",
                level: .warning,
                subsystem: "focus",
                fields: RuntimeDiagnosticPrivacy.sanitizedErrorCategory(error)
            )
            return false
        }
    }

    func focusInputForPresentation(
        preservingCapturedTarget: Bool = false
    ) async -> Bool {
        guard let webView = currentWebView else { return false }

        // inputFocusScript checks and reuses the active non-utility editor in
        // the same WebKit evaluation. Avoid the former currentFocus + focus
        // pair: the extra IPC round trip was visible on the first voice press
        // after a page scroll or a long idle period.
        let adapter = await registry.adapter(for: webView.url, webView: webView)
        currentAdapter = adapter
        currentWebsiteIdentifier = adapter.identifier
        do {
            if preservingCapturedTarget {
                try await adapter.focusInputForVoice(in: webView)
            } else {
                try await adapter.focusInput(in: webView)
            }
            currentTarget = .input
            logger.debug(
                "voice focus restored captured=\(preservingCapturedTarget, privacy: .public) site=\(adapter.identifier, privacy: .public)"
            )
            diagnostics.record(
                event: "web_focus.presentation.completed",
                level: .info,
                subsystem: "focus",
                fields: [
                    "site": .string(adapter.identifier),
                    "preserved_capture": .bool(preservingCapturedTarget)
                ]
            )
            return true
        } catch {
            logger.error(
                "voice focus restore failed captured=\(preservingCapturedTarget, privacy: .public) site=\(adapter.identifier, privacy: .public) reason=\(error.localizedDescription, privacy: .public)"
            )
            diagnostics.record(
                event: "web_focus.failed",
                level: .warning,
                subsystem: "focus",
                fields: RuntimeDiagnosticPrivacy.sanitizedErrorCategory(error)
            )
            return false
        }
    }

    /// Verifies the current DOM target without moving focus again. Callers
    /// combine this with native key-window/first-responder checks before they
    /// acknowledge an external voice request.
    func isInputFocusReady() async -> Bool {
        guard let webView = currentWebView else { return false }
        let adapter = await registry.adapter(for: webView.url, webView: webView)
        currentAdapter = adapter
        currentWebsiteIdentifier = adapter.identifier
        do {
            let target = try await adapter.currentFocus(in: webView)
            currentTarget = target
            return target == .input
        } catch {
            currentTarget = .unavailable
            return false
        }
    }

    @discardableResult
    func togglePrimaryFocus(trace: RuntimeDiagnosticTrace? = nil) async -> WebFocusTransition {
        guard let webView = currentWebView else {
            return recordFailure(
                websiteIdentifier: currentWebsiteIdentifier ?? "unavailable",
                from: currentTarget,
                to: .unavailable,
                error: WebFocusAdapterError.noWebView,
                trace: trace
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
                to: focused,
                trace: trace
            )
        } catch {
            currentTarget = .unavailable
            return recordFailure(
                websiteIdentifier: adapter.identifier,
                from: from,
                to: destination,
                error: error,
                trace: trace
            )
        }
    }

    private func recordSuccess(
        websiteIdentifier: String,
        from: WebFocusTarget,
        to: WebFocusTarget,
        trace: RuntimeDiagnosticTrace?
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
        diagnostics.record(
            event: "web_focus.toggle",
            level: .info,
            subsystem: "focus",
            trace: trace,
            fields: [
                "site": .string(websiteIdentifier),
                "from": .string(from.rawValue),
                "to": .string(to.rawValue),
                "success": .bool(true)
            ]
        )
        onTransition?(transition)
        return transition
    }

    private func recordFailure(
        websiteIdentifier: String,
        from: WebFocusTarget,
        to: WebFocusTarget,
        error: Error,
        trace: RuntimeDiagnosticTrace?
    ) -> WebFocusTransition {
        let transition = WebFocusTransition(
            websiteIdentifier: websiteIdentifier,
            from: from,
            to: to,
            succeeded: false,
            failureReason: error.localizedDescription
        )
        logger.error(
            "focus toggle site=\(websiteIdentifier, privacy: .public) from=\(from.rawValue, privacy: .public) to=\(to.rawValue, privacy: .public) success=false category=\(Self.errorCategory(error), privacy: .public)"
        )
        var fields = RuntimeDiagnosticPrivacy.sanitizedErrorCategory(error)
        fields["site"] = .string(websiteIdentifier)
        fields["from"] = .string(from.rawValue)
        fields["to"] = .string(to.rawValue)
        fields["success"] = .bool(false)
        diagnostics.record(
            event: "web_focus.toggle",
            level: .warning,
            subsystem: "focus",
            trace: trace,
            fields: fields
        )
        diagnostics.record(
            event: "web_focus.failed",
            level: .warning,
            subsystem: "focus",
            trace: trace,
            fields: fields
        )
        onTransition?(transition)
        return transition
    }

    private static func errorCategory(_ error: Error) -> String {
        guard let value = RuntimeDiagnosticPrivacy.sanitizedErrorCategory(error)["error_category"] else {
            return "runtime"
        }
        if case let .string(category) = value {
            return category
        }
        return "runtime"
    }
}
