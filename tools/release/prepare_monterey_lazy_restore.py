#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: Path, old: str, new: str, marker: str) -> None:
    text = path.read_text()
    if marker in text:
        return
    if old not in text:
        raise SystemExit(f"error: expected Monterey runtime-hardening context not found in {path}")
    path.write_text(text.replace(old, new, 1))


# Do not instantiate a saved WKWebView synchronously while AppCoordinator is
# still constructing the accessory app. A persisted profile can therefore no
# longer turn a WebKit runtime failure into an app-launch crash loop. The first
# explicit FloatTabs presentation still calls synchronizeSlotState().
panel = ROOT / "FloatTabs/Panel/PanelController.swift"
replace_once(
    panel,
    '''        tabStore.onChange = { [weak self] in
            self?.synchronizeSlotState()
        }
        synchronizeSlotState()
    }
''',
    '''        tabStore.onChange = { [weak self] in
            self?.synchronizeSlotState()
        }
        // Monterey lazy restore: do not create/load a saved WKWebView while
        // PanelController itself is being initialized. showFloatTabs() performs
        // the first full synchronization after the shell has been requested.
        NSLog("[FloatTabs Monterey] PanelController initialized without WebView restore")
    }
''',
    "Monterey lazy restore: do not create/load a saved WKWebView",
)

# A typed address used to be persisted before WebKit was even asked to navigate.
# On a runtime crash that made the same URL auto-load on every later start. In
# the compatibility build, navigation begins first and the navigation observer
# persists only a URL that WebKit actually commits.
replace_once(
    panel,
    '''        tabStore.updateCurrentURL(id: id, url: normalized.url)
        webViewPool.navigate(
            slotID: id,
            to: normalized.url,
            allowHTTPEntryFallback: normalized.schemeWasInferred
        )
''',
    '''        NSLog("[FloatTabs Monterey] address commit begin slot=%@", id.uuidString)
        webViewPool.navigate(
            slotID: id,
            to: normalized.url,
            allowHTTPEntryFallback: normalized.schemeWasInferred
        )
        NSLog("[FloatTabs Monterey] address navigation submitted slot=%@", id.uuidString)
''',
    "[FloatTabs Monterey] address commit begin",
)

# Avoid url-KVO persistence at provisional-navigation time. Persist currentURL
# only after WKNavigationDelegate reports a real commit.
observer = ROOT / "FloatTabs/Web/SlotNavigationObserver.swift"
replace_once(
    observer,
    '''        observation = webView.observe(\\.url, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      let url = self.webView?.url,
                      WebAppURL.isSafe(url) else {
                    return
                }
                self.onURLChange(self.slotID, url)
            }
        }

        webView.navigationDelegate = self
''',
    '''        // Monterey navigation safe mode: do not persist provisional URL KVO
        // changes. didCommit below is the durability boundary for currentURL.
        NSLog("[FloatTabs Monterey] navigation observer ready slot=%@", slotID.uuidString)
        webView.navigationDelegate = self
''',
    "Monterey navigation safe mode: do not persist provisional URL KVO",
)

replace_once(
    observer,
    '''    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        restoreWebsiteMode(in: webView)
        restoreHiddenScrollerPolicy(in: webView)
        // Once an https entry commits, later in-page failures can never inherit
        // the entry-only downgrade permission.
        pendingHTTPEntryFallback = nil
    }
''',
    '''    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        restoreWebsiteMode(in: webView)
        restoreHiddenScrollerPolicy(in: webView)
        if let url = webView.url, WebAppURL.isSafe(url) {
            NSLog("[FloatTabs Monterey] navigation committed slot=%@", slotID.uuidString)
            onURLChange(slotID, url)
        }
        // Once an https entry commits, later in-page failures can never inherit
        // the entry-only downgrade permission.
        pendingHTTPEntryFallback = nil
    }
''',
    "[FloatTabs Monterey] navigation committed slot=",
)

# Breadcrumbs deliberately log only lifecycle stages and slot IDs, never URLs or
# page contents. If real Monterey still terminates, Terminal output will reveal
# whether the failure occurs in WKWebView construction, observer setup, popup
# setup, or the first load submission.
pool = ROOT / "FloatTabs/Web/WebViewPool.swift"
replace_once(
    pool,
    '''    ) -> WKWebView {
        let rendering = profile.renderingProfile.normalized()
        let runtimeRendering = SiteCompatibilityPolicy.runtimeRendering(
            for: rendering,
            navigationURL: navigationURL
        )
        let webView = WebViewFactory.makeWebView(renderingProfile: runtimeRendering)
        let observer = SlotNavigationObserver(
''',
    '''    ) -> WKWebView {
        NSLog("[FloatTabs Monterey] createWebView begin slot=%@", profile.id.uuidString)
        let rendering = profile.renderingProfile.normalized()
        let runtimeRendering = SiteCompatibilityPolicy.runtimeRendering(
            for: rendering,
            navigationURL: navigationURL
        )
        let webView = WebViewFactory.makeWebView(renderingProfile: runtimeRendering)
        NSLog("[FloatTabs Monterey] createWebView factory ready slot=%@", profile.id.uuidString)
        let observer = SlotNavigationObserver(
''',
    "[FloatTabs Monterey] createWebView begin slot=",
)

replace_once(
    pool,
    '''        let popupCoordinator = PopupCoordinator(
            parentWebView: webView,
            downloadCoordinator: downloadCoordinator
        )
        webView.uiDelegate = popupCoordinator
''',
    '''        NSLog("[FloatTabs Monterey] createWebView observer ready slot=%@", profile.id.uuidString)
        let popupCoordinator = PopupCoordinator(
            parentWebView: webView,
            downloadCoordinator: downloadCoordinator
        )
        NSLog("[FloatTabs Monterey] createWebView popup ready slot=%@", profile.id.uuidString)
        webView.uiDelegate = popupCoordinator
''',
    "[FloatTabs Monterey] createWebView popup ready slot=",
)

replace_once(
    pool,
    '''        load(webView, request)
        return webView
    }
''',
    '''        NSLog("[FloatTabs Monterey] createWebView before load slot=%@", profile.id.uuidString)
        load(webView, request)
        NSLog("[FloatTabs Monterey] createWebView load submitted slot=%@", profile.id.uuidString)
        return webView
    }
''',
    "[FloatTabs Monterey] createWebView before load slot=",
)

# Verify the dangerous pre-navigation persistence and eager-init call are gone
# from the specific compatibility seams we patched.
panel_text = panel.read_text()
commit_start = panel_text.find("    private func commitAddress(")
commit_end = panel_text.find("    private func copyAddressToPasteboard", commit_start)
if commit_start < 0 or commit_end < 0:
    raise SystemExit("error: commitAddress boundaries not found after Monterey patch")
if "tabStore.updateCurrentURL" in panel_text[commit_start:commit_end]:
    raise SystemExit("error: address URL is still persisted before Monterey navigation")

observer_text = observer.read_text()
if "webView.observe(\\.url" in observer_text:
    raise SystemExit("error: provisional URL KVO persistence survived Monterey patch")
if "onURLChange(slotID, url)" not in observer_text:
    raise SystemExit("error: committed-navigation persistence is missing")

for required in [
    "Monterey lazy restore: do not create/load a saved WKWebView",
    "[FloatTabs Monterey] createWebView before load",
    "[FloatTabs Monterey] navigation committed",
]:
    combined = panel_text + observer_text + pool.read_text()
    if required not in combined:
        raise SystemExit(f"error: Monterey runtime hardening marker missing: {required}")

print("Applied Monterey lazy restore, committed-URL persistence, and runtime breadcrumbs.")
