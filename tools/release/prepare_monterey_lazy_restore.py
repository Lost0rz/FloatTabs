#!/usr/bin/env python3
"""Stage 5: macOS-12-only lazy restore, committed-URL persistence, breadcrumbs.

Startup never creates a saved WKWebView before explicit presentation; typed
addresses and navigation observers persist only committed URLs; WebViewPool
logs lifecycle breadcrumbs around first construction and first load.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from monterey_transform_lib import (
    read_source,
    replace_once_regex,
    replace_span_once,
    require_present,
    write_source,
)

ROOT = Path(__file__).resolve().parents[2]

# Do not instantiate a saved WKWebView synchronously on macOS 12 while
# AppCoordinator is still constructing the accessory app. macOS 13+ keeps the
# accepted eager-restore behavior unchanged.
panel = ROOT / "FloatTabs/Panel/PanelController.swift"
text = read_source(panel)
text = replace_once_regex(
    text,
    r"        tabStore\.onChange = \{ \[weak self\] in\s*"
    r"self\?\.synchronizeSlotState\(\)\s*"
    r"\}\s*"
    r"synchronizeSlotState\(\)\s*"
    r"\}",
    """        tabStore.onChange = { [weak self] in
            self?.synchronizeSlotState()
        }
        if #available(macOS 13.0, *) {
            synchronizeSlotState()
        } else {
            // Monterey lazy restore: do not create/load a saved WKWebView while
            // PanelController itself is being initialized. showFloatTabs()
            // performs the first full synchronization after user presentation.
            NSLog("[FloatTabs Monterey] PanelController initialized without WebView restore")
        }
    }""",
    label="PanelController lazy restore",
)

# Keep the accepted macOS 13+ pre-navigation runtime-state update. On Monterey,
# navigation starts without persisting the candidate URL; didCommit below is the
# durability boundary, preventing a failed WebKit load from poisoning startup.
text = replace_once_regex(
    text,
    r"        tabStore\.updateCurrentURL\(id: id, url: normalized\.url\)\s*"
    r"webViewPool\.navigate\(\s*"
    r"slotID: id,\s*"
    r"to: normalized\.url,\s*"
    r"allowHTTPEntryFallback: normalized\.schemeWasInferred\s*"
    r"\)",
    """        if #available(macOS 13.0, *) {
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
        }""",
    label="PanelController committed-address navigation",
)
write_source(panel, text)

# Preserve standard URL KVO on macOS 13+. Monterey persists only committed URLs.
observer = ROOT / "FloatTabs/Web/SlotNavigationObserver.swift"
text = read_source(observer)
text = replace_once_regex(
    text,
    r"        observation = webView\.observe\(\\\.url, options: \[\.new\]\) \{ \[weak self\] _, _ in\s*"
    r"Task \{ @MainActor \[weak self\] in\s*"
    r"guard let self,\s*"
    r"let url = self\.webView\?\.url,\s*"
    r"WebAppURL\.isSafe\(url\) else \{\s*"
    r"return\s*"
    r"\}\s*"
    r"self\.onURLChange\(self\.slotID, url\)\s*"
    r"\}\s*"
    r"\}\s*"
    r"\n\s*webView\.navigationDelegate = self",
    """        if #available(macOS 13.0, *) {
            observation = webView.observe(\\.url, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self,
                          let url = self.webView?.url,
                          WebAppURL.isSafe(url) else {
                        return
                    }
                    self.onURLChange(self.slotID, url)
                }
            }
        } else {
            // Monterey navigation safe mode: do not persist provisional URL KVO
            // changes. didCommit below is the durability boundary for currentURL.
            NSLog("[FloatTabs Monterey] navigation observer ready slot=%@", slotID.uuidString)
        }

        webView.navigationDelegate = self""",
    label="SlotNavigationObserver provisional-URL KVO guard",
)

text = replace_span_once(
    text,
    r"^    func webView\(_ webView: WKWebView, didCommit navigation: WKNavigation!\) \{",
    r"^    func webView\(_ webView: WKWebView, didFinish navigation: WKNavigation!\) \{",
    """    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        restoreWebsiteMode(in: webView)
        restoreHiddenScrollerPolicy(in: webView)
        if #available(macOS 13.0, *) {
            // URL KVO preserves the accepted modern persistence behavior.
        } else if let url = webView.url, WebAppURL.isSafe(url) {
            NSLog("[FloatTabs Monterey] navigation committed slot=%@", slotID.uuidString)
            onURLChange(slotID, url)
        }
        // Once an https entry commits, later in-page failures can never inherit
        // the entry-only downgrade permission.
        pendingHTTPEntryFallback = nil
    }

