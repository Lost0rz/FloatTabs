import Foundation
import WebKit

@MainActor
final class ChatGPTAdapter: WebSiteAdapter {
    let identifier = "chatgpt"

    private static let supportedHosts: Set<String> = [
        "chatgpt.com",
        "www.chatgpt.com",
        "chat.openai.com",
    ]

    private let inputScoring = """
        (() => {
            let score = 0;
            const context = inputContext(element);
            if (element.tagName.toLowerCase() === 'textarea') score += 100;
            if (element.isContentEditable) score += 90;
            if (element.getAttribute('role') === 'textbox') score += 45;
            if (isInMainRegion(element)) score += 45;
            if (/message chatgpt|message|ask anything|ask chatgpt|prompt|reply/.test(context)) score += 120;
            if (/search|address|url|setting|find in page|navigate/.test(context)) score -= 1000;
            if (element.getAttribute('type') === 'search') score -= 1000;
            if (element.closest('header, nav, aside, [role="navigation"], [role="dialog"]')) score -= 160;
            return score;
        })()
        """

    func matches(url: URL?, webView: WKWebView) async -> Bool {
        if let host = url?.host?.lowercased(), Self.supportedHosts.contains(host) {
            return true
        }

        // URL host is authoritative when available. The DOM fallback is only
        // used while WebKit has not exposed a URL yet, and still requires a
        // ChatGPT-like composer plus a ChatGPT host in document.location.
        guard url == nil else { return false }
        let script = """
        (() => {
            const host = (window.location.hostname || '').toLowerCase();
            const isChatHost = host === 'chatgpt.com'
                || host === 'www.chatgpt.com'
                || host === 'chat.openai.com';
            const composer = Array.from(document.querySelectorAll(
                'textarea, [contenteditable="true"], [role="textbox"]'
            )).some((element) => {
                const text = [
                    element.getAttribute('aria-label') || '',
                    element.getAttribute('placeholder') || ''
                ].join(' ').toLowerCase();
                return /message chatgpt|ask anything|ask chatgpt/.test(text);
            });
            return isChatHost && composer;
        })()
        """

        do {
            let value: Any = try await withCheckedThrowingContinuation { continuation in
                webView.evaluateJavaScript(script) { value, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: value ?? false)
                    }
                }
            }
            return (value as? Bool) ?? false
        } catch {
            return false
        }
    }

    func togglePrimaryFocus(in webView: WKWebView) async throws -> WebFocusTarget {
        let current = try await currentFocus(in: webView)
        if current == .input {
            try await focusPage(in: webView)
            return .page
        }
        try await focusInput(in: webView)
        return .input
    }

    func focusInput(in webView: WKWebView) async throws {
        let result = try await WebFocusDOM.evaluate(
            WebFocusDOM.inputFocusScript(scoring: inputScoring),
            in: webView
        )
        guard WebFocusDOM.succeeded(result) else {
            throw WebFocusAdapterError.inputUnavailable
        }
    }

    func focusPage(in webView: WKWebView) async throws {
        let result = try await WebFocusDOM.evaluate(
            WebFocusDOM.pageFocusScript(),
            in: webView
        )
        guard WebFocusDOM.succeeded(result) else {
            throw WebFocusAdapterError.pageUnavailable
        }
    }

    func currentFocus(in webView: WKWebView) async throws -> WebFocusTarget {
        let result = try await WebFocusDOM.evaluate(
            WebFocusDOM.currentFocusScript(),
            in: webView
        )
        return WebFocusDOM.resultTarget(from: result)
    }
}
