import AppKit
import Foundation
import WebKit

enum NewBrowsingContextDisposition: Equatable {
    case currentSlot
    case temporaryPopup
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
        completionHandler: @escaping ([URL]?) -> Void
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

/// Owns new browsing contexts created through `target=_blank`, `window.open`,
/// and explicit FloatTabs link actions.
///
/// Navigation Intent rules:
///
/// - any user-activated HTTP(S) link stays in the current Slot;
/// - scripted HTTP(S) / `window.open` contexts use a temporary child WKWebView;
/// - `about:blank` uses a temporary child because many auth flows create it first;
/// - non-web schemes are handed to the system;
/// - the default browser is used for web links only through the explicit context-menu action;
/// - user-created floating windows are independent from temporary auth popups.
@MainActor
final class PopupCoordinator: NSObject, WKUIDelegate, WKNavigationDelegate, NSWindowDelegate {
    typealias ExternalOpenHandler = (URL) -> Void

    private weak var parentWebView: WKWebView?
    private var childPanels: [ObjectIdentifier: NSPanel] = [:]
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
        guard let targetURL else {
            return .temporaryPopup
        }

        let scheme = targetURL.scheme?.lowercased()
        if scheme == "about" {
            return .temporaryPopup
        }

        guard WebNavigationCoordinator.isWebURL(targetURL) else {
            return .externalBrowser
        }

        _ = sourceURL
        return navigationType == .linkActivated
            ? .currentSlot
            : .temporaryPopup
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
            webView.load(navigationAction.request)
            return nil

        case .externalBrowser:
            if let targetURL {
                openExternal(targetURL)
            }
            return nil

        case .temporaryPopup:
            return makeTemporaryPopup(
                sourceWebView: webView,
                configuration: configuration,
                targetURL: targetURL
            )
        }
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
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
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
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
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(
            DownloadCoordinator.responsePolicy(
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

        let id = ObjectIdentifier(webView)
        childPanels.removeValue(forKey: id)
        userFloatingPanels.removeValue(forKey: id)
        linkContextCoordinators.removeValue(forKey: id)?.invalidate()
        restoreParentFocus()
    }

    func closeAll() {
        let panels = Array(childPanels.values) + Array(userFloatingPanels.values)
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

    private func makeTemporaryPopup(
        sourceWebView: WKWebView,
        configuration: WKWebViewConfiguration,
        targetURL: URL?
    ) -> WKWebView {
        let popupWebView = WKWebView(frame: .zero, configuration: configuration)
        popupWebView.allowsBackForwardNavigationGestures = true
        popupWebView.customUserAgent = sourceWebView.customUserAgent
        popupWebView.uiDelegate = self
        popupWebView.navigationDelegate = self

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = targetURL?.host ?? "Web Login"
        panel.contentView = popupWebView
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        if let parentWindow = sourceWebView.window {
            panel.level = parentWindow.level
            panel.collectionBehavior = parentWindow.collectionBehavior
            parentWindow.addChildWindow(panel, ordered: .above)
        }

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        childPanels[ObjectIdentifier(popupWebView)] = panel
        return popupWebView
    }

    private func close(webView: WKWebView, restoreFocus: Bool) {
        let id = ObjectIdentifier(webView)
        let temporaryPanel = childPanels.removeValue(forKey: id)
        let userPanel = userFloatingPanels.removeValue(forKey: id)
        linkContextCoordinators.removeValue(forKey: id)?.invalidate()

        guard let panel = temporaryPanel ?? userPanel else {
            if restoreFocus {
                restoreParentFocus()
            }
            return
        }

        if temporaryPanel != nil,
           let parentWindow = parentWebView?.window {
            parentWindow.removeChildWindow(panel)
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
