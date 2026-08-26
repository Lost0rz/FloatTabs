import Foundation
import WebKit

@MainActor
final class GenericWebAdapter: WebSiteAdapter {
    let identifier = "generic"

    private let inputScoring = """
        (() => {
            let score = 0;
            const context = inputContext(element);
            if (element.tagName.toLowerCase() === 'textarea') score += 100;
            if (element.isContentEditable) score += 80;
            if (element.getAttribute('role') === 'textbox') score += 40;
            if (isInMainRegion(element)) score += 30;
            if (!isInMainRegion(element)) score -= 20;
            if (/message|prompt|ask|compose|comment|reply|write|chat/.test(context)) score += 25;
            if (isUtilityInput(element)) score -= 1000;
            if (element.closest('header, nav, aside, [role="navigation"], [role="dialog"]')) score -= 100;
            return score;
        })()
        """

    func matches(url: URL?, webView: WKWebView) async -> Bool {
        true
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
