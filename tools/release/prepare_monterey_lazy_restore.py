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


# Do not instantiate a saved WKWebView synchronously on macOS 12 while
# AppCoordinator is still constructing the accessory app. macOS 13+ keeps the
# accepted eager-restore behavior unchanged.
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
        if #available(macOS 13.0, *) {
            synchronizeSlotState()
        } else {
            // Monterey lazy restore: do not create/load a saved WKWebView while
            // PanelController itself is being initialized. showFloatTabs()
            // performs the first full synchronization after user presentation.
            NSLog("[FloatTabs Monterey] PanelController initialized without WebView restore")
        }
    }
''',
    "Monterey lazy restore: do not create/load a saved WKWebView",
)

# Keep the accepted macOS 13+ pre-navigation runtime-state update. On Monterey,
# navigation starts without persisting the candidate URL; didCommit below is the
# durability boundary, preventing a failed WebKit load from poisoning startup.
replace_once(
    panel,
    '''        tabStore.updateCurrentURL(id: id, url: normalized.url)
        webViewPool.navigate(
            slotID: id,
            to: normalized.url,
            allowHTTPEntryFallback: normalized.schemeWasInferred
        )
''',
    '''        if #available(macOS 13.0, *) {
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
''',
    "[FloatTabs Monterey] address commit begin",
)

# Preserve standard URL KVO on macOS 13+. Monterey persists only committed URLs.
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
    '''        if #available(macOS 13.0, *) {
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

panel_text = panel.read_text()
observer_text = observer.read_text()
pool_text = pool.read_text()

required = [
    "Monterey lazy restore: do not create/load a saved WKWebView",
    "Monterey navigation safe mode: do not persist provisional URL KVO",
    "[FloatTabs Monterey] navigation committed slot=",
    "[FloatTabs Monterey] createWebView before load slot=",
]
combined = panel_text + observer_text + pool_text
for item in required:
    if item not in combined:
        raise SystemExit(f"error: Monterey runtime hardening marker missing: {item}")

# Modern source semantics must remain present behind macOS 13 availability.
if "synchronizeSlotState()" not in panel_text:
    raise SystemExit("error: modern eager restore was not preserved")
if "tabStore.updateCurrentURL(id: id, url: normalized.url)" not in panel_text:
    raise SystemExit("error: modern address persistence was not preserved")
if "observation = webView.observe(\\.url" not in observer_text:
    raise SystemExit("error: modern URL KVO was not preserved")

print("Applied macOS-12-only lazy restore, committed-URL persistence, and runtime breadcrumbs.")
