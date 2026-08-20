#!/usr/bin/env python3
"""Stage 7: Candidate G native Monterey popup/auth context.

This stage runs after Candidate F's six build-time transforms. It restores
native WKWebView child construction for automatic HTTP(S)/about popups while
keeping the primary slot navigation observer, one-shot inferred HTTP fallback,
and the explicit Website Mode UI contract from Candidate F.
"""

import re
from pathlib import Path

from monterey_transform_lib import (
    read_source,
    replace_exact_once,
    replace_once_regex,
    replace_span_once,
    require_absent,
    require_present,
    span_of,
    write_source,
)

ROOT = Path(__file__).resolve().parents[2]
DOTALL = re.MULTILINE | re.DOTALL


def transform_popup() -> None:
    path = ROOT / "FloatTabs/Web/PopupCoordinator.swift"
    text = read_source(path)

    text = replace_exact_once(
        text,
        "    case currentSlot\n",
        "    case temporaryPopup\n",
        label="Candidate G popup disposition enum",
    )
    text = replace_exact_once(
        text,
        "final class PopupCoordinator: NSObject, WKUIDelegate, WKNavigationDelegate, NSWindowDelegate {",
        "final class PopupCoordinator: NSObject, WKUIDelegate, NSWindowDelegate {",
        label="Candidate G PopupCoordinator native delegate surface",
    )
    text = replace_exact_once(
        text,
        "    private var userFloatingPanels: [ObjectIdentifier: NSPanel] = [:]\n",
        "    private var userFloatingPanels: [ObjectIdentifier: NSPanel] = [:]\n"
        "    private var temporaryPanels: [ObjectIdentifier: NSPanel] = [:]\n",
        label="Candidate G temporary panel storage",
    )
    if "        installCurrentSlotWindowOpenPolicy(on: parentWebView)\n" in text:
        text = replace_exact_once(
            text,
            "        super.init()\n"
            "        installCurrentSlotWindowOpenPolicy(on: parentWebView)\n"
            "        installExplicitLinkContextMenu(on: parentWebView)\n",
            "        super.init()\n",
            label="Candidate G primary popup initialization without scripts",
        )
    text = text.replace(
        "WKUIDelegate/WKNavigationDelegate surface",
        "WKUIDelegate surface",
    )

    disposition = """    static func disposition(
        navigationType: WKNavigationType,
        sourceURL: URL?,
        targetURL: URL?
    ) -> NewBrowsingContextDisposition {
        guard let targetURL else { return .temporaryPopup }

        if targetURL.scheme?.lowercased() == "about" {
            return .temporaryPopup
        }

        guard WebNavigationCoordinator.isWebURL(targetURL) else {
            return .externalBrowser
        }

        _ = navigationType
        _ = sourceURL
        return .temporaryPopup
    }

"""
    text = replace_span_once(
        text,
        r"^    static func disposition\(",
        r"^    /// Returns the user-visible FloatTabs viewport",
        disposition,
        label="Candidate G native popup disposition",
    )

    create_and_helper = """    func webView(
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
        case .temporaryPopup:
            return makeTemporaryPopupWebView(
                configuration: configuration,
                sourceWebView: webView,
                targetURL: targetURL
            )

        case .externalBrowser:
            if let targetURL {
                openExternal(targetURL)
            }
            return nil
        }
    }

    @discardableResult
    func makeTemporaryPopupWebView(
        configuration: WKWebViewConfiguration,
        sourceWebView: WKWebView,
        targetURL: URL?
    ) -> WKWebView {
        let popupWebView = WKWebView(
            frame: .zero,
            configuration: configuration
        )
        popupWebView.allowsBackForwardNavigationGestures = true
        popupWebView.uiDelegate = self

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
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

        temporaryPanels[ObjectIdentifier(popupWebView)] = panel
        panel.makeKeyAndOrderFront(nil)
        return popupWebView
    }

"""
    text = replace_span_once(
        text,
        r"^    func webView\(\n        _ webView: WKWebView,\n        createWebViewWith configuration: WKWebViewConfiguration,",
        r"^    func webView\(\n        _ webView: WKWebView,\n        runOpenPanelWith parameters: WKOpenPanelParameters,",
        create_and_helper,
        label="Candidate G callback configuration popup construction",
    )

    text = replace_span_once(
        text,
        r"^    func webView\(\n        _ webView: WKWebView,\n        decidePolicyFor navigationAction: WKNavigationAction,",
        r"^    func webViewDidClose\(_ webView: WKWebView\) \{",
        "",
        label="Candidate G PopupCoordinator navigation policy removal",
    )

    text = replace_span_once(
        text,
        r"^    func webViewDidClose\(_ webView: WKWebView\) \{",
        r"^    func windowWillClose\(_ notification: Notification\) \{",
        """    func webViewDidClose(_ webView: WKWebView) {
        if temporaryPanels[ObjectIdentifier(webView)] != nil {
            closeTemporaryPopup(webView: webView, restoreFocus: true)
        } else {
            close(webView: webView, restoreFocus: true)
        }
    }

""",
        label="Candidate G temporary popup close callback",
    )

    text = replace_span_once(
        text,
        r"^    func windowWillClose\(_ notification: Notification\) \{",
        r"^    func closeAll\(\) \{",
        """    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              let webView = panel.contentView as? WKWebView else {
            return
        }

        let id = ObjectIdentifier(webView)
        if temporaryPanels.removeValue(forKey: id) != nil {
            restoreParentFocus()
            return
        }

        guard userFloatingPanels.removeValue(forKey: id) != nil else {
            return
        }
        linkContextCoordinators.removeValue(forKey: id)?.invalidate()
        restoreParentFocus()
    }

""",
        label="Candidate G temporary and explicit panel close cleanup",
    )

    text = replace_span_once(
        text,
        r"^    func closeAll\(\) \{",
        r"^    @discardableResult\n    func openUserFloatingWindow\(",
        """    func closeAll() {
        let temporary = Array(temporaryPanels.keys)
        for id in temporary {
            if let webView = temporaryPanels[id]?.contentView as? WKWebView {
                closeTemporaryPopup(webView: webView, restoreFocus: false)
            }
        }

        let explicit = Array(userFloatingPanels.keys)
        for id in explicit {
            if let webView = userFloatingPanels[id]?.contentView as? WKWebView {
                close(webView: webView, restoreFocus: false)
            }
        }

        if let parentWebView {
            let id = ObjectIdentifier(parentWebView)
            linkContextCoordinators.removeValue(forKey: id)?.invalidate()
        }
        restoreParentFocus()
    }

""",
        label="Candidate G closeAll panel lifecycle",
    )

    text = replace_span_once(
        text,
        r"^        let rendering: WebRenderingProfile\n",
        r"^        let sourceSize = Self\.visibleSourceSize",
        """        let floatingWebView = WebViewFactory.makeWebView()
        floatingWebView.allowsBackForwardNavigationGestures = true
        floatingWebView.uiDelegate = self
        installExplicitLinkContextMenu(on: floatingWebView)

""",
        label="Candidate G explicit floating WebView baseline",
    )
    text = replace_span_once(
        text,
        r"^    private func installCurrentSlotWindowOpenPolicy\(on webView: WKWebView\) \{",
        r"^    private func close\(webView: WKWebView, restoreFocus: Bool\) \{",
        """    private func closeTemporaryPopup(webView: WKWebView, restoreFocus: Bool) {
        let id = ObjectIdentifier(webView)
        let panel = temporaryPanels.removeValue(forKey: id)
        panel?.orderOut(nil)
        panel?.close()
        if restoreFocus {
            restoreParentFocus()
        }
    }

""",
        label="Candidate G temporary popup close helper",
    )
    text = replace_exact_once(
        text,
        "    var userFloatingWindowCount: Int {\n        userFloatingPanels.count\n    }\n",
        "    var userFloatingWindowCount: Int {\n        userFloatingPanels.count\n    }\n\n"
        "    var temporaryPopupWindowCount: Int {\n        temporaryPanels.count\n    }\n",
        label="Candidate G temporary popup count",
    )
    write_source(path, text)


