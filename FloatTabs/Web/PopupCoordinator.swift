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
final class PopupCoordinator: NSObject, WKUIDelegate, WKNavigationDelegate, NSWindowDelegate {
    typealias ExternalOpenHandler = (URL) -> Void

    private weak var parentWebView: WKWebView?
    private var childPanels: [ObjectIdentifier: NSPanel] = [:]
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
