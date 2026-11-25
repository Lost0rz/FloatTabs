import Foundation
import WebKit

enum WebNavigationDisposition: Equatable {
    case allow
    case loadInCurrentSlot
}

/// Owns navigation-policy decisions independently from per-Slot WebView
/// lifecycle observation.
@MainActor
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
        // `sourceURL` remains part of the policy seam because popup callers and
        // deterministic tests carry origin context. Ordinary user routing does
        // not compare source/target hosts: destination is selected by user intent.
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

    nonisolated static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Preserves the HTTP `Referer` header under `strict-origin-when-cross-origin`
    /// when FloatTabs converts a new-context request into an explicit same-Slot load.
    static func requestPreservingReferrer(
        _ request: URLRequest,
        sourceURL: URL?
    ) -> URLRequest {
        guard request.value(forHTTPHeaderField: "Referer") == nil,
              let sourceURL,
              isWebURL(sourceURL),
              let targetURL = request.url,
              isWebURL(targetURL) else {
            return request
        }

        guard var sourceComponents = URLComponents(
            url: sourceURL,
            resolvingAgainstBaseURL: false
        ),
              let sourceScheme = sourceComponents.scheme?.lowercased(),
              let sourceHost = sourceComponents.host?.lowercased(),
              !sourceHost.isEmpty,
              let targetComponents = URLComponents(
                url: targetURL,
                resolvingAgainstBaseURL: false
              ),
              let targetScheme = targetComponents.scheme?.lowercased(),
              let targetHost = targetComponents.host?.lowercased(),
              !targetHost.isEmpty else {
            return request
        }

        // Never downgrade an HTTPS referrer onto an insecure HTTP destination.
        if sourceScheme == "https" && targetScheme == "http" {
            return request
        }

        sourceComponents.user = nil
        sourceComponents.password = nil
        sourceComponents.fragment = nil
        sourceComponents.scheme = sourceScheme
        sourceComponents.host = sourceHost

        func effectivePort(scheme: String, port: Int?) -> Int? {
            if let port { return port }
            switch scheme {
            case "http": return 80
            case "https": return 443
            default: return nil
            }
        }

        let sameOrigin = sourceScheme == targetScheme
            && sourceHost == targetHost
            && effectivePort(scheme: sourceScheme, port: sourceComponents.port)
                == effectivePort(scheme: targetScheme, port: targetComponents.port)

        let refererValue: String?
        if sameOrigin {
            refererValue = sourceComponents.url?.absoluteString
        } else {
            var originComponents = URLComponents()
            originComponents.scheme = sourceScheme
            originComponents.host = sourceHost
            originComponents.port = sourceComponents.port
            originComponents.path = "/"
            refererValue = originComponents.url?.absoluteString
        }

        guard let refererValue else { return request }
        var updated = request
        updated.setValue(refererValue, forHTTPHeaderField: "Referer")
        return updated
    }
}
