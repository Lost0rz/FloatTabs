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
        return ChatGPTSitePolicy.isSupportedHost(host)
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
    typealias AttentionObservationHandler = @MainActor (UUID, ChatGPTAttentionObservation) -> Void
    typealias CommittedURLChangeHandler = @MainActor (UUID, URL) -> Void
    typealias CommittedURLProvider = @MainActor (WKWebView) -> URL?

    private var webViews: [UUID: WKWebView] = [:]
    private var navigationObservers: [UUID: SlotNavigationObserver] = [:]
    private var popupCoordinators: [UUID: PopupCoordinator] = [:]
    private var attentionBridges: [UUID: ChatGPTAttentionBridge] = [:]
    private var appliedRenderingProfiles: [UUID: WebRenderingProfile] = [:]
    private var lastKnownURLs: [UUID: URL] = [:]
    private var deferredReloadSlotIDs = Set<UUID>()

    var onResidentSetChange: (() -> Void)?

    /// Transient normalized-observation seam for later stages. The pool keeps
    /// no attention state here and assigns no visibility meaning.
    var onAttentionObservation: AttentionObservationHandler?

    /// Transient presentation seam for the selected Slot's committed
    /// top-level URL. Persistence continues to use `onURLChange`; this route
    /// exists only so presentation owners can project the current-site favicon.
    var onCommittedURLChange: CommittedURLChangeHandler?

    private let onURLChange: @MainActor (UUID, URL) -> Void
    private let load: LoadHandler
    private let isSlotActive: IsSlotActiveHandler
    private let downloadCoordinator: DownloadCoordinator
    // Production leaves this nil and reads WKWebView history directly. The
    // optional seam lets tests model a committed history item without network
    // or WebKit process timing.
    private let committedURLProvider: CommittedURLProvider?

    init(
        onURLChange: @escaping @MainActor (UUID, URL) -> Void,
        initialLoad: @escaping LoadHandler = { webView, request in
            webView.load(request)
        },
        isSlotActive: @escaping IsSlotActiveHandler = { _ in true },
        downloadCoordinator: DownloadCoordinator? = nil,
        committedURLProvider: CommittedURLProvider? = nil
    ) {
        self.onURLChange = onURLChange
        load = initialLoad
        self.isSlotActive = isSlotActive
        self.downloadCoordinator = downloadCoordinator ?? DownloadCoordinator()
        self.committedURLProvider = committedURLProvider
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

    /// Returns the URL of the live WebKit history item that most recently
    /// committed for this Slot. A persisted `currentURL` or a load request is
    /// deliberately not considered committed presentation state.
    func committedURL(for slotID: UUID) -> URL? {
        guard let webView = webViews[slotID],
              let url = committedURLProvider?(webView)
                ?? webView.backForwardList.currentItem?.url,
              WebAppURL.isSafe(url) else {
            return nil
        }
        return url
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
        // The bridge dies with its WKWebView: invalidate it first so no stale
        // callback can arrive after the runtime is dropped.
        invalidateAttentionBridge(slotID: slotID)
        discardPopupCoordinator(slotID: slotID)
        navigationObservers.removeValue(forKey: slotID)
        appliedRenderingProfiles.removeValue(forKey: slotID)
        lastKnownURLs.removeValue(forKey: slotID)
        deferredReloadSlotIDs.remove(slotID)
        let removed = webViews.removeValue(forKey: slotID)
        removed?.removeFromSuperview()
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

    /// Read-only access to the Slot's live bridge. Diagnostic/test seam for
    /// bridge lifetime ownership; no attention state lives in the pool.
    func attentionBridge(for slotID: UUID) -> ChatGPTAttentionBridge? {
        attentionBridges[slotID]
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

        // The terminated runtime is authoritatively replaced: reset its
        // attention runtime before the existing recovery policy proceeds. The
        // bridge installation itself stays usable for the recovered document.
        attentionBridges[slotID]?.handleRuntimeReplacement()

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
        invalidateAttentionBridge(slotID: profile.id)
        discardPopupCoordinator(slotID: profile.id)
        navigationObservers.removeValue(forKey: profile.id)
        appliedRenderingProfiles.removeValue(forKey: profile.id)
        lastKnownURLs.removeValue(forKey: profile.id)
        deferredReloadSlotIDs.remove(profile.id)
        let replaced = webViews.removeValue(forKey: profile.id)
        replaced?.removeFromSuperview()

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
        // The bridge exists before its WKWebView: the Factory invokes
        // `install(into:)` on the pre-creation user content controller so the
        // document-start script is present for the very first load.
        let attentionBridge = ChatGPTAttentionBridge(slotID: profile.id) { [weak self] slotID, observation in
            self?.onAttentionObservation?(slotID, observation)
        }
        let webView = WebViewFactory.makeWebView(
            renderingProfile: runtimeRendering,
            configureUserContentController: { userContentController in
                attentionBridge.install(into: userContentController)
            }
        )
        attentionBridge.attach(to: webView)
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
            },
            onNavigationCommit: { [weak self, weak attentionBridge, weak webView] slotID, commitURL in
                guard let self,
                      let webView,
                      self.existingWebView(for: slotID) === webView else {
                    return
                }
                let committedURL = self.committedURL(for: slotID)
                attentionBridge?.cancelInstantBackHandoff()
                attentionBridge?.handleRuntimeReplacement(committedURL: commitURL)
                guard let committedURL else {
                    return
                }
                self.onCommittedURLChange?(slotID, committedURL)
            },
            onInstantBackRequest: { [weak self, weak attentionBridge, weak webView] slotID, targetURL in
                guard let self,
                      let webView,
                      self.existingWebView(for: slotID) === webView else {
                    return
                }
                attentionBridge?.beginInstantBackHandoff(targetURL: targetURL)
            },
            onInstantBackCancellation: { [weak self, weak attentionBridge, weak webView] slotID in
                guard let self,
                      let webView,
                      self.existingWebView(for: slotID) === webView else {
                    return
                }
                attentionBridge?.cancelInstantBackHandoff()
            },
            onInstantBackActivation: { [weak self, weak webView] slotID in
                guard let self,
                      let webView,
                      self.existingWebView(for: slotID) === webView else {
                    return
                }
                self.attentionBridges[slotID]?.confirmInstantBackHandoff()
                // Confirmed Instant Back resets and resyncs through the bridge
                // handoff, but it must not reuse ordinary didCommit projection
                // semantics or create a duplicate replacement boundary.
                guard let committedURL = self.committedURL(for: slotID) else {
                    return
                }
                self.onCommittedURLChange?(slotID, committedURL)
            }
        )
        let popupCoordinator = PopupCoordinator(
            parentWebView: webView,
            downloadCoordinator: downloadCoordinator
        )
        webView.uiDelegate = popupCoordinator

        let wasResident = webViews[profile.id] != nil
        webViews[profile.id] = webView
        navigationObservers[profile.id] = observer
        popupCoordinators[profile.id] = popupCoordinator
        attentionBridges[profile.id] = attentionBridge

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

    /// Kills a Slot's bridge before its WKWebView is dropped or replaced:
    /// removes the handler, rejects later callbacks, forwards the reset
    /// boundary, and clears pool ownership.
    private func invalidateAttentionBridge(slotID: UUID) {
        guard let bridge = attentionBridges.removeValue(forKey: slotID) else { return }
        bridge.invalidate()
    }

    private func discardPopupCoordinator(slotID: UUID) {
        popupCoordinators.removeValue(forKey: slotID)?.closeAll()
    }
}
