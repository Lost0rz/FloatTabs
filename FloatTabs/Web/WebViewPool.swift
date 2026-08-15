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
    typealias LoadHandler = @MainActor (WKWebView, URLRequest) -> Void
    typealias IsSlotActiveHandler = @MainActor (UUID) -> Bool

    private final class WeakHotHostOwner {
        weak var container: WebPanelContainerView?

        init(_ container: WebPanelContainerView) {
            self.container = container
        }
    }

    private var webViews: [UUID: WKWebView] = [:]
    private var navigationObservers: [UUID: SlotNavigationObserver] = [:]
    private var popupCoordinators: [UUID: PopupCoordinator] = [:]
    private var appliedRenderingProfiles: [UUID: WebRenderingProfile] = [:]
    private var lastKnownURLs: [UUID: URL] = [:]
    private var deferredReloadSlotIDs = Set<UUID>()
    private var hotHostOwners: [UUID: [ObjectIdentifier: WeakHotHostOwner]] = [:]

    var onResidentSetChange: (() -> Void)?

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
            // Remember every dedicated Hot host this runtime has physically used.
            // A Slot can move between the normal shell and fullscreen companion,
            // leaving the previous container with a reusable host that no longer
            // owns the WKWebView. Weak owner tracking lets later policy/release
            // cleanup remove both the physical owner and any such stale host.
            rememberHotHostOwnerIfNeeded(existing, slotID: profile.id)
            if profile.residencyPolicy != .hot {
                removeKnownHotHostOwnership(existing, slotID: profile.id)
            }

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
            // remain stable when a warm WKWebView is detached and later reused.
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

    /// Starts a FloatTabs-owned top-level navigation. HTTP fallback is opt-in
    /// and must come from raw user-entry provenance; the default is deliberately
    /// false so page-derived URLs, explicit HTTPS, redirects, and ordinary
    /// programmatic navigation never gain downgrade permission accidentally.
    func navigate(
        slotID: UUID,
        to url: URL,
        allowHTTPEntryFallback: Bool = false
    ) {
        guard WebAppURL.isSafe(url), let webView = webViews[slotID] else { return }
        lastKnownURLs[slotID] = url
        navigationObservers[slotID]?.configureHTTPEntryFallback(
            for: url,
            allowed: allowHTTPEntryFallback
        )
        load(webView, URLRequest(url: url))
    }

    /// Whether the current entry load of a Slot is eligible for the one-shot
    /// https → http fallback (see `SlotNavigationObserver`). Diagnostic seam
    /// used by tests.
    func isHTTPEntryFallbackPending(slotID: UUID) -> Bool {
        navigationObservers[slotID]?.isHTTPEntryFallbackPending ?? false
    }

    @discardableResult
    func reload(slotID: UUID) -> Bool {
        guard let webView = webViews[slotID] else { return false }
        webView.reload()
        return true
    }

    func remove(slotID: UUID) {
        release(slotID: slotID)
    }

    /// Releases only the transient live WebView/runtime state for a Slot. The
    /// persisted WebAppProfile, currentURL, cookies and shared website data stay
    /// outside this pool and therefore survive Cold eviction.
    func release(slotID: UUID) {
        discardPopupCoordinator(slotID: slotID)
        navigationObservers.removeValue(forKey: slotID)
        appliedRenderingProfiles.removeValue(forKey: slotID)
        lastKnownURLs.removeValue(forKey: slotID)
        deferredReloadSlotIDs.remove(slotID)
        let removed = webViews.removeValue(forKey: slotID)
        if let removed {
            rememberHotHostOwnerIfNeeded(removed, slotID: slotID)
            removeKnownHotHostOwnership(removed, slotID: slotID)
            removed.removeFromSuperview()
        } else {
            hotHostOwners.removeValue(forKey: slotID)
        }
        if removed != nil {
            onResidentSetChange?()
        }
    }

    /// Pauses currently playing media without putting the page into WebKit's
    /// stronger suspended state. A paused page remains user-resumable when the
    /// Slot becomes active again.
    func pauseMediaPlayback(slotID: UUID) {
        guard let webView = webViews[slotID] else { return }
        webView.pauseAllMediaPlayback(completionHandler: nil)
    }

    func isMediaPlaying(slotID: UUID, completion: @escaping (Bool) -> Void) {
        guard let webView = webViews[slotID] else {
            completion(false)
            return
        }
        webView.requestMediaPlaybackState { state in
            completion(state == .playing)
        }
    }

    func contains(slotID: UUID) -> Bool {
        webViews[slotID] != nil
    }

    var count: Int {
        webViews.count
    }

    var residentSlotIDs: Set<UUID> {
        Set(webViews.keys)
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
        let replaced = webViews.removeValue(forKey: profile.id)
        if let replaced {
            rememberHotHostOwnerIfNeeded(replaced, slotID: profile.id)
            removeKnownHotHostOwnership(replaced, slotID: profile.id)
            replaced.removeFromSuperview()
        } else {
            hotHostOwners.removeValue(forKey: profile.id)
        }

        // A rendering-profile rebuild replaces the transient runtime for the same
        // resident Slot. Do not emit a resident-set change merely because the
        // dictionary entry is recreated; callers observe residency identity, not
        // WKWebView object identity.
        return createWebView(
            for: profile,
            navigationURL: navigationURL,
            cachePolicy: .useProtocolCachePolicy,
            notifyResidentSetChange: false
        )
    }

    private func createWebView(
        for profile: WebAppProfile,
        navigationURL: URL,
        cachePolicy: URLRequest.CachePolicy,
        notifyResidentSetChange: Bool = true
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

        let wasResident = webViews[profile.id] != nil
        hotHostOwners.removeValue(forKey: profile.id)
        webViews[profile.id] = webView
        navigationObservers[profile.id] = observer
        popupCoordinators[profile.id] = popupCoordinator

        // A recreated runtime may inherit `currentURL` from arbitrary page
        // navigation. Only the configured Home URL can reuse persisted entry
        // provenance; an internal currentURL must never become a fresh downgrade
        // candidate merely because a Cold eviction or rendering rebuild occurred.
        let isConfiguredHomeEntry = navigationURL == profile.homeURL
        observer.configureHTTPEntryFallback(
            for: navigationURL,
            allowed: isConfiguredHomeEntry && profile.homeURLSchemeWasInferred
        )

        // Store the effective runtime profile so warm-slot reuse compares against
        // the identity actually applied to this WKWebView.
        appliedRenderingProfiles[profile.id] = runtimeRendering
        lastKnownURLs[profile.id] = navigationURL
        deferredReloadSlotIDs.remove(profile.id)
        if notifyResidentSetChange, !wasResident {
            onResidentSetChange?()
        }

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

    private func rememberHotHostOwnerIfNeeded(_ webView: WKWebView, slotID: UUID) {
        guard let host = webView.superview as? WebSlotHostView,
              let container = host.superview?.superview as? WebPanelContainerView else {
            return
        }
        let key = ObjectIdentifier(container)
        var owners = hotHostOwners[slotID] ?? [:]
        owners[key] = WeakHotHostOwner(container)
        hotHostOwners[slotID] = owners
    }

    /// Clears every container this runtime has used as a dedicated Hot host.
    /// Only weak container references are retained. WebKit's private fullscreen
    /// superviews are never registered because they are not WebSlotHostView.
    private func removeKnownHotHostOwnership(_ webView: WKWebView, slotID: UUID) {
        rememberHotHostOwnerIfNeeded(webView, slotID: slotID)
        let owners = hotHostOwners.removeValue(forKey: slotID)?.values ?? []
        for owner in owners {
            owner.container?.removeSlot(slotID)
        }

        // Defensive fallback for a dedicated host whose container hierarchy was
        // changed before it could be registered. Never touches a WebKit-private
        // fullscreen superview because of the WebSlotHostView type check.
        if let host = webView.superview as? WebSlotHostView {
            if let container = host.superview?.superview as? WebPanelContainerView {
                container.removeSlot(slotID)
            } else {
                webView.removeFromSuperview()
                host.removeFromSuperview()
            }
        }
    }

    private func discardPopupCoordinator(slotID: UUID) {
        popupCoordinators.removeValue(forKey: slotID)?.closeAll()
    }
}