def transform_navigation() -> None:
    observer_path = ROOT / "FloatTabs/Web/SlotNavigationObserver.swift"
    text = read_source(observer_path)
    text = replace_span_once(
        text,
        r"^    func webView\(\n        _ webView: WKWebView,\n        didFail navigation: WKNavigation!,",
        r"^    func webView\(\n        _ webView: WKWebView,\n        didFailProvisionalNavigation navigation: WKNavigation!,",
        """    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        let nsError = error as NSError
        NSLog(
            "[FloatTabs Monterey] navigation failure slot=%@ domain=%@ code=%ld",
            slotID.uuidString,
            nsError.domain,
            nsError.code
        )
        _ = webView
        _ = navigation
    }

""",
        label="Candidate G navigation failure logging",
    )
    text = replace_exact_once(
        text,
        "        let failingURL = ((error as NSError).userInfo[\"NSErrorFailingURLStringKey\"] as? String)\n"
        "            .flatMap { URL(string: $0) }\n"
        "            ?? webView.url\n",
        "        let failingURL = ((error as NSError).userInfo[\"NSErrorFailingURLStringKey\"] as? String)\n"
        "            .flatMap { URL(string: $0) }\n"
        "            ?? webView.url\n"
        "        let nsError = error as NSError\n"
        "        NSLog(\n"
        "            \"[FloatTabs Monterey] provisional failure slot=%@ domain=%@ code=%ld failingURL=%@\",\n"
        "            slotID.uuidString,\n"
        "            nsError.domain,\n"
        "            nsError.code,\n"
        "            failingURL?.absoluteString ?? \"<nil>\"\n"
        "        )\n",
        label="Candidate G provisional failure logging",
    )
    text = replace_exact_once(
        text,
        '        NSLog("[FloatTabs Monterey] navigation committed slot=%@", slotID.uuidString)\n',
        '        NSLog("[FloatTabs Monterey] navigation committed slot=%@ url=%@", slotID.uuidString, url.absoluteString)\n',
        label="Candidate G committed URL logging",
    )
    write_source(observer_path, text)

    pool_path = ROOT / "FloatTabs/Web/WebViewPool.swift"
    text = read_source(pool_path)
    text = replace_exact_once(
        text,
        "        load(webView, URLRequest(url: url))\n",
        "        NSLog(\"[FloatTabs Monterey] navigation submitted slot=%@ url=%@\", slotID.uuidString, url.absoluteString)\n"
        "        load(webView, URLRequest(url: url))\n",
        label="Candidate G submitted navigation logging",
    )
    old_observer_tail = """            onContentProcessTermination: { [weak self] slotID in
                self?.handleContentProcessTermination(slotID: slotID)
            }
"""
    new_observer_tail = """            onContentProcessTermination: { [weak self] slotID in
                self?.handleContentProcessTermination(slotID: slotID)
            },
            loadHandler: { [weak self] webView, url in
                guard let self else { return }
                NSLog("[FloatTabs Monterey] navigation retry slot=%@ url=%@", profile.id.uuidString, url.absoluteString)
                self.load(
                    webView,
                    URLRequest(
                        url: url,
                        cachePolicy: .useProtocolCachePolicy,
                        timeoutInterval: 60
                    )
                )
            }
"""
    text = replace_exact_once(
        text,
        old_observer_tail,
        new_observer_tail,
        label="Candidate G weak pool load handler",
    )
    write_source(pool_path, text)


