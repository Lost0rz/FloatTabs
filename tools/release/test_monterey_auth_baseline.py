#!/usr/bin/env python3
"""Static contract tests for the generated Monterey auth baseline."""

import os
from pathlib import Path

from monterey_transform_lib import read_source, require_absent, require_present


ROOT = Path(
    os.environ.get(
        "FLOATTABS_TRANSFORM_ROOT",
        str(Path(__file__).resolve().parents[2]),
    )
)


def main() -> None:
    delegate = read_source(ROOT / "FloatTabs/App/AppDelegate.swift")
    factory = read_source(ROOT / "FloatTabs/Web/WebViewFactory.swift")

    required_delegate = (
        "WKWebViewConfiguration()",
        "MontereyBrowserDataStoreManager.shared.persistentStore",
        "WKWebsiteDataStore.allWebsiteDataTypes()",
        "modifiedSince: .distantPast",
        "MontereySafariIdentity.applicationName",
        "configuration.applicationNameForUserAgent = applicationName",
        "WKWebView(frame: .zero, configuration: configuration)",
        "assert(webView.customUserAgent == nil)",
        'width: 900, height: 760',
        'window.title = "FloatTabs Monterey Auth Baseline"',
        'https://chatgpt.com/',
    )
    for needle in required_delegate:
        require_present(delegate, needle, label=f"auth-baseline required contract: {needle}")

    forbidden_delegate = (
        "PanelController",
        "WebViewPool",
        "WebPanelContainerView",
        "WebSlotHostView",
        "MontereyNavigationObserver",
        "PopupCoordinator",
        "SlotLifecycleCoordinator",
        "FloatTabsWebView",
        "Website Mode",
        "residency",
        "pageZoom",
        "preferredContentMode",
        "customUserAgent = ",
        "navigationDelegate",
        "uiDelegate",
        "WKNavigationDelegate",
        "WKUIDelegate",
        "evaluateJavaScript",
        "WKUserScript",
        "httpFallback",
        "fullscreen",
        "download",
    )
    for needle in forbidden_delegate:
        require_absent(delegate, needle, label=f"auth-baseline forbidden runtime: {needle}")

    require_present(
        factory,
        "websiteDataStore: WKWebsiteDataStore = .default()",
        label="auth-baseline default persistent store",
    )
    require_present(
        factory,
        "enum MontereySafariIdentity",
        label="auth-baseline public Safari identity",
    )
    print("Monterey auth baseline static contract: PASS")


if __name__ == "__main__":
    main()
