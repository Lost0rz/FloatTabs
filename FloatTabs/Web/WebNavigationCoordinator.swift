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
            navigationType: navigationAction.navigationType,
            sourceURL: navigationAction.sourceFrame.request.url,
            targetURL: navigationAction.request.url
        )
    }

    /// Navigation Intent policy for new browsing contexts.
    ///
    /// Ordinary user HTTP(S) links remain in the persistent Slot regardless of
    /// host. Script-created contexts are allowed through to `WKUIDelegate`,
    /// where popup/OAuth semantics are preserved. This deliberately removes
    /// host comparison from the ordinary user-navigation boundary.
    static func disposition(
        hasTargetFrame: Bool,
        navigationType: WKNavigationType = .linkActivated,
        sourceURL: URL?,
        targetURL: URL?
    ) -> WebNavigationDisposition {
        // `sourceURL` is retained in this seam because popup policy and tests
        // still provide origin context, but ordinary user routing intentionally
        // does not compare source/target hosts. Destination is chosen by user
        // intent, not by same-site/cross-site classification.
        _ = sourceURL

        guard !hasTargetFrame,
              let targetURL,
              isWebURL(targetURL) else {
            return .allow
        }

        return navigationType == .linkActivated
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
