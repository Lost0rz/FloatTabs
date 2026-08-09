import AppKit
import Foundation
import WebKit

enum NewBrowsingContextDisposition: Equatable {
    case currentSlot
    case temporaryPopup
    case externalBrowser
}

/// Owns temporary browsing contexts created through `target=_blank` or
/// `window.open`. The classifier deliberately uses interaction semantics rather
/// than provider-specific host lists:
///
/// - same-site HTTP(S) stays in the current Slot;
/// - a cross-site user link goes to the default browser;
/// - a cross-site scripted popup is hosted in a temporary child WKWebView;
/// - `about:blank` is a temporary popup because many auth flows create it first;
/// - non-web schemes are handed to the system.
@MainActor
final class PopupCoordinator: NSObject, WKUIDelegate, NSWindowDelegate {
    typealias ExternalOpenHandler = (URL) -> Void

    private weak var parentWebView: WKWebView?
    private var childPanels: [ObjectIdentifier: NSPanel] = [:]
    private let openExternal: ExternalOpenHandler

    init(
        parentWebView: WKWebView,
        openExternal: @escaping ExternalOpenHandler = { url in
            _ = NSWorkspace.shared.open(url)
        }
    ) {
        self.parentWebView = parentWebView
        self.openExternal = openExternal
        super.init()
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

        if WebNavigationCoordinator.isSameSite(sourceURL, targetURL) {
            return .currentSlot
        }

        return navigationType == .linkActivated
            ? .externalBrowser
            : .temporaryPopup
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

    func webViewDidClose(_ webView: WKWebView) {
        close(webView: webView, restoreFocus: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              let childWebView = panel.contentView as? WKWebView else {
            return
        }

        childPanels.removeValue(forKey: ObjectIdentifier(childWebView))
        restoreParentFocus()
    }

    func closeAll() {
        let webViews = childPanels.compactMap { _, panel in
            panel.contentView as? WKWebView
        }
        for webView in webViews {
            close(webView: webView, restoreFocus: false)
        }
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
        guard let panel = childPanels.removeValue(forKey: ObjectIdentifier(webView)) else {
            if restoreFocus {
                restoreParentFocus()
            }
            return
        }

        if let parentWindow = parentWebView?.window {
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
