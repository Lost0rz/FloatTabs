import AppKit
import Foundation
import WebKit

enum SiteCompatibilityPolicy {
    static func runtimeRendering(
        for renderingProfile: WebRenderingProfile,
        navigationURL: URL
    ) -> WebRenderingProfile {
        let rendering = renderingProfile.normalized()
        guard rendering.browserIdentity == .automatic,
              rendering.websiteMode == .mobile,
              requiresDesktopPointerIdentity(for: navigationURL) else {
            return rendering
        }

        return rendering.settingBrowserIdentity(.macosSafari)
    }

    private static func requiresDesktopPointerIdentity(for url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "chatgpt.com"
            || host.hasSuffix(".chatgpt.com")
            || host == "chat.openai.com"
    }
}

enum WebContentRecoveryDisposition: Equatable {
    case reloadNow
    case deferUntilActivation
}

@MainActor
final class WebViewPool {
    typealias LoadHandler = (WKWebView, URLRequest) -> Void
    typealias IsSlotActiveHandler = @MainActor (UUID) -> Bool

    private var webViews: [UUID: WKWebView] = [:]
    private var navigationObservers: [UUID: SlotNavigationObserver] = [:]
    private var popupCoordinators: [UUID: PopupCoordinator] = [:]
    private var appliedRenderingProfiles: [UUID: WebRenderingProfile] = [:]
    private var lastKnownURLs: [UUID: URL] = [:]
    private var deferredReloadSlotIDs = Set<UUID>()

    private let onURLChange: @MainActor (UUID, URL) -> Void
    private let load: LoadHandler
    private let isSlotActive: IsSlotActiveHandler
    private let downloadCoordinator: DownloadCoordinator

    init(
        onURLChange: @escaping @MainActor (UUID, URL) -> Void,
        initialLoad: @escaping LoadHandler = { webView, request in
            webView.load(request)
        },
        isSlotActive: @escaping IsSlotActiveHandler = { _ in true },
        downloadCoordinator: DownloadCoordinator? = nil
    ) {
        self.onURLChange = onURLChange
        load = initialLoad
        self.isSlotActive = isSlotActive
        self.downloadCoordinator = downloadCoordinator ?? DownloadCoordinator()
    }