""",
    label="SlotNavigationObserver didCommit committed-URL persistence",
)
write_source(observer, text)

# Breadcrumbs deliberately log only lifecycle stages and slot IDs, never URLs or
# page contents. If real Monterey still terminates, Terminal output will reveal
# whether the failure occurs in WKWebView construction, observer setup, popup
# setup, or the first load submission.
pool = ROOT / "FloatTabs/Web/WebViewPool.swift"
text = read_source(pool)
text = replace_once_regex(
    text,
    r"    \) -> WKWebView \{\s*"
    r"let rendering = profile\.renderingProfile\.normalized\(\)\s*"
    r"let runtimeRendering = SiteCompatibilityPolicy\.runtimeRendering\(",
    """    ) -> WKWebView {
        NSLog("[FloatTabs Monterey] createWebView begin slot=%@", profile.id.uuidString)
        let rendering = profile.renderingProfile.normalized()
        let runtimeRendering = SiteCompatibilityPolicy.runtimeRendering(""",
    label="WebViewPool createWebView begin breadcrumb",
)
text = replace_once_regex(
    text,
    r"        let webView = WebViewFactory\.makeWebView\(renderingProfile: runtimeRendering\)\s*"
    r"let observer = SlotNavigationObserver\(",
    """        let webView = WebViewFactory.makeWebView(renderingProfile: runtimeRendering)
        NSLog("[FloatTabs Monterey] createWebView factory ready slot=%@", profile.id.uuidString)
        let observer = SlotNavigationObserver(""",
    label="WebViewPool createWebView factory breadcrumb",
)
text = replace_once_regex(
    text,
    r"        let popupCoordinator = PopupCoordinator\(\s*"
    r"parentWebView: webView,\s*"
    r"downloadCoordinator: downloadCoordinator\s*"
    r"\)\s*"
    r"webView\.uiDelegate = popupCoordinator",
    """        NSLog("[FloatTabs Monterey] createWebView observer ready slot=%@", profile.id.uuidString)
        let popupCoordinator = PopupCoordinator(
            parentWebView: webView,
            downloadCoordinator: downloadCoordinator
        )
        NSLog("[FloatTabs Monterey] createWebView popup ready slot=%@", profile.id.uuidString)
        webView.uiDelegate = popupCoordinator""",
    label="WebViewPool createWebView popup breadcrumb",
)
text = replace_once_regex(
    text,
    r"        load\(webView, request\)\s*"
    r"return webView\s*"
    r"\}",
    """        NSLog("[FloatTabs Monterey] createWebView before load slot=%@", profile.id.uuidString)
        load(webView, request)
        NSLog("[FloatTabs Monterey] createWebView load submitted slot=%@", profile.id.uuidString)
        return webView
    }""",
    label="WebViewPool createWebView load breadcrumb",
)
write_source(pool, text)

# ---------------------------------------------------------------------------
# Post-transform contract for this stage.
# ---------------------------------------------------------------------------
panel_text = read_source(panel)
observer_text = read_source(observer)
pool_text = read_source(pool)

combined = panel_text + observer_text + pool_text
for item in [
    "Monterey lazy restore: do not create/load a saved WKWebView",
    "Monterey navigation safe mode: do not persist provisional URL KVO",
    "[FloatTabs Monterey] navigation committed slot=",
    "[FloatTabs Monterey] createWebView before load slot=",
]:
    require_present(combined, item, label="Monterey runtime hardening marker")

# Modern source semantics must remain present behind macOS 13 availability.
require_present(panel_text, "synchronizeSlotState()", label="modern eager restore")
require_present(
    panel_text,
    "tabStore.updateCurrentURL(id: id, url: normalized.url)",
    label="modern address persistence",
)
require_present(observer_text, "observation = webView.observe(\\.url", label="modern URL KVO")

print("Applied macOS-12-only lazy restore, committed-URL persistence, and runtime breadcrumbs.")
