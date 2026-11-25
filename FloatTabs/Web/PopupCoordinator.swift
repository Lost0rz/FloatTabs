import AppKit
import Foundation
import WebKit

enum NewBrowsingContextDisposition: Equatable {
    case currentSlot
    case popup
    case externalBrowser
}

struct UploadPanelPolicy: Equatable {
    let allowsMultipleSelection: Bool
    let canChooseFiles: Bool
    let canChooseDirectories: Bool

    static func make(
        allowsMultipleSelection: Bool,
        allowsDirectories: Bool
    ) -> UploadPanelPolicy {
        UploadPanelPolicy(
            allowsMultipleSelection: allowsMultipleSelection,
            canChooseFiles: !allowsDirectories,
            canChooseDirectories: allowsDirectories
        )
    }
}

@MainActor
final class UploadCoordinator {
    func presentOpenPanel(
        parameters: WKOpenPanelParameters,
        for webView: WKWebView,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let policy = UploadPanelPolicy.make(
            allowsMultipleSelection: parameters.allowsMultipleSelection,
            allowsDirectories: parameters.allowsDirectories
        )

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = policy.allowsMultipleSelection
        panel.canChooseFiles = policy.canChooseFiles
        panel.canChooseDirectories = policy.canChooseDirectories
        panel.canCreateDirectories = false
        panel.resolvesAliases = true

        let finish: (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }

        if let window = webView.window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            finish(panel.runModal())
        }
    }
}

/// Augments WebKit's native context menu when right-clicking an HTTP(S) link
/// without replacing system actions such as Copy, Look Up, Translate, or
/// Inspect Element. A passive document-start listener reports the hovered link
/// target so AppKit's `willOpenMenu(_:with:)` can prepend FloatTabs-specific
/// destinations cleanly.
@MainActor
final class LinkContextMenuCoordinator: NSObject, WKScriptMessageHandler {
    typealias FloatingOpenHandler = (URL, WKWebView) -> Void
    typealias ExternalOpenHandler = (URL) -> Void

    static let handlerName = "floatTabsLinkContext"
    private static let linkFreshnessWindow: TimeInterval = 1.0

    private weak var webView: WKWebView?
    private let openFloating: FloatingOpenHandler
    private let openExternal: ExternalOpenHandler
    private var representedURL: URL?
    private weak var representedSourceWebView: WKWebView?
    private var pendingContextLink: (url: URL, timestamp: TimeInterval)?

    init(
        webView: WKWebView,
        openFloating: @escaping FloatingOpenHandler,
        openExternal: @escaping ExternalOpenHandler
    ) {
        self.webView = webView
        self.openFloating = openFloating
        self.openExternal = openExternal
        super.init()

        let controller = webView.configuration.userContentController
        controller.addUserScript(Self.userScript())
        controller.removeScriptMessageHandler(forName: Self.handlerName)
        controller.add(self, name: Self.handlerName)
        attachNativeMenuHandler(to: webView)
    }

    func attachNativeMenuHandler(to targetWebView: WKWebView) {
        (targetWebView as? FloatTabsWebView)?.willOpenContextMenuHandler = { [weak self, weak targetWebView] menu, _ in
            guard let self, let targetWebView else { return }
            self.augmentNativeMenu(menu, sourceWebView: targetWebView)
        }
    }

