#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_required(path: Path, old: str, new: str, description: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"error: expected {description} context not found in {path}")
    path.write_text(text.replace(old, new, 1))


# ---------------------------------------------------------------------------
# Monterey Compatibility Edition isolation contract
# ---------------------------------------------------------------------------
# This script runs only inside the dedicated Monterey compatibility build.
# It intentionally removes the macOS 13+ runtime branches introduced by the
# compile-compatibility preparation scripts. The standard product keeps those
# behaviors in the untouched repository source / standard release line.
#
# Compatibility Edition = Monterey behavior only.
# Standard Edition      = existing macOS 13+ behavior only.
# ---------------------------------------------------------------------------

# FloatingPanel: Monterey never adopts the macOS-13-only collection behavior.
floating = ROOT / "FloatTabs/Panel/FloatingPanel.swift"
replace_required(
    floating,
    '''    private static var ordinaryCollectionBehavior: NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        if #available(macOS 13.0, *) {
            behavior.insert(.canJoinAllApplications)
        }
        return behavior
    }
''',
    '''    // Monterey Compatibility Edition intentionally keeps a Monterey-only
    // collection behavior. Standard macOS 13+ behavior lives in the standard
    // release and is not carried inside this compatibility package.
    private static let ordinaryCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .ignoresCycle,
    ]
''',
    "dual-path FloatingPanel collection behavior",
)

# Fullscreen: the compatibility edition carries neither the modern observer nor
# the synthetic Monterey polling loop. Preserve the ordinary source-window
# geometry/presentation helpers because they are also required by normal browser
# hosting even when element fullscreen itself is disabled.
fullscreen = ROOT / "FloatTabs/Panel/FullscreenSourceHost.swift"
text = fullscreen.read_text()
old_observe = '''        if #available(macOS 13.0, *) {
            observeModernFullscreenState(of: webView)
        } else {
            // Monterey runtime safe mode: do not start the compatibility polling
            // loop during ordinary WebView creation. The polling implementation
            // is compile-valid but cannot be runtime-validated on GitHub's newer
            // macOS runner. Element fullscreen is disabled for the Monterey
            // compatibility package below, so there is no state to infer here.
            legacyFullscreenPollGeneration &+= 1
        }
'''
new_observe = '''        // Monterey Compatibility Edition: fullscreen observation is disabled.
        // The standard release owns the modern fullscreen implementation.
        legacyFullscreenPollGeneration &+= 1
'''
if old_observe not in text:
    raise SystemExit("error: expected dual-path fullscreen observation context not found")
text = text.replace(old_observe, new_observe, 1)

modern_extension_start = text.find("@available(macOS 13.0, *)\nprivate extension FullscreenWebKitState")
modern_extension_end = text.find("enum FullscreenSourceSessionState", modern_extension_start)
if modern_extension_start < 0 or modern_extension_end < 0:
    raise SystemExit("error: modern FullscreenState adapter boundaries not found")
text = text[:modern_extension_start] + text[modern_extension_end:]

# Remove only the modern observer and the synthetic polling helpers. Do not slice
# through sourceFrame/makeSourceWindow/presentation detection: those helpers are
# ordinary source-host infrastructure and are needed even with fullscreen off.
modern_helper_start = text.find("    @available(macOS 13.0, *)\n    private func observeModernFullscreenState")
legacy_helper_start = text.find("    private func startLegacyFullscreenPolling", modern_helper_start)
if modern_helper_start < 0 or legacy_helper_start < 0:
    raise SystemExit("error: modern fullscreen observer boundaries not found")
text = text[:modern_helper_start] + text[legacy_helper_start:]

legacy_helper_start = text.find("    private func startLegacyFullscreenPolling")
source_frame_start = text.find("    static func sourceFrame(", legacy_helper_start)
if legacy_helper_start < 0 or source_frame_start < 0:
    raise SystemExit("error: legacy polling/source-host helper boundaries not found")
text = text[:legacy_helper_start] + text[source_frame_start:]
fullscreen.write_text(text)