def transform_ui() -> None:
    path = ROOT / "FloatTabs/UI/WebAppEditorController.swift"
    text = read_source(path)
    ui_enum = """enum MontereyCompatibilityUI {
    static let websiteModeEnabled = true
    static let browserIdentityEnabled = false
    static let customUserAgentEnabled = false
    static let zoomEnabled = false
    static let effectiveUserAgentPreview = "System WebKit · Monterey Compatibility"
}

"""
    text = replace_once_regex(
        text,
        r"^private final class RenderingForm",
        ui_enum + "private final class RenderingForm",
        label="Candidate G honest compatibility UI contract",
    )
    text = replace_exact_once(
        text,
        "        identityPopup.addItems(withTitles: BrowserIdentity.allCases.map(\\.displayName))\n"
        "        if let index = BrowserIdentity.allCases.firstIndex(of: rendering.browserIdentity) {\n"
        "            identityPopup.selectItem(at: index)\n"
        "        }\n",
        "        identityPopup.addItem(withTitle: MontereyCompatibilityUI.effectiveUserAgentPreview)\n"
        "        identityPopup.selectItem(at: 0)\n",
        label="Candidate G identity UI replacement",
    )
    text = replace_exact_once(
        text,
        '        customUAField.placeholderString = "Mozilla/5.0 …"\n',
        '        customUAField.placeholderString = "Unavailable in Monterey Compatibility"\n',
        label="Candidate G custom UA placeholder",
    )
    text = replace_exact_once(
        text,
        "        orientationPopup.toolTip = devicePopup.toolTip\n",
        "        orientationPopup.toolTip = devicePopup.toolTip\n"
        "        zoomPopup.isEnabled = MontereyCompatibilityUI.zoomEnabled\n"
        "        zoomPopup.toolTip = \"Zoom is unavailable in Monterey Compatibility.\"\n"
        "        identityPopup.isEnabled = MontereyCompatibilityUI.browserIdentityEnabled\n"
        "        identityPopup.toolTip = \"Browser Identity is unavailable in Monterey Compatibility.\"\n"
        "        customUAField.isEditable = MontereyCompatibilityUI.customUserAgentEnabled\n"
        "        customUAField.isEnabled = MontereyCompatibilityUI.customUserAgentEnabled\n"
        "        customUAField.toolTip = \"Custom User Agent is unavailable in Monterey Compatibility.\"\n",
        label="Candidate G disabled runtime-only controls",
    )
    text = replace_exact_once(
        text,
        "        let identityIndex = identityPopup.indexOfSelectedItem\n",
        "",
        label="Candidate G persisted identity selection",
    )
    text = replace_exact_once(
        text,
        "              ZoomSteps.values.indices.contains(zoomIndex),\n              BrowserIdentity.allCases.indices.contains(identityIndex),\n              DeviceOrientation.allCases.indices.contains(orientationIndex) else {",
        "              ZoomSteps.values.indices.contains(zoomIndex),\n              DeviceOrientation.allCases.indices.contains(orientationIndex) else {",
        label="Candidate G UI value validation",
    )
    text = replace_exact_once(
        text,
        "        let identity = BrowserIdentity.allCases[identityIndex]\n",
        "        let identity = initialRendering.browserIdentity\n",
        label="Candidate G persisted browser identity",
    )
    text = replace_span_once(
        text,
        r"^        let customUA: String\?\n",
        r"^        let deviceID: String\?\n",
        "        let customUA: String? = initialRendering.customUserAgent\n\n",
        label="Candidate G persisted custom UA metadata",
    )
    text = replace_exact_once(
        text,
        "            zoom: ZoomSteps.values[zoomIndex]\n",
        "            zoom: initialRendering.zoom\n",
        label="Candidate G persisted zoom metadata",
    )
    text = replace_span_once(
        text,
        r"^    private func updateAutomaticIdentityTitle\(\) \{",
        r"^    private func updateCustomFieldEditability\(\) \{",
        """    private func updateAutomaticIdentityTitle() {
        identityPopup.item(at: 0)?.title = MontereyCompatibilityUI.effectiveUserAgentPreview
    }

""",
        label="Candidate G identity preview title",
    )
    text = replace_span_once(
        text,
        r"^    private func updateCustomUAEditability\(\) \{",
        r"^    private func updateEffectiveUAPreview\(\) \{",
        """    private func updateCustomUAEditability() {
        customUAField.isEditable = MontereyCompatibilityUI.customUserAgentEnabled
        customUAField.isEnabled = MontereyCompatibilityUI.customUserAgentEnabled
        customUAField.textColor = .secondaryLabelColor
    }

""",
        label="Candidate G custom UA honesty",
    )
    text = replace_span_once(
        text,
        r"^    private func updateEffectiveUAPreview\(\) \{",
        r"^    private static func label\(_ text: String\) -> NSTextField \{",
        """    private func updateEffectiveUAPreview() {
        effectiveUAField.stringValue = MontereyCompatibilityUI.effectiveUserAgentPreview
        effectiveUAField.toolTip = MontereyCompatibilityUI.effectiveUserAgentPreview
    }

""",
        label="Candidate G effective UA preview",
    )
    write_source(path, text)