    static func userScript() -> WKUserScript {
        WKUserScript(
            source: """
            (() => {
              if (window.__floatTabsLinkContextInstalled) return;
              window.__floatTabsLinkContextInstalled = true;

              document.addEventListener('contextmenu', (event) => {
                const path = typeof event.composedPath === 'function'
                  ? event.composedPath()
                  : [];

                let link = path.find((node) =>
                  node
                  && node.nodeType === 1
                  && typeof node.matches === 'function'
                  && node.matches('a[href], area[href]')
                );

                if (!link && event.target && event.target.nodeType === 1
                    && typeof event.target.closest === 'function') {
                  link = event.target.closest('a[href], area[href]');
                }

                const href = link && link.href;
                const handler = window.webkit
                  && window.webkit.messageHandlers
                  && window.webkit.messageHandlers.floatTabsLinkContext;
                if (!handler) return;

                if (href && /^https?:/i.test(href)) {
                  handler.postMessage(href);
                } else {
                  handler.postMessage('');
                }
              }, true);
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == Self.handlerName,
              let rawValue = message.body as? String else {
            return
        }
        guard !rawValue.isEmpty,
              let url = URL(string: rawValue),
              WebAppURL.isSafe(url) else {
            pendingContextLink = nil
            return
        }
        representedSourceWebView = message.webView ?? webView
        pendingContextLink = (url: url, timestamp: ProcessInfo.processInfo.systemUptime)
    }

    func augmentNativeMenu(_ menu: NSMenu, sourceWebView: WKWebView) {
        guard let pending = pendingContextLink else { return }
        pendingContextLink = nil
        let age = ProcessInfo.processInfo.systemUptime - pending.timestamp
        guard age >= 0, age <= Self.linkFreshnessWindow else { return }

        representedURL = pending.url
        representedSourceWebView = sourceWebView

        let redundantIndices = menu.items.enumerated().compactMap { index, item -> Int? in
            let id = item.identifier?.rawValue ?? ""
            if id == "WKMenuItemIdentifierOpenLink"
                || id == "WKMenuItemIdentifierOpenLinkInNewWindow" {
                return index
            }
            return nil
        }
        for index in redundantIndices.reversed() {
            menu.removeItem(at: index)
        }

        let floating = NSMenuItem(
            title: L10n.tr("Open in Floating Window", "在悬浮窗口中打开"),
            action: #selector(openFloatingFromMenu),
            keyEquivalent: ""
        )
        floating.target = self

        let external = NSMenuItem(
            title: L10n.tr("Open in Default Browser", "在默认浏览器中打开"),
            action: #selector(openExternalFromMenu),
            keyEquivalent: ""
        )
        external.target = self

        if !menu.items.isEmpty, !menu.items[0].isSeparatorItem {
            menu.insertItem(.separator(), at: 0)
        }
        menu.insertItem(external, at: 0)
        menu.insertItem(floating, at: 0)
    }

    func menu(for url: URL, sourceWebView: WKWebView) -> NSMenu {
        representedURL = url
        representedSourceWebView = sourceWebView

        let menu = NSMenu()

        let floating = NSMenuItem(
            title: L10n.tr("Open in Floating Window", "在悬浮窗口中打开"),
            action: #selector(openFloatingFromMenu),
            keyEquivalent: ""
        )
        floating.target = self
        menu.addItem(floating)

        let external = NSMenuItem(
            title: L10n.tr("Open in Default Browser", "在默认浏览器中打开"),
            action: #selector(openExternalFromMenu),
            keyEquivalent: ""
        )
        external.target = self
        menu.addItem(external)

        menu.addItem(.separator())

        let copy = NSMenuItem(
            title: L10n.tr("Copy Link", "复制链接"),
            action: #selector(copyLinkFromMenu),
            keyEquivalent: ""
        )
        copy.target = self
        menu.addItem(copy)
        return menu
    }

    func invalidate() {
        (webView as? FloatTabsWebView)?.willOpenContextMenuHandler = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.handlerName
        )
        pendingContextLink = nil
    }

    @objc private func openFloatingFromMenu() {
        guard let representedURL,
              let representedSourceWebView else { return }
        openFloating(representedURL, representedSourceWebView)
    }

    @objc private func openExternalFromMenu() {
        guard let representedURL else { return }
        openExternal(representedURL)
    }

    @objc private func copyLinkFromMenu() {
        guard let representedURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(representedURL.absoluteString, forType: .string)
    }
}

/// Routes new browsing contexts created through `target=_blank`, `window.open`,
/// and explicit FloatTabs link actions.
///
/// Navigation Intent rules:
///
/// - user-activated HTTP(S) links stay in the current Slot;
/// - only script-created authentication/authorization contexts get a real
///   popup so OAuth flows retain their opener and never replace the parent page;
/// - ordinary script-created pages, video pages, and about:blank contexts stay
///   in the current Slot;
/// - non-web schemes are handed to the system;
/// - the default browser is used for web links only through the explicit context-menu action;
/// - only explicit context-menu actions may create a FloatTabs-owned popup for
///   non-authentication pages.
@MainActor
final class PopupCoordinator: NSObject, WKUIDelegate, WKNavigationDelegate, NSWindowDelegate {
    typealias ExternalOpenHandler = (URL) -> Void

    enum JavaScriptDialogRequest {
        case alert(origin: String, message: String, @MainActor () -> Void)
        case confirm(origin: String, message: String, @MainActor (Bool) -> Void)
        case prompt(origin: String, prompt: String, defaultText: String?, @MainActor (String?) -> Void)
    }

    typealias JavaScriptDialogPresenter = @MainActor (JavaScriptDialogRequest, NSWindow?) -> Void
    typealias MediaCapturePermissionPresenter = @MainActor (
        String,
        WKMediaCaptureType,
        NSWindow?,
        @escaping @MainActor (WKPermissionDecision) -> Void
    ) -> Void

    private static let maximumDialogTextLength = 4_000

    private struct DeferredBlankPopup {
        let webView: FloatTabsWebView
        weak var sourceWebView: WKWebView?
        let sourceURL: URL?
        let initialPlaceholderURL: URL?
        var didConsumeInitialPlaceholder: Bool
        let windowFeatures: WKWindowFeatures
        var cleanupTask: Task<Void, Never>?
    }

    private weak var parentWebView: WKWebView?
    private var userFloatingPanels: [ObjectIdentifier: NSPanel] = [:]
    private var deferredBlankPopups: [ObjectIdentifier: DeferredBlankPopup] = [:]
    private var linkContextCoordinators: [ObjectIdentifier: LinkContextMenuCoordinator] = [:]
    private var mediaCaptureDecisions: [String: WKPermissionDecision] = [:]
    private let openExternal: ExternalOpenHandler
    private let uploadCoordinator: UploadCoordinator
    private let downloadCoordinator: DownloadCoordinator
    private let dialogPresenter: JavaScriptDialogPresenter
    private let mediaPermissionPresenter: MediaCapturePermissionPresenter
    private let deferredPopupTimeout: TimeInterval
    private let slotID: UUID?
    private let diagnostics: any RuntimeDiagnosticRecording

    init(
        parentWebView: WKWebView,
        openExternal: @escaping ExternalOpenHandler = { url in
            _ = NSWorkspace.shared.open(url)
        },
        uploadCoordinator: UploadCoordinator? = nil,
        downloadCoordinator: DownloadCoordinator? = nil,
        dialogPresenter: JavaScriptDialogPresenter? = nil,
        mediaPermissionPresenter: MediaCapturePermissionPresenter? = nil,
        deferredPopupTimeout: TimeInterval = 15.0,
        slotID: UUID? = nil,
        diagnostics: any RuntimeDiagnosticRecording = RuntimeDiagnosticNoopRecorder()
    ) {
        self.parentWebView = parentWebView
        self.openExternal = openExternal
        self.uploadCoordinator = uploadCoordinator ?? UploadCoordinator()
        self.downloadCoordinator = downloadCoordinator ?? DownloadCoordinator()
        self.dialogPresenter = dialogPresenter ?? Self.presentDefaultJavaScriptDialog
        self.mediaPermissionPresenter = mediaPermissionPresenter ?? Self.presentDefaultMediaCapturePermission
        self.deferredPopupTimeout = max(0, deferredPopupTimeout)
        self.slotID = slotID
        self.diagnostics = diagnostics
        super.init()
        installExplicitLinkContextMenu(on: parentWebView)
    }

    static func disposition(
        navigationType: WKNavigationType,
        sourceURL: URL?,
        targetURL: URL?
    ) -> NewBrowsingContextDisposition {
        _ = navigationType

        guard let targetURL, !targetURL.absoluteString.isEmpty else {
            return isAuthenticationURL(sourceURL) ? .popup : .currentSlot
        }

        let scheme = targetURL.scheme?.lowercased()
        if scheme == "about" {
            // OAuth providers often create an about:blank child first and
            // navigate it immediately afterwards. Keep that child floating
            // only when its opener is itself an authentication flow.
            return isAuthenticationURL(sourceURL) ? .popup : .currentSlot
        }

        if let scheme, ["blob", "data", "javascript"].contains(scheme) {
            return .currentSlot
        }

        guard WebNavigationCoordinator.isWebURL(targetURL) else {
            return .externalBrowser
        }

        return isAuthenticationURL(targetURL) ? .popup : .currentSlot
    }

    /// Identifies a login/OAuth handoff without treating every new browsing
    /// context as a separate window. This is deliberately URL-based and
    /// conservative: ordinary video/detail/share URLs remain in the current
    /// Tab, while common IdP hosts and explicit auth path components retain a
    /// real opener window.
    nonisolated static func isAuthenticationURL(_ url: URL?) -> Bool {
        guard let url,
              WebNavigationCoordinator.isWebURL(url) else {
            return false
        }

        let host = url.host?.lowercased() ?? ""
        let knownAuthenticationHosts = [
            "accounts.google.com",
            "appleid.apple.com",
            "auth.openai.com",
            "github.com",
            "login.microsoftonline.com",
            "login.live.com",
        ]
        if knownAuthenticationHosts.contains(host)
            || host.hasPrefix("accounts.")
            || host.hasPrefix("auth.")
            || host.hasPrefix("id.")
            || host.hasPrefix("login.")
            || host.hasPrefix("signin.")
            || host.hasPrefix("sso.") {
            return true
        }

        let pathComponents = url.path
            .split(separator: "/")
            .map { $0.lowercased() }
        let authenticationPathComponents: Set<String> = [
            "auth",
            "authenticate",
            "authentication",
            "authorize",
            "authorization",
            "consent",
            "login",
            "mfa",
            "oauth",
            "oauth2",
            "passkey",
            "saml",
            "sign-in",
            "signin",
            "sso",
            "two-factor",
            "2fa",
            "webauthn",
        ]
        if pathComponents.contains(where: authenticationPathComponents.contains) {
            return true
        }

        if pathComponents.contains("installations"),
           pathComponents.contains("apps") || pathComponents.contains("settings") {
            return true
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            let queryNames = Set(queryItems.map { $0.name.lowercased() })
            if queryNames.contains("samlrequest")
                || queryNames.contains("oauth_token")
                || (queryNames.contains("client_id")
                    && (queryNames.contains("redirect_uri")
                        || queryNames.contains("response_type"))) {
                return true
            }
        }

        return false
    }

    /// Returns the user-visible FloatTabs viewport for a source WebView.
    ///
    /// Desktop Website Mode deliberately gives the child WKWebView a larger
    /// logical CSS frame and maps it into the visible panel through an AppKit
    /// host. Using `webView.frame.size` directly therefore over-sizes explicit
    /// floating windows after the PR #16 logical-host rendering change. Walk up
    /// to the owning WebPanelContainerView when present; standalone/popup WebViews
    /// keep their ordinary frame as the fallback.
    static func visibleSourceSize(for webView: WKWebView) -> NSSize {
        var ancestor = webView.superview
        while let view = ancestor {
            if let container = view as? WebPanelContainerView,
               container.bounds.width > 0,
               container.bounds.height > 0 {
                return container.bounds.size
            }
            ancestor = view.superview
        }
        return webView.frame.size
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let frameRequestURL = navigationAction.sourceFrame.request.url
        let sourceURL: URL?
        if let frameRequestURL, WebNavigationCoordinator.isWebURL(frameRequestURL) {
            sourceURL = frameRequestURL
        } else {
            sourceURL = webView.url ?? frameRequestURL
        }
        let targetURL = navigationAction.request.url

        switch Self.disposition(
            navigationType: navigationAction.navigationType,
            sourceURL: sourceURL,
            targetURL: targetURL
        ) {
        case .currentSlot:
            let deferDecision = Self.shouldDeferChildContext(
                targetURL: targetURL,
                sourceURL: sourceURL,
                webViewURL: webView.url,
                navigationType: navigationAction.navigationType
            )
            if deferDecision.deferChild {
                return makeDeferredBlankPopupWebView(
                    configuration: configuration,
                    sourceWebView: webView,
                    sourceURL: sourceURL,
                    initialPlaceholderURL: deferDecision.placeholderURL,
                    windowFeatures: windowFeatures
                )
            }
            if let targetURL, WebAppURL.isSafe(targetURL) {
                webView.load(
                    WebNavigationCoordinator.requestPreservingReferrer(
                        navigationAction.request,
                        sourceURL: sourceURL
                    )
                )
            }
            return nil

        case .popup:
            return makePopupWebView(
                configuration: configuration,
                sourceWebView: webView,
                targetURL: targetURL,
                windowFeatures: windowFeatures
            )

        case .externalBrowser:
            if let targetURL {
                openExternal(targetURL)
            }
            return nil

        }
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        uploadCoordinator.presentOpenPanel(
            parameters: parameters,
            for: webView,
            completionHandler: completionHandler
        )
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping @MainActor @Sendable (
            WKNavigationActionPolicy,
            WKWebpagePreferences
        ) -> Void
    ) {
        let webViewID = ObjectIdentifier(webView)
        if var deferred = deferredBlankPopups[webViewID] {
            if navigationAction.shouldPerformDownload {
                deferredBlankPopups.removeValue(forKey: webViewID)?.cleanupTask?.cancel()
                teardownDeferredBlankPopup(deferred.webView)
                decisionHandler(.download, preferences)
                return
            }

            let destinationURL = navigationAction.request.url
            if Self.isDeferredBlankTargetURL(destinationURL) {
                decisionHandler(.allow, preferences)
                return
            }

            if !deferred.didConsumeInitialPlaceholder,
               navigationAction.navigationType == .other,
               let placeholderURL = deferred.initialPlaceholderURL,
               let destinationURL,
               destinationURL.standardized == placeholderURL.standardized {
                deferred.didConsumeInitialPlaceholder = true
                deferredBlankPopups[webViewID] = deferred
                decisionHandler(.cancel, preferences)
                return
            }

            deferredBlankPopups.removeValue(forKey: webViewID)?.cleanupTask?.cancel()

            switch Self.disposition(
                navigationType: navigationAction.navigationType,
                sourceURL: deferred.sourceURL,
                targetURL: destinationURL
            ) {
            case .popup:
                if let sourceWebView = deferred.sourceWebView ?? parentWebView {
                    presentPopupPanel(
                        for: deferred.webView,
                        sourceWebView: sourceWebView,
                        targetURL: destinationURL,
                        windowFeatures: deferred.windowFeatures,
                        popupKind: "deferred_blank_promoted"
                    )
                }
                decisionHandler(
                    DownloadCoordinator.actionPolicy(
                        shouldPerformDownload: navigationAction.shouldPerformDownload
                    ),
                    preferences
                )

            case .currentSlot:
                decisionHandler(.cancel, preferences)
                teardownDeferredBlankPopup(deferred.webView)
                if let destinationURL,
                   WebAppURL.isSafe(destinationURL),
                   let hostWebView = deferred.sourceWebView ?? parentWebView {
                    hostWebView.load(
                        WebNavigationCoordinator.requestPreservingReferrer(
                            navigationAction.request,
                            sourceURL: deferred.sourceURL
                        )
                    )
                }

            case .externalBrowser:
                decisionHandler(.cancel, preferences)
                teardownDeferredBlankPopup(deferred.webView)
                if let destinationURL {
                    openExternal(destinationURL)
                }
            }
            return
        }

        decisionHandler(
            DownloadCoordinator.actionPolicy(
                shouldPerformDownload: navigationAction.shouldPerformDownload
            ),
            preferences
        )
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(
            DownloadCoordinator.responsePolicy(
                response: navigationResponse.response,
                canShowMIMEType: navigationResponse.canShowMIMEType
            )
        )
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        downloadCoordinator.attach(
            download,
            presentingWindow: webView.window ?? parentWebView?.window
        )
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        downloadCoordinator.attach(
            download,
            presentingWindow: webView.window ?? parentWebView?.window
        )
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable () -> Void
    ) {
        let host = Self.dialogOriginLabel(for: frame, fallbackWebView: webView)
        dialogPresenter(
            .alert(
                origin: host,
                message: Self.clampedDialogText(message),
                completionHandler
            ),
            webView.window ?? parentWebView?.window
        )
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let host = Self.dialogOriginLabel(for: frame, fallbackWebView: webView)
        dialogPresenter(
            .confirm(
                origin: host,
                message: Self.clampedDialogText(message),
                completionHandler
            ),
            webView.window ?? parentWebView?.window
        )
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let host = Self.dialogOriginLabel(for: frame, fallbackWebView: webView)
        dialogPresenter(
            .prompt(
                origin: host,
                prompt: Self.clampedDialogText(prompt),
                defaultText: defaultText.map(Self.clampedDialogText),
                completionHandler
            ),
            webView.window ?? parentWebView?.window
        )
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        _ = frame
        evaluateMediaCapturePermission(
            scheme: origin.protocol,
            host: origin.host,
            port: origin.port,
            type: type,
            hostWindow: webView.window ?? parentWebView?.window,
            decisionHandler: decisionHandler
        )
    }

    func evaluateMediaCapturePermission(
        scheme rawScheme: String,
        host rawHost: String,
        port: Int,
        type: WKMediaCaptureType,
        hostWindow: NSWindow?,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        let scheme = rawScheme.lowercased()
        let host = rawHost.lowercased()
        let isSecureOrigin = scheme == "https"
            || host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
        let originURL = Self.securityOriginURL(scheme: scheme, host: host, port: port)
        let safeOrigin = originURL.flatMap {
            RuntimeDiagnosticPrivacy.safeURLString($0, mode: .standard)
        }
        guard isSecureOrigin, !host.isEmpty else {
            recordMediaPermissionDecision(
                type: type,
                decision: .deny,
                source: "insecure_origin_denied",
                safeOrigin: safeOrigin
            )
            decisionHandler(.deny)
            return
        }

        let cacheKey = "\(scheme)://\(host):\(port)#\(type.rawValue)"
        if let cached = mediaCaptureDecisions[cacheKey] {
            recordMediaPermissionDecision(
                type: type,
                decision: cached,
                source: "cached",
                safeOrigin: safeOrigin
            )
            decisionHandler(cached)
            return
        }

        mediaPermissionPresenter(
            rawHost,
            type,
            hostWindow
        ) { [weak self] decision in
            if decision == .grant || decision == .deny {
                self?.mediaCaptureDecisions[cacheKey] = decision
            }
            self?.recordMediaPermissionDecision(
                type: type,
                decision: decision,
                source: "user_prompt",
                safeOrigin: safeOrigin
            )
            decisionHandler(decision)
        }
    }

    func webViewDidClose(_ webView: WKWebView) {
        let wasPresentedPanel = userFloatingPanels[ObjectIdentifier(webView)] != nil
        close(webView: webView, restoreFocus: wasPresentedPanel)
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              let webView = panel.contentView as? WKWebView else {
            return
        }

        // A popup can own a WebKit media presentation independently of its
        // AppKit panel. End that presentation before dropping our last native
        // reference, otherwise audio can continue after the close button has
        // removed the visible window.
        webView.closeAllMediaPresentations(completionHandler: nil)
        let id = ObjectIdentifier(webView)
        userFloatingPanels.removeValue(forKey: id)
        linkContextCoordinators.removeValue(forKey: id)?.invalidate()
        restoreParentFocus()
    }

    func closeAll() {
        let deferredWebViews = Array(deferredBlankPopups.values.map(\.webView))
        for webView in deferredWebViews {
            close(webView: webView, restoreFocus: false)
        }

        let panels = Array(userFloatingPanels.values)
        let webViews = panels.compactMap { $0.contentView as? WKWebView }
        for webView in webViews {
            close(webView: webView, restoreFocus: false)
        }

        if let parentWebView {
            let id = ObjectIdentifier(parentWebView)
            linkContextCoordinators.removeValue(forKey: id)?.invalidate()
        }
    }

    @discardableResult
    func openUserFloatingWindow(
        _ url: URL,
        from sourceWebView: WKWebView? = nil
    ) -> WKWebView? {
        guard WebAppURL.isSafe(url),
              let sourceWebView = sourceWebView ?? parentWebView else {
            return nil
        }

        let rendering: WebRenderingProfile
        if let source = sourceWebView as? FloatTabsWebView {
            rendering = WebRenderingProfile.canonicalDefault
                .settingWebsiteMode(source.websiteMode)
                .settingZoom(source.userPageZoom)
        } else {
            rendering = WebRenderingProfile.canonicalDefault
                .settingZoom(sourceWebView.pageZoom)
        }

        let floatingWebView = WebViewFactory.makeWebView(
            renderingProfile: rendering,
            websiteDataStore: sourceWebView.configuration.websiteDataStore
        )
        floatingWebView.customUserAgent = sourceWebView.customUserAgent
        floatingWebView.allowsBackForwardNavigationGestures = true
        floatingWebView.uiDelegate = self
        floatingWebView.navigationDelegate = self
        installExplicitLinkContextMenu(on: floatingWebView)

        let sourceSize = Self.visibleSourceSize(for: sourceWebView)
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: max(sourceSize.width, 430),
                height: max(sourceSize.height, 560)
            ),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = url.host ?? L10n.tr("Floating Page", "悬浮页面")
        panel.contentView = floatingWebView
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = sourceWebView.window?.level ?? .floating
        panel.collectionBehavior = sourceWebView.window?.collectionBehavior
            ?? [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        userFloatingPanels[ObjectIdentifier(floatingWebView)] = panel
        recordPopupOpened(
            kind: "user_floating_window",
            targetURL: url,
            customProfileDataStore: !sourceWebView.configuration.websiteDataStore.isPersistent
                ? false
                : sourceWebView.configuration.websiteDataStore !== WKWebsiteDataStore.default()
        )
        floatingWebView.load(URLRequest(url: url))
        return floatingWebView
    }

    var userFloatingWindowCount: Int {
        userFloatingPanels.count
    }

#if DEBUG
    var debugDeferredBlankPopupCount: Int {
        deferredBlankPopups.count
    }
#endif

    private static func isDeferredBlankTargetURL(_ url: URL?) -> Bool {
        guard let url else { return true }
        let scheme = url.scheme?.lowercased() ?? ""
        return scheme == "about" || url.absoluteString.isEmpty
    }

    private static func shouldDeferChildContext(
        targetURL: URL?,
        sourceURL: URL?,
        webViewURL: URL?,
        navigationType: WKNavigationType
    ) -> (deferChild: Bool, placeholderURL: URL?) {
        if isDeferredBlankTargetURL(targetURL) {
            return (true, nil)
        }
        if navigationType == .other, let targetURL {
            let standardizedTarget = targetURL.standardized
            if sourceURL.map({ $0.standardized == standardizedTarget }) == true
                || webViewURL.map({ $0.standardized == standardizedTarget }) == true {
                return (true, targetURL)
            }
        }
        return (false, nil)
    }

    private func installExplicitLinkContextMenu(on webView: WKWebView) {
        let id = ObjectIdentifier(webView)
        guard linkContextCoordinators[id] == nil else { return }

        let coordinator = LinkContextMenuCoordinator(
            webView: webView,
            openFloating: { [weak self] url, sourceWebView in
                self?.openUserFloatingWindow(url, from: sourceWebView)
            },
            openExternal: { [weak self] url in
                self?.openExternal(url)
            }
        )
        linkContextCoordinators[id] = coordinator
    }

    private func makeChildWebView(
        configuration: WKWebViewConfiguration,
        sourceWebView: WKWebView
    ) -> FloatTabsWebView {
        // WebKit supplies this configuration for the new browsing context. It
        // carries the opener's process pool and website data store, which is
        // essential for Google OAuth to complete in the same Browser Profile.
        let childWebView = FloatTabsWebView(frame: .zero, configuration: configuration)
        childWebView.customUserAgent = sourceWebView.customUserAgent
        childWebView.allowsBackForwardNavigationGestures = true
        childWebView.uiDelegate = self
        childWebView.navigationDelegate = self
        if let source = sourceWebView as? FloatTabsWebView {
            childWebView.setRendering(
                websiteMode: source.websiteMode,
                userPageZoom: source.userPageZoom
            )
        }
        // WebKit's configuration for a newly-created browsing context carries
        // the opener's userContentController. The parent already registered
        // `floatTabsLinkContext` on that controller, so registering the same
        // handler again raises an Objective-C exception and aborts the app
        // (this is especially easy to hit when Google/X OAuth opens a popup).
        // Attach the native `willOpenMenu` handler from the opener's link
        // coordinator without adding a duplicate script message handler.
        let coordinator = linkContextCoordinators[ObjectIdentifier(sourceWebView)]
            ?? parentWebView.flatMap { linkContextCoordinators[ObjectIdentifier($0)] }
        coordinator?.attachNativeMenuHandler(to: childWebView)
        return childWebView
    }

    private static func dialogOriginLabel(
        for frame: WKFrameInfo,
        fallbackWebView: WKWebView
    ) -> String {
        let host = frame.securityOrigin.host.trimmingCharacters(in: .whitespacesAndNewlines)
        if !host.isEmpty { return host }
        if let fallbackHost = fallbackWebView.url?.host, !fallbackHost.isEmpty {
            return fallbackHost
        }
        return L10n.tr("Website", "网页")
    }

    private static func clampedDialogText(_ raw: String) -> String {
        guard raw.count > maximumDialogTextLength else { return raw }
        return String(raw.prefix(maximumDialogTextLength)) + "…"
    }

    private static func presentDefaultJavaScriptDialog(
        _ request: JavaScriptDialogRequest,
        hostWindow: NSWindow?
    ) {
        guard let hostWindow,
              hostWindow.isVisible,
              hostWindow.attachedSheet == nil else {
            switch request {
            case let .alert(_, _, completion):
                completion()
            case let .confirm(_, _, completion):
                completion(false)
            case let .prompt(_, _, _, completion):
                completion(nil)
            }
            return
        }

        let alert = NSAlert()
        switch request {
        case let .alert(origin, message, completion):
            alert.messageText = L10n.tr("\(origin) says", "\(origin) 提示")
            alert.informativeText = message
            alert.addButton(withTitle: L10n.tr("OK", "好"))
            alert.beginSheetModal(for: hostWindow) { _ in
                completion()
            }

        case let .confirm(origin, message, completion):
            alert.messageText = L10n.tr("\(origin) asks", "\(origin) 询问")
            alert.informativeText = message
            alert.addButton(withTitle: L10n.tr("OK", "好"))
            alert.addButton(withTitle: L10n.tr("Cancel", "取消"))
            alert.beginSheetModal(for: hostWindow) { response in
                completion(response == .alertFirstButtonReturn)
            }

        case let .prompt(origin, prompt, defaultText, completion):
            alert.messageText = L10n.tr("\(origin) asks", "\(origin) 询问")
            alert.informativeText = prompt
            let field = NSTextField(string: defaultText ?? "")
            field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
            alert.accessoryView = field
            alert.addButton(withTitle: L10n.tr("OK", "好"))
            alert.addButton(withTitle: L10n.tr("Cancel", "取消"))
            alert.beginSheetModal(for: hostWindow) { response in
                completion(response == .alertFirstButtonReturn ? field.stringValue : nil)
            }
        }
    }

    private static func presentDefaultMediaCapturePermission(
        host: String,
        type: WKMediaCaptureType,
        hostWindow: NSWindow?,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        guard let hostWindow,
              hostWindow.isVisible,
              hostWindow.attachedSheet == nil else {
            decisionHandler(.deny)
            return
        }

        let resourceName: String
        switch type {
        case .microphone:
            resourceName = L10n.tr("microphone", "麦克风")
        case .camera:
            resourceName = L10n.tr("camera", "摄像头")
        case .cameraAndMicrophone:
            resourceName = L10n.tr("camera and microphone", "摄像头和麦克风")
        @unknown default:
            resourceName = L10n.tr("media device", "媒体设备")
        }

        let displayHost = host.isEmpty ? L10n.tr("This website", "此网站") : "“\(host)”"
        let alert = NSAlert()
        alert.messageText = L10n.tr(
            "Allow \(displayHost) to use your \(resourceName)?",
            "允许\(displayHost)使用您的\(resourceName)吗？"
        )
        alert.informativeText = L10n.tr(
            "Access lasts for the lifetime of this tab session.",
            "授权在当前标签会话期间有效。"
        )
        alert.addButton(withTitle: L10n.tr("Allow", "允许"))
        alert.addButton(withTitle: L10n.tr("Don’t Allow", "不允许"))
        alert.beginSheetModal(for: hostWindow) { response in
            decisionHandler(response == .alertFirstButtonReturn ? .grant : .deny)
        }
    }

    private func makeDeferredBlankPopupWebView(
        configuration: WKWebViewConfiguration,
        sourceWebView: WKWebView,
        sourceURL: URL?,
        initialPlaceholderURL: URL?,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView {
        let deferredWebView = makeChildWebView(
            configuration: configuration,
            sourceWebView: sourceWebView
        )
        let id = ObjectIdentifier(deferredWebView)
        var entry = DeferredBlankPopup(
            webView: deferredWebView,
            sourceWebView: sourceWebView,
            sourceURL: sourceURL,
            initialPlaceholderURL: initialPlaceholderURL,
            didConsumeInitialPlaceholder: false,
            windowFeatures: windowFeatures,
            cleanupTask: nil
        )
        if deferredPopupTimeout > 0 {
            let timeoutNanoseconds = UInt64((deferredPopupTimeout * 1_000_000_000).rounded())
            entry.cleanupTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                } catch {
                    return
                }
                self?.expireDeferredBlankPopup(id: id)
            }
        }
        deferredBlankPopups[id] = entry
        return deferredWebView
    }

    private func expireDeferredBlankPopup(id: ObjectIdentifier) {
        guard let deferred = deferredBlankPopups.removeValue(forKey: id) else { return }
        var fields: [String: RuntimeDiagnosticValue] = [
            "reason": .string("deferred_timeout")
        ]
        if let slotID {
            fields["slot_id"] = .string(slotID.uuidString)
        }
        diagnostics.record(
            event: "web.popup.deferred_expired",
            level: .notice,
            subsystem: "web",
            fields: fields
        )
        teardownDeferredBlankPopup(deferred.webView)
    }

    private func teardownDeferredBlankPopup(_ webView: WKWebView) {
        webView.stopLoading()
        webView.closeAllMediaPresentations(completionHandler: nil)
        webView.uiDelegate = nil
        webView.navigationDelegate = nil
    }

    private func makePopupWebView(
        configuration: WKWebViewConfiguration,
        sourceWebView: WKWebView,
        targetURL: URL?,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView {
        let popupWebView = makeChildWebView(
            configuration: configuration,
            sourceWebView: sourceWebView
        )
        presentPopupPanel(
            for: popupWebView,
            sourceWebView: sourceWebView,
            targetURL: targetURL,
            windowFeatures: windowFeatures,
            popupKind: "immediate_popup"
        )
        return popupWebView
    }

    private func presentPopupPanel(
        for popupWebView: FloatTabsWebView,
        sourceWebView: WKWebView,
        targetURL: URL?,
        windowFeatures: WKWindowFeatures,
        popupKind: String = "immediate_popup"
    ) {
        let id = ObjectIdentifier(popupWebView)
        guard userFloatingPanels[id] == nil else { return }

        let sourceSize = Self.visibleSourceSize(for: sourceWebView)
        let width = max(windowFeatures.width?.doubleValue ?? sourceSize.width, 430)
        let height = max(windowFeatures.height?.doubleValue ?? sourceSize.height, 560)
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            ),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = targetURL?.host ?? L10n.tr("Sign In", "登录")
        panel.contentView = popupWebView
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = sourceWebView.window?.level ?? .floating
        panel.collectionBehavior = sourceWebView.window?.collectionBehavior
            ?? [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        userFloatingPanels[id] = panel
        recordPopupOpened(
            kind: popupKind,
            targetURL: targetURL,
            customProfileDataStore: popupWebView.configuration.websiteDataStore !== WKWebsiteDataStore.default()
        )
    }

    private func recordPopupOpened(
        kind: String,
        targetURL: URL?,
        customProfileDataStore: Bool
    ) {
        var fields: [String: RuntimeDiagnosticValue] = [
            "popup_kind": .string(kind),
            "target_origin": targetURL.flatMap {
                RuntimeDiagnosticPrivacy.safeURLString($0, mode: .standard)
            }.map(RuntimeDiagnosticValue.string) ?? .null,
            "custom_profile_datastore": .bool(customProfileDataStore)
        ]
        if let slotID {
            fields["slot_id"] = .string(slotID.uuidString)
        }
        diagnostics.record(
            event: "web.popup.opened",
            level: .notice,
            subsystem: "web",
            fields: fields
        )
    }

    private func recordMediaPermissionDecision(
        type: WKMediaCaptureType,
        decision: WKPermissionDecision,
        source: String,
        safeOrigin: String?
    ) {
        let mediaTypeName: String
        switch type {
        case .camera:
            mediaTypeName = "camera"
        case .microphone:
            mediaTypeName = "microphone"
        case .cameraAndMicrophone:
            mediaTypeName = "camera_and_microphone"
        @unknown default:
            mediaTypeName = "other"
        }
        let decisionName: String
        switch decision {
        case .grant:
            decisionName = "grant"
        case .deny:
            decisionName = "deny"
        case .prompt:
            decisionName = "prompt"
        @unknown default:
            decisionName = "other"
        }
        var fields: [String: RuntimeDiagnosticValue] = [
            "media_type": .string(mediaTypeName),
            "decision": .string(decisionName),
            "decision_source": .string(source),
            "security_origin": safeOrigin.map(RuntimeDiagnosticValue.string) ?? .null
        ]
        if let slotID {
            fields["slot_id"] = .string(slotID.uuidString)
        }
        diagnostics.record(
            event: "web.media_permission.decision",
            level: .notice,
            subsystem: "web",
            fields: fields
        )
    }

    private static func securityOriginURL(scheme: String, host: String, port: Int) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if port > 0 {
            components.port = port
        }
        return components.url
    }

    private func close(webView: WKWebView, restoreFocus: Bool) {
        webView.closeAllMediaPresentations(completionHandler: nil)
        let id = ObjectIdentifier(webView)
        if let deferred = deferredBlankPopups.removeValue(forKey: id) {
            deferred.cleanupTask?.cancel()
            teardownDeferredBlankPopup(deferred.webView)
        }
        let userPanel = userFloatingPanels.removeValue(forKey: id)
        linkContextCoordinators.removeValue(forKey: id)?.invalidate()

        guard let panel = userPanel else {
            if restoreFocus {
                restoreParentFocus()
            }
            return
        }

        panel.orderOut(nil)
        panel.close()

        if restoreFocus {
            restoreParentFocus()
        }
    }

    private func restoreParentFocus() {
        guard let parentWebView,
              let parentWindow = parentWebView.window else {
            return
        }
        parentWindow.makeKeyAndOrderFront(nil)
        _ = parentWindow.makeFirstResponder(parentWebView)
    }
}
