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

/// Adds explicit user intent to HTTP(S) link context menus without changing
/// ordinary left-click delivery. The document-start script only intercepts a
/// context-menu gesture when it resolves to a real web link, then forwards the
/// absolute href to native AppKit menu actions.
@MainActor
final class LinkContextMenuCoordinator: NSObject, WKScriptMessageHandler {
    typealias FloatingOpenHandler = (URL, WKWebView) -> Void
    typealias ExternalOpenHandler = (URL) -> Void

    static let handlerName = "floatTabsLinkContext"

    private weak var webView: WKWebView?
    private let openFloating: FloatingOpenHandler
    private let openExternal: ExternalOpenHandler
    private var representedURL: URL?
    private weak var representedSourceWebView: WKWebView?

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
        controller.add(self, name: Self.handlerName)
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
                if (!href || !/^https?:/i.test(href)) return;

                const handler = window.webkit
                  && window.webkit.messageHandlers
                  && window.webkit.messageHandlers.floatTabsLinkContext;
                if (!handler) return;

                event.preventDefault();
                event.stopPropagation();
                if (typeof event.stopImmediatePropagation === 'function') {
                  event.stopImmediatePropagation();
                }
                handler.postMessage(href);
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
              let rawValue = message.body as? String,
              let url = URL(string: rawValue),
              WebAppURL.isSafe(url),
              let sourceWebView = message.webView ?? webView else {
            return
        }

        presentMenu(for: url, sourceWebView: sourceWebView)
    }

    func menu(for url: URL, sourceWebView: WKWebView) -> NSMenu {
        representedURL = url
        representedSourceWebView = sourceWebView

        let menu = NSMenu()

        let floating = NSMenuItem(
            title: "Open in Floating Window",
            action: #selector(openFloatingFromMenu),
            keyEquivalent: ""
        )
        floating.target = self
        menu.addItem(floating)

        let external = NSMenuItem(
            title: "Open in Default Browser",
            action: #selector(openExternalFromMenu),
            keyEquivalent: ""
        )
        external.target = self
        menu.addItem(external)

        menu.addItem(.separator())

        let copy = NSMenuItem(
            title: "Copy Link",
            action: #selector(copyLinkFromMenu),
            keyEquivalent: ""
        )
        copy.target = self
        menu.addItem(copy)
        return menu
    }

    func invalidate() {
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.handlerName
        )
    }

    private func presentMenu(for url: URL, sourceWebView: WKWebView) {
        guard let window = sourceWebView.window else { return }
        let menu = menu(for: url, sourceWebView: sourceWebView)
        let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let viewPoint = sourceWebView.convert(windowPoint, from: nil)
        menu.popUp(positioning: nil, at: viewPoint, in: sourceWebView)
        representedURL = nil
        representedSourceWebView = nil
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

    private weak var parentWebView: WKWebView?
    private var userFloatingPanels: [ObjectIdentifier: NSPanel] = [:]
    private var linkContextCoordinators: [ObjectIdentifier: LinkContextMenuCoordinator] = [:]
    private let openExternal: ExternalOpenHandler
    private let uploadCoordinator: UploadCoordinator
    private let downloadCoordinator: DownloadCoordinator

    init(
        parentWebView: WKWebView,
        openExternal: @escaping ExternalOpenHandler = { url in
            _ = NSWorkspace.shared.open(url)
        },
        uploadCoordinator: UploadCoordinator? = nil,
        downloadCoordinator: DownloadCoordinator? = nil
    ) {
        self.parentWebView = parentWebView
        self.openExternal = openExternal
        self.uploadCoordinator = uploadCoordinator ?? UploadCoordinator()
        self.downloadCoordinator = downloadCoordinator ?? DownloadCoordinator()
        super.init()
        installExplicitLinkContextMenu(on: parentWebView)
    }

    static func disposition(
        navigationType: WKNavigationType,
        sourceURL: URL?,
        targetURL: URL?
    ) -> NewBrowsingContextDisposition {
        _ = navigationType

        guard let targetURL else {
            return isAuthenticationURL(sourceURL) ? .popup : .currentSlot
        }

        let scheme = targetURL.scheme?.lowercased()
        if scheme == "about" {
            // OAuth providers often create an about:blank child first and
            // navigate it immediately afterwards. Keep that child floating
            // only when its opener is itself an authentication flow.
            return isAuthenticationURL(sourceURL) ? .popup : .currentSlot
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
    static func isAuthenticationURL(_ url: URL?) -> Bool {
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
            || host.hasPrefix("auth.")
            || host.hasPrefix("login.")
            || host.hasPrefix("signin.")
            || host.hasPrefix("sso.") {
            return true
        }

        let authenticationPathComponents: Set<String> = [
            "auth",
            "authenticate",
            "authentication",
            "authorize",
            "authorization",
            "login",
            "oauth",
            "oauth2",
            "saml",
            "sign-in",
            "signin",
            "sso",
        ]
        return url.path
            .split(separator: "/")
            .map { $0.lowercased() }
            .contains(where: authenticationPathComponents.contains)
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
        let sourceURL = navigationAction.sourceFrame.request.url ?? webView.url
        let targetURL = navigationAction.request.url

        switch Self.disposition(
            navigationType: navigationAction.navigationType,
            sourceURL: sourceURL,
            targetURL: targetURL
        ) {
        case .currentSlot:
            if targetURL?.scheme?.lowercased() != "about" {
                webView.load(navigationAction.request)
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
        downloadCoordinator.attach(download, presentingWindow: webView.window)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        downloadCoordinator.attach(download, presentingWindow: webView.window)
    }

    func webViewDidClose(_ webView: WKWebView) {
        close(webView: webView, restoreFocus: true)
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

        let floatingWebView = WebViewFactory.makeWebView(renderingProfile: rendering)
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
        panel.title = url.host ?? "Floating Page"
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
        floatingWebView.load(URLRequest(url: url))
        return floatingWebView
    }

    var userFloatingWindowCount: Int {
        userFloatingPanels.count
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

    private func makePopupWebView(
        configuration: WKWebViewConfiguration,
        sourceWebView: WKWebView,
        targetURL: URL?,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView {
        // WebKit supplies this configuration for the new browsing context. It
        // carries the opener's process pool and website data store, which is
        // essential for Google OAuth to complete in the same Browser Profile.
        let popupWebView = FloatTabsWebView(frame: .zero, configuration: configuration)
        popupWebView.customUserAgent = sourceWebView.customUserAgent
        popupWebView.allowsBackForwardNavigationGestures = true
        popupWebView.uiDelegate = self
        popupWebView.navigationDelegate = self
        if let source = sourceWebView as? FloatTabsWebView {
            popupWebView.setRendering(
                websiteMode: source.websiteMode,
                userPageZoom: source.userPageZoom
            )
        }
        // WebKit's configuration for a newly-created browsing context carries
        // the opener's userContentController. The parent already registered
        // `floatTabsLinkContext` on that controller, so registering the same
        // handler again raises an Objective-C exception and aborts the app
        // (this is especially easy to hit when Google/X OAuth opens a popup).
        // The inherited script and handler continue to deliver messages with
        // `message.webView` set to this popup, so no second coordinator is
        // needed here.

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
        panel.title = targetURL?.host ?? "Sign In"
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

        userFloatingPanels[ObjectIdentifier(popupWebView)] = panel
        return popupWebView
    }

    private func close(webView: WKWebView, restoreFocus: Bool) {
        webView.closeAllMediaPresentations(completionHandler: nil)
        let id = ObjectIdentifier(webView)
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