def transform_tests() -> None:
    path = ROOT / "FloatTabsTests/WebViewPoolTests.swift"
    text = read_source(path)
    popup_tests = """    func testPopupRoutingUsesTemporaryContextForSameSiteWebURL() {
        XCTAssertEqual(
            PopupCoordinator.disposition(
                navigationType: .linkActivated,
                sourceURL: URL(string: "https://www.bilibili.com/"),
                targetURL: URL(string: "https://bilibili.com/video/BV123")
            ),
            .temporaryPopup
        )
    }

    func testPopupRoutingUsesTemporaryContextForCrossSiteWebURL() {
        XCTAssertEqual(
            PopupCoordinator.disposition(
                navigationType: .linkActivated,
                sourceURL: URL(string: "https://example.com"),
                targetURL: URL(string: "https://developer.apple.com")
            ),
            .temporaryPopup
        )
    }

    func testPopupRoutingUsesTemporaryContextForScriptedAuthURL() {
        XCTAssertEqual(
            PopupCoordinator.disposition(
                navigationType: .other,
                sourceURL: URL(string: "https://example.com"),
                targetURL: URL(string: "https://accounts.example-idp.com/oauth")
            ),
            .temporaryPopup
        )
    }

    func testPopupRoutingUsesTemporaryContextForAboutAndMissingURL() {
        XCTAssertEqual(
            PopupCoordinator.disposition(
                navigationType: .other,
                sourceURL: URL(string: "https://example.com"),
                targetURL: URL(string: "about:blank")
            ),
            .temporaryPopup
        )
        XCTAssertEqual(
            PopupCoordinator.disposition(
                navigationType: .other,
                sourceURL: URL(string: "https://example.com"),
                targetURL: nil
            ),
            .temporaryPopup
        )
    }

    func testTemporaryPopupUsesCallbackConfigurationAndNilNavigationDelegate() {
        _ = NSApplication.shared
        let source = WebViewFactory.makeWebView()
        let sourceWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        sourceWindow.contentView = source
        sourceWindow.makeKeyAndOrderFront(nil)

        let coordinator = PopupCoordinator(parentWebView: source)
        let configuration = WKWebViewConfiguration()
        let popup = coordinator.makeTemporaryPopupWebView(
            configuration: configuration,
            sourceWebView: source,
            targetURL: URL(string: "https://accounts.example-idp.com/oauth")
        )

        XCTAssertTrue(popup.configuration.processPool === configuration.processPool)
        XCTAssertFalse(popup is FloatTabsWebView)
        XCTAssertNil(popup.navigationDelegate)
        XCTAssertTrue(popup.uiDelegate === coordinator)
        XCTAssertTrue(popup.allowsBackForwardNavigationGestures)
        XCTAssertEqual(coordinator.temporaryPopupWindowCount, 1)

        coordinator.closeAll()
        XCTAssertEqual(coordinator.temporaryPopupWindowCount, 0)
        sourceWindow.close()
    }

"""
    text = replace_span_once(
        text,
        r"^    func testPopupRoutingKeepsSameSiteContextInCurrentSlot\(\) \{",
        r"^    func testPopupRoutingHandsNonWebSchemeToSystem\(\) \{",
        popup_tests,
        label="Candidate G generated popup tests",
    )
    text = replace_exact_once(
        text,
        "        XCTAssertEqual(floating.customUserAgent, source.customUserAgent)\n"
        "        XCTAssertEqual(coordinator.userFloatingWindowCount, 1)\n",
        "        XCTAssertTrue((floating.customUserAgent ?? \"\").isEmpty)\n"
        "        XCTAssertNil(floating.navigationDelegate)\n"
        "        XCTAssertEqual(coordinator.userFloatingWindowCount, 1)\n",
        label="Candidate G explicit floating test contract",
    )
    ui_test = """    func testMontereyCompatibilityUIIsHonestAboutRuntimeFeatures() {
        XCTAssertTrue(MontereyCompatibilityUI.websiteModeEnabled)
        XCTAssertFalse(MontereyCompatibilityUI.browserIdentityEnabled)
        XCTAssertFalse(MontereyCompatibilityUI.customUserAgentEnabled)
        XCTAssertFalse(MontereyCompatibilityUI.zoomEnabled)
        XCTAssertTrue(MontereyCompatibilityUI.effectiveUserAgentPreview.contains("System WebKit"))
        XCTAssertFalse(MontereyCompatibilityUI.effectiveUserAgentPreview.contains("Chrome"))
        XCTAssertFalse(MontereyCompatibilityUI.effectiveUserAgentPreview.contains("iPhone"))
    }

"""
    text = replace_once_regex(
        text,
        r"^    func testUploadPanelPolicyForSingleFile\(\) \{",
        ui_test + "    func testUploadPanelPolicyForSingleFile() {",
        label="Candidate G generated UI honesty test",
    )
    write_source(path, text)