    func webView(for profile: WebAppProfile) -> WKWebView {
        let desiredRendering = profile.renderingProfile.normalized()

        if let existing = webViews[profile.id],
           let appliedRendering = appliedRenderingProfiles[profile.id] {
            let compatibilityURL = Self.rebuildNavigationURL(
                initialURL: nil,
                visibleURL: existing.url,
                storedCurrentURL: profile.currentURL,
                homeURL: profile.homeURL
            )
            let desiredRuntimeRendering = SiteCompatibilityPolicy.runtimeRendering(
                for: desiredRendering,
                navigationURL: compatibilityURL
            )

            if desiredRuntimeRendering.requiresWebViewRebuild(comparedTo: appliedRendering) {
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

            // Reapply the effective runtime profile, not the persisted base profile.
            // Narrow compatibility overrides such as ChatGPT Automatic+Mobile must
            // remain stable whenever a warm WKWebView is selected again.
            WebViewFactory.applyRuntimeRendering(desiredRuntimeRendering, to: existing)
            appliedRenderingProfiles[profile.id] = desiredRuntimeRendering
            recoverDeferredContentProcessIfNeeded(for: profile, in: existing)
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
        lastKnownURLs[slotID] = url
        load(webView, URLRequest(url: url))
    }

    func remove(slotID: UUID) {
        discardPopupCoordinator(slotID: slotID)
        navigationObservers.removeValue(forKey: slotID)
        appliedRenderingProfiles.removeValue(forKey: slotID)
        lastKnownURLs.removeValue(forKey: slotID)
        deferredReloadSlotIDs.remove(slotID)
        webViews[slotID]?.removeFromSuperview()
        webViews.removeValue(forKey: slotID)
    }

    func contains(slotID: UUID) -> Bool {
        webViews[slotID] != nil
    }

    var count: Int {
        webViews.count
    }

    static func recoveryDisposition(isActive: Bool) -> WebContentRecoveryDisposition {
        isActive ? .reloadNow : .deferUntilActivation
    }

    func handleContentProcessTermination(slotID: UUID) {
        guard let webView = webViews[slotID] else { return }

        switch Self.recoveryDisposition(isActive: isSlotActive(slotID)) {
        case .reloadNow:
            deferredReloadSlotIDs.remove(slotID)
            guard let recoveryURL = recoveryURL(slotID: slotID, webView: webView) else {
                deferredReloadSlotIDs.insert(slotID)
                return
            }
            lastKnownURLs[slotID] = recoveryURL
            load(webView, recoveryRequest(url: recoveryURL))

        case .deferUntilActivation:
            deferredReloadSlotIDs.insert(slotID)
        }
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
        lastKnownURLs.removeValue(forKey: profile.id)
        deferredReloadSlotIDs.remove(profile.id)
        webViews[profile.id]?.removeFromSuperview()
        webViews.removeValue(forKey: profile.id)
        return createWebView(
            for: profile,
            navigationURL: navigationURL,
            cachePolicy: .useProtocolCachePolicy
        )
    }

    private func createWebView(
        for profile: WebAppProfile,
        navigationURL: URL,
        cachePolicy: URLRequest.CachePolicy
    ) -> WKWebView {
        let rendering = profile.renderingProfile.normalized()
        let runtimeRendering = SiteCompatibilityPolicy.runtimeRendering(
            for: rendering,
            navigationURL: navigationURL
        )
        let webView = WebViewFactory.makeWebView(renderingProfile: runtimeRendering)
        let observer = SlotNavigationObserver(
            slotID: profile.id,
            webView: webView,
            websiteMode: rendering.effectiveWebsiteMode,
            downloadCoordinator: downloadCoordinator,
            onURLChange: { [weak self] slotID, url in
                guard let self else { return }
                self.lastKnownURLs[slotID] = url
                self.onURLChange(slotID, url)
            },
            onContentProcessTermination: { [weak self] slotID in
                self?.handleContentProcessTermination(slotID: slotID)
            }
        )
        let popupCoordinator = PopupCoordinator(
            parentWebView: webView,
            downloadCoordinator: downloadCoordinator
        )
        webView.uiDelegate = popupCoordinator

        webViews[profile.id] = webView
        navigationObservers[profile.id] = observer
        popupCoordinators[profile.id] = popupCoordinator
        // Store the effective runtime profile so warm-slot reuse compares against
        // the identity actually applied to this WKWebView.
        appliedRenderingProfiles[profile.id] = runtimeRendering
        lastKnownURLs[profile.id] = navigationURL
        deferredReloadSlotIDs.remove(profile.id)

        let request = URLRequest(
            url: navigationURL,
            cachePolicy: cachePolicy,
            timeoutInterval: 60
        )
        load(webView, request)
        return webView
    }

    private func recoverDeferredContentProcessIfNeeded(
        for profile: WebAppProfile,
        in webView: WKWebView
    ) {
        guard deferredReloadSlotIDs.remove(profile.id) != nil else { return }
        let navigationURL = profile.currentURL.flatMap { WebAppURL.isSafe($0) ? $0 : nil }
            ?? profile.homeURL
        lastKnownURLs[profile.id] = navigationURL
        load(webView, recoveryRequest(url: navigationURL))
    }

    private func recoveryURL(slotID: UUID, webView: WKWebView) -> URL? {
        for candidate in [lastKnownURLs[slotID], webView.url] {
            if let candidate, WebAppURL.isSafe(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func recoveryRequest(url: URL) -> URLRequest {
        URLRequest(
            url: url,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 60
        )
    }

    private func discardPopupCoordinator(slotID: UUID) {
        popupCoordinators.removeValue(forKey: slotID)?.closeAll()
    }
}


/// Keeps every warm Slot's WKWebView attached to the same AppKit window.
/// Switching Slots changes only sibling order. Existing WebViews are never
/// removed/re-added merely because another Slot becomes active, so heavy SPA
/// DOM/JS/compositor state can remain warm across ordinary Slot switches.
///
/// Stage 5 owns resource scheduling for these resident inactive views; this
/// Stage 4 boundary is intentionally about state continuity and switch latency.
@MainActor
final class WarmWebViewResidencyCoordinator {
    private unowned let container: WebPanelContainerView
    private weak var hostView: NSView?
    private weak var active: WKWebView?

    init(container: WebPanelContainerView) {
        self.container = container
    }

    var activeWebView: WKWebView? {
        active
    }

    func show(webView: WKWebView) {
        let host: NSView
        if let existingHost = hostView {
            host = existingHost
        } else {
            container.show(webView: webView)
            guard let attachedHost = webView.superview else { return }
            hostView = attachedHost
            host = attachedHost
        }

        if webView.superview !== host {
            webView.removeFromSuperview()
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.autoresizingMask = [.width, .height]
            webView.frame = host.bounds
            host.addSubview(webView)
        } else {
            webView.translatesAutoresizingMaskIntoConstraints = true
            webView.autoresizingMask = [.width, .height]
        }

        // Reordering the existing subviews keeps every resident WKWebView in the
        // same window hierarchy. AppKit moves shared views without remove/re-add.
        var orderedSubviews = host.subviews
        if let index = orderedSubviews.firstIndex(where: { $0 === webView }) {
            let selected = orderedSubviews.remove(at: index)
            orderedSubviews.append(selected)
            host.subviews = orderedSubviews
        }

        for resident in host.subviews.compactMap({ $0 as? WKWebView }) {
            resident.isHidden = false
            resident.alphaValue = 1
            resident.autoresizingMask = [.width, .height]
            if resident.frame != host.bounds {
                resident.frame = host.bounds
            }
        }

        active = webView
    }

    func showEmptyState() {
        if let hostView {
            for resident in hostView.subviews.compactMap({ $0 as? WKWebView }) {
                resident.removeFromSuperview()
            }
        }
        active = nil
        hostView = nil
        container.showEmptyState()
    }
}