# WebViewFactory: make the compatibility package a Monterey-only implementation
# rather than a dual macOS12/macOS13 binary behavior switch.
web_factory = ROOT / "FloatTabs/Web/WebViewFactory.swift"
text = web_factory.read_text()
start = text.find("    static func makeWebView(\n")
end = text.find("    static func makeStageZeroWebView()", start)
if start < 0 or end < 0:
    raise SystemExit("error: WebViewFactory.makeWebView boundaries not found")
compat_make = '''    static func makeWebView(
        renderingProfile: WebRenderingProfile = .canonicalDefault
    ) -> WKWebView {
        let rendering = renderingProfile.normalized()

        // Monterey Compatibility Edition: keep construction deliberately close
        // to stock WKWebViewConfiguration. The standard release separately owns
        // UA overrides, preferredContentMode, injected scrollbar policy, and
        // element-fullscreen behavior.
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
text = text[:start] + compat_make + text[end:]

old_runtime = '''    static func applyRuntimeRendering(
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
new_runtime = '''    static func applyRuntimeRendering(
        _ renderingProfile: WebRenderingProfile,
        to webView: WKWebView
    ) {
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
if old_runtime not in text:
    raise SystemExit("error: dual-path runtime rendering context not found")
text = text.replace(old_runtime, new_runtime, 1)

old_scrollers = '''    static func configureHiddenScrollers(in webView: WKWebView) {
        guard #available(macOS 13.0, *) else { return }
        for scrollView in descendantScrollViews(in: webView) {
            guard needsHiddenScrollerConfiguration(scrollView) else { continue }
            configureHiddenScrollerStyle(scrollView)
        }
    }
'''
new_scrollers = '''    static func configureHiddenScrollers(in webView: WKWebView) {
        // Monterey Compatibility Edition intentionally leaves WebKit's internal
        // AppKit scroll hierarchy untouched.
    }
'''
if old_scrollers not in text:
    raise SystemExit("error: dual-path hidden-scroller context not found")
text = text.replace(old_scrollers, new_scrollers, 1)
web_factory.write_text(text)

# Panel restore / typed-address persistence: compatibility semantics are used
# unconditionally inside this edition. Standard semantics remain in standard
# source and are not embedded behind an availability branch here.
panel = ROOT / "FloatTabs/Panel/PanelController.swift"
text = panel.read_text()
old_init = '''        if #available(macOS 13.0, *) {
            synchronizeSlotState()
        } else {
            // Monterey lazy restore: do not create/load a saved WKWebView while
            // PanelController itself is being initialized. showFloatTabs()
            // performs the first full synchronization after user presentation.
            NSLog("[FloatTabs Monterey] PanelController initialized without WebView restore")
        }
'''
new_init = '''        // Monterey Compatibility Edition defers saved WebView restoration until
        // explicit presentation; the standard release keeps its own eager path.
        NSLog("[FloatTabs Monterey] PanelController initialized without WebView restore")
'''
if old_init not in text:
    raise SystemExit("error: dual-path PanelController restore context not found")
text = text.replace(old_init, new_init, 1)

old_nav = '''        if #available(macOS 13.0, *) {
            tabStore.updateCurrentURL(id: id, url: normalized.url)
        } else {
            NSLog("[FloatTabs Monterey] address commit begin slot=%@", id.uuidString)
        }
        webViewPool.navigate(
            slotID: id,
            to: normalized.url,
            allowHTTPEntryFallback: normalized.schemeWasInferred
        )
        if #available(macOS 13.0, *) {
            // Preserve the accepted modern navigation/persistence sequence.
        } else {
            NSLog("[FloatTabs Monterey] address navigation submitted slot=%@", id.uuidString)
        }
'''
new_nav = '''        NSLog("[FloatTabs Monterey] address commit begin slot=%@", id.uuidString)
        webViewPool.navigate(
            slotID: id,
            to: normalized.url,
            allowHTTPEntryFallback: normalized.schemeWasInferred
        )
        NSLog("[FloatTabs Monterey] address navigation submitted slot=%@", id.uuidString)