def verify_contract() -> None:
    popup = read_source(ROOT / "FloatTabs/Web/PopupCoordinator.swift")
    pool = read_source(ROOT / "FloatTabs/Web/WebViewPool.swift")
    observer = read_source(ROOT / "FloatTabs/Web/SlotNavigationObserver.swift")
    ui = read_source(ROOT / "FloatTabs/UI/WebAppEditorController.swift")
    tests = read_source(ROOT / "FloatTabsTests/WebViewPoolTests.swift")

    for required in ["case temporaryPopup", "case externalBrowser"]:
        require_present(popup, required, label="Candidate G popup disposition")
    for forbidden in [
        "case currentSlot",
        "WKNavigationDelegate",
        "decidePolicyFor navigationAction",
        "decidePolicyFor navigationResponse",
        "floatingWebView.navigationDelegate = self",
        "floatingWebView.customUserAgent =",
        "installCurrentSlotWindowOpenPolicy",
    ]:
        require_absent(popup, forbidden, label=f"Candidate G popup isolation: {forbidden}")

    helper = span_of(
        popup,
        r"^    func makeTemporaryPopupWebView\(",
        r"^    func webView\(\n        _ webView: WKWebView,\n        runOpenPanelWith",
        label="Candidate G temporary popup helper",
    )
    for required in [
        "let popupWebView = WKWebView(\n            frame: .zero,\n            configuration: configuration\n        )",
        "popupWebView.allowsBackForwardNavigationGestures = true",
        "popupWebView.uiDelegate = self",
        "temporaryPanels[ObjectIdentifier(popupWebView)] = panel",
    ]:
        require_present(helper, required, label="Candidate G temporary popup helper")
    for forbidden in [
        "WKWebViewConfiguration()",
        "WebViewFactory.makeWebView",
        "customUserAgent",
        "preferredContentMode",
        "pageZoom",
        "addUserScript",
        "userContentController.add",
        "navigationDelegate =",
        ".load(",
    ]:
        require_absent(helper, forbidden, label=f"Candidate G temporary popup customization: {forbidden}")

    create = span_of(
        popup,
        r"^    func webView\(\n        _ webView: WKWebView,\n        createWebViewWith configuration",
        r"^    @discardableResult\n    func makeTemporaryPopupWebView",
        label="Candidate G createWebViewWith",
    )
    require_present(create, "case .temporaryPopup", label="Candidate G callback popup branch")
    require_present(create, "return makeTemporaryPopupWebView", label="Candidate G callback popup return")
    require_absent(create, ".load(", label="Candidate G callback manual load")

    require_present(pool, "private var navigationObservers: [UUID: MontereyNavigationObserver]", label="Candidate G primary observer storage")
    require_present(pool, "let observer = MontereyNavigationObserver(", label="Candidate G primary observer")
    require_present(pool, "webView.uiDelegate = popupCoordinator", label="Candidate G primary UI delegate")
    require_present(pool, "loadHandler: { [weak self]", label="Candidate G weak retry handler")
    require_present(pool, "navigation submitted slot=", label="Candidate G submitted navigation log")
    require_absent(pool, "userContentController.add", label="Candidate G primary script-message injection")

    for required in [
        "provisional failure slot=",
        "navigation committed slot=%@ url=%@",
        "pendingHTTPEntryFallback",
        "static func httpFallbackURL",
    ]:
        require_present(observer, required, label="Candidate G observer contract")
    require_absent(observer, "decidePolicyFor", label="Candidate G observer policy restoration")

    for required in [
        "static let websiteModeEnabled = true",
        "static let browserIdentityEnabled = false",
        "static let customUserAgentEnabled = false",
        "static let zoomEnabled = false",
        "System WebKit · Monterey Compatibility",
    ]:
        require_present(ui, required, label="Candidate G honest UI contract")
    require_absent(ui, "UserAgentProvider.userAgent(", label="Candidate G dynamic UA preview")
    for required in [
        "testTemporaryPopupUsesCallbackConfigurationAndNilNavigationDelegate",
        "testMontereyCompatibilityUIIsHonestAboutRuntimeFeatures",
        ".temporaryPopup",
    ]:
        require_present(tests, required, label="Candidate G generated test contract")

    source_path = ROOT / "FloatTabs/Web/PopupCoordinator.swift"
    require_absent(
        read_source(source_path),
        "navigationDelegate = self",
        label="Candidate G PopupCoordinator navigation assignment",
    )


def main() -> None:
    transform_popup()
    transform_navigation()
    transform_ui()
    transform_tests()
    verify_contract()
    print("Applied Candidate G native Monterey popup/auth context and honest UI contract.")


if __name__ == "__main__":
    main()
