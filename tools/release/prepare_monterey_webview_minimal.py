#!/usr/bin/env python3
"""Stage 4: minimal macOS 12 WebView initialization path.

makeWebView keeps the accepted macOS 13+ construction and adds a deliberately
stock-like macOS 12 branch (no element-fullscreen opt-in, no content-mode
mutation, no UA override, no scrollbar script, no WebKit view-hierarchy
traversal). Stage 6 later collapses the function to the Monterey-only path.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from monterey_transform_lib import (
    read_source,
    replace_once_regex,
    replace_span_once,
    require_absent,
    require_present,
    span_of,
    write_source,
)

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / "FloatTabs/Web/WebViewFactory.swift"
text = read_source(path)

make_start = r"^    static func makeWebView\("
make_end = r"^    static func makeStageZeroWebView\("

replacement = """    static func makeWebView(
        renderingProfile: WebRenderingProfile = .canonicalDefault
    ) -> WKWebView {
        let rendering = renderingProfile.normalized()

        if #available(macOS 13.0, *) {
            let versions = BrowserVersionCatalog.current
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .default()
            configuration.preferences.isElementFullscreenEnabled = true
            configuration.applicationNameForUserAgent = UserAgentProvider.safariApplicationName(
                versions: versions
            )
            configuration.defaultWebpagePreferences.preferredContentMode =
                rendering.effectiveWebsiteMode == .desktop ? .desktop : .mobile
            configuration.userContentController.addUserScript(hiddenScrollbarUserScript())

            let webView = FloatTabsWebView(frame: .zero, configuration: configuration)
            webView.allowsBackForwardNavigationGestures = true
            applyRuntimeRendering(rendering, to: webView, versions: versions)
            configureHiddenScrollers(in: webView)
            return webView
        }

        // Monterey minimal WebView path. Keep first construction deliberately
        // close to a stock WKWebViewConfiguration: no element-fullscreen opt-in,
        // no content-mode mutation, no application-name UA override, no injected
        // scrollbar script, and no traversal of WebKit's internal AppKit view
        // hierarchy. These optional behaviors can be restored individually only
        // after real 12.7.6 validation.
        NSLog("[FloatTabs Monterey] WebViewFactory.makeWebView begin")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = FloatTabsWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.setRendering(
            websiteMode: rendering.effectiveWebsiteMode,
            userPageZoom: rendering.zoom
        )
        NSLog("[FloatTabs Monterey] WebViewFactory.makeWebView ready")
        return webView
    }

"""
text = replace_span_once(
    text,
    make_start,
    make_end,
    replacement,
    label="WebViewFactory.makeWebView minimal dual path",
)

# Later rendering changes must not re-introduce UA/version probing on Monterey.
text = replace_span_once(
    text,
    r"^    static func applyRuntimeRendering\(\n        _ renderingProfile: WebRenderingProfile,\n        to webView: WKWebView\n    \) \{",
    r"^    static func applyRuntimeRendering\(",
    """    static func applyRuntimeRendering(
        _ renderingProfile: WebRenderingProfile,
        to webView: WKWebView
    ) {
        if #available(macOS 13.0, *) {
            applyRuntimeRendering(
                renderingProfile,
                to: webView,
                versions: .current
            )
            return
        }

        let rendering = renderingProfile.normalized()
        if let floatTabsWebView = webView as? FloatTabsWebView {
            floatTabsWebView.setRendering(
                websiteMode: rendering.effectiveWebsiteMode,
                userPageZoom: rendering.zoom
            )
        } else {
            webView.pageZoom = rendering.zoom
        }
    }

""",
    label="WebViewFactory.applyRuntimeRendering dual path",
)

text = replace_once_regex(
    text,
    r"    static func configureHiddenScrollers\(in webView: WKWebView\) \{\s*"
    r"for scrollView in descendantScrollViews\(in: webView\) \{\s*"
    r"guard needsHiddenScrollerConfiguration\(scrollView\) else \{ continue \}\s*"
    r"configureHiddenScrollerStyle\(scrollView\)\s*"
    r"\}\s*"
    r"\}",
    """    static func configureHiddenScrollers(in webView: WKWebView) {
        guard #available(macOS 13.0, *) else { return }
        for scrollView in descendantScrollViews(in: webView) {
            guard needsHiddenScrollerConfiguration(scrollView) else { continue }
            configureHiddenScrollerStyle(scrollView)
        }
    }""",
    label="WebViewFactory.configureHiddenScrollers dual path",
)
write_source(path, text)

prepared = read_source(path)
for item in [
    "Monterey minimal WebView path",
    "guard #available(macOS 13.0, *) else { return }",
    "[FloatTabs Monterey] WebViewFactory.makeWebView begin",
    "configuration.defaultWebpagePreferences.preferredContentMode =",
]:
    require_present(prepared, item, label="Monterey WebView hardening marker")

# Verify the macOS 12 path itself contains none of the optional configuration.
minimal = span_of(
    prepared,
    r"// Monterey minimal WebView path",
    r"^    static func makeStageZeroWebView\(",
    label="Monterey minimal path span",
)
for forbidden in [
    "isElementFullscreenEnabled",
    "preferredContentMode",
    "applicationNameForUserAgent",
    "hiddenScrollbarUserScript",
    "BrowserVersionCatalog.current",
]:
    require_absent(minimal, forbidden, label=f"{forbidden} in Monterey minimal WebView path")

print("Applied Monterey minimal WebView initialization path while preserving macOS 13+ behavior.")