'''
if old_nav not in text:
    raise SystemExit("error: dual-path typed-address context not found")
text = text.replace(old_nav, new_nav, 1)
panel.write_text(text)

observer = ROOT / "FloatTabs/Web/SlotNavigationObserver.swift"
text = observer.read_text()
obs_start = text.find("        if #available(macOS 13.0, *) {\n            observation = webView.observe(\\.url")
obs_end = text.find("\n\n        webView.navigationDelegate = self", obs_start)
if obs_start < 0 or obs_end < 0:
    raise SystemExit("error: dual-path URL observation boundaries not found")
compat_observer = '''        // Monterey Compatibility Edition persists only committed URLs.
        NSLog("[FloatTabs Monterey] navigation observer ready slot=%@", slotID.uuidString)'''
text = text[:obs_start] + compat_observer + text[obs_end:]

old_commit = '''        if #available(macOS 13.0, *) {
            // URL KVO preserves the accepted modern persistence behavior.
        } else if let url = webView.url, WebAppURL.isSafe(url) {
            NSLog("[FloatTabs Monterey] navigation committed slot=%@", slotID.uuidString)
            onURLChange(slotID, url)
        }
'''
new_commit = '''        if let url = webView.url, WebAppURL.isSafe(url) {
            NSLog("[FloatTabs Monterey] navigation committed slot=%@", slotID.uuidString)
            onURLChange(slotID, url)
        }
'''
if old_commit not in text:
    raise SystemExit("error: dual-path committed-URL context not found")
text = text.replace(old_commit, new_commit, 1)
observer.write_text(text)

# Hard isolation assertions. These are intentionally stronger than availability
# checks: the compatibility edition must not contain a second standard runtime
# branch in the areas we are hardening.
prepared_floating = floating.read_text()
prepared_fullscreen = fullscreen.read_text()
prepared_web = web_factory.read_text()
prepared_panel = panel.read_text()
prepared_observer = observer.read_text()

if ".canJoinAllApplications" in prepared_floating:
    raise SystemExit("error: standard macOS 13 collection behavior leaked into compatibility edition")
if "observeModernFullscreenState" in prepared_fullscreen:
    raise SystemExit("error: modern fullscreen observer leaked into compatibility edition")
if "WKWebView.FullscreenState" in prepared_fullscreen:
    raise SystemExit("error: modern FullscreenState API leaked into compatibility edition")
for required_helper in [
    "static func sourceFrame(",
    "static func isWebKitFullscreenPresentationActive(",
    "private static func makeSourceWindow(",
]:
    if required_helper not in prepared_fullscreen:
        raise SystemExit(f"error: ordinary source-host helper was removed: {required_helper}")
for forbidden in [
    "configuration.preferences.isElementFullscreenEnabled = true",
    "configuration.defaultWebpagePreferences.preferredContentMode =",
    "configuration.applicationNameForUserAgent =",
    "BrowserVersionCatalog.current",
]:
    make_end = prepared_web.find("    static func makeStageZeroWebView()")
    if forbidden in prepared_web[:make_end]:
        raise SystemExit(f"error: standard WebView behavior leaked into compatibility edition: {forbidden}")
if "if #available(macOS 13.0, *)" in prepared_panel:
    # PanelController may legitimately contain unrelated availability checks; only
    # reject the ones surrounding the compatibility markers.
    for marker in [
        "PanelController initialized without WebView restore",
        "address commit begin slot=",
    ]:
        marker_index = prepared_panel.find(marker)
        nearby = prepared_panel[max(0, marker_index - 220): marker_index + 220]
        if "if #available(macOS 13.0, *)" in nearby:
            raise SystemExit(f"error: standard runtime branch still surrounds compatibility marker: {marker}")
if "observation = webView.observe(\\.url" in prepared_observer:
    raise SystemExit("error: provisional URL KVO leaked into compatibility edition")

print("Applied isolated Monterey Compatibility Edition runtime semantics.")
