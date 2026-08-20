#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
path = ROOT / "FloatTabs/Web/WebViewFactory.swift"
text = path.read_text()

marker = "Monterey minimal WebView path"
if marker not in text:
    start = text.find("    static func makeWebView(\n")
    end = text.find("    static func makeStageZeroWebView()", start)
    if start < 0 or end < 0:
        raise SystemExit("error: WebViewFactory.makeWebView boundaries not found")

    replacement = '''    static func makeWebView(
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

'''
    text = text[:start] + replacement + text[end:]

# Later rendering changes must not re-introduce UA/version probing on Monterey.
old_runtime = '''    static func applyRuntimeRendering(
        _ renderingProfile: WebRenderingProfile,
        to webView: WKWebView
    ) {
        applyRuntimeRendering(
            renderingProfile,
            to: webView,
            versions: .current
        )
    }
'''
new_runtime = '''    static func applyRuntimeRendering(
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
'''
if old_runtime in text:
    text = text.replace(old_runtime, new_runtime, 1)
elif new_runtime not in text:
    raise SystemExit("error: applyRuntimeRendering compatibility context not found")

old_scrollers = '''    static func configureHiddenScrollers(in webView: WKWebView) {
        for scrollView in descendantScrollViews(in: webView) {
            guard needsHiddenScrollerConfiguration(scrollView) else { continue }
            configureHiddenScrollerStyle(scrollView)
        }
    }
'''
new_scrollers = '''    static func configureHiddenScrollers(in webView: WKWebView) {
        guard #available(macOS 13.0, *) else { return }
        for scrollView in descendantScrollViews(in: webView) {
            guard needsHiddenScrollerConfiguration(scrollView) else { continue }
            configureHiddenScrollerStyle(scrollView)
        }
    }
'''
if old_scrollers in text:
    text = text.replace(old_scrollers, new_scrollers, 1)
elif new_scrollers not in text:
    raise SystemExit("error: hidden-scroller compatibility context not found")

path.write_text(text)

prepared = path.read_text()
required = [
    "Monterey minimal WebView path",
    "guard #available(macOS 13.0, *) else { return }",
    "[FloatTabs Monterey] WebViewFactory.makeWebView begin",
    "configuration.defaultWebpagePreferences.preferredContentMode =",
]
for item in required:
    if item not in prepared:
        raise SystemExit(f"error: Monterey WebView hardening marker missing: {item}")

# Verify the macOS 12 path itself contains none of the optional configuration.
start = prepared.find("// Monterey minimal WebView path")
end = prepared.find("    static func makeStageZeroWebView()", start)
minimal = prepared[start:end]
for forbidden in [
    "isElementFullscreenEnabled",
    "preferredContentMode",
    "applicationNameForUserAgent",
    "hiddenScrollbarUserScript",
    "BrowserVersionCatalog.current",
]:
    if forbidden in minimal:
        raise SystemExit(f"error: {forbidden} survived in Monterey minimal WebView path")

print("Applied Monterey minimal WebView initialization path while preserving macOS 13+ behavior.")
