import Foundation
import WebKit

enum WebNavigationDisposition: Equatable {
    case allow
    case loadInCurrentSlot
}

/// Owns navigation-policy decisions independently from per-Slot WebView
/// lifecycle observation.
final class WebNavigationCoordinator {
    func disposition(for navigationAction: WKNavigationAction) -> WebNavigationDisposition {
        Self.disposition(
            hasTargetFrame: navigationAction.targetFrame != nil,
            sourceURL: navigationAction.sourceFrame.request.url,
            targetURL: navigationAction.request.url
        )
    }

    /// Stage 4B production policy for new browsing contexts.
    ///
    /// Same-site HTTP(S) links continue in the persistent Slot. Cross-site and
    /// non-web new contexts are allowed through so `WKUIDelegate` can classify
    /// them as temporary popups or external-browser handoffs.
    static func disposition(
        hasTargetFrame: Bool,
        sourceURL: URL?,
        targetURL: URL?
    ) -> WebNavigationDisposition {
        guard !hasTargetFrame,
              let targetURL,
              isWebURL(targetURL) else {
            return .allow
        }

        return isSameSite(sourceURL, targetURL)
            ? .loadInCurrentSlot
            : .allow
    }

    /// Preserves the accepted Stage 3 regression seam while its historical test
    /// still asserts the old all-HTTP(S) current-Slot fallback directly.
    static func stage3FallbackDisposition(
        hasTargetFrame: Bool,
        url: URL?
    ) -> WebNavigationDisposition {
        guard !hasTargetFrame,
              let url,
              isWebURL(url) else {
            return .allow
        }
        return .loadInCurrentSlot
    }

    static func isSameSite(_ first: URL?, _ second: URL?) -> Bool {
        guard let firstHost = normalizedHost(first),
              let secondHost = normalizedHost(second) else {
            return false
        }
        return firstHost == secondHost
    }

    static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func normalizedHost(_ url: URL?) -> String? {
        guard var host = url?.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        return host
    }
}
