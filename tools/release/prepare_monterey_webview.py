#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: Path, old: str, new: str, marker: str) -> None:
    text = path.read_text()
    if marker in text:
        return
    if old not in text:
        raise SystemExit(f"error: expected Monterey WebKit patch context not found in {path}")
    path.write_text(text.replace(old, new, 1))


source = ROOT / "FloatTabs/Web/WebViewFactory.swift"

# Monterey runtime hardening: WKWebView's private KVC `userAgent` key is not a
# public API contract. A missing KVC key throws an Objective-C exception rather
# than a Swift error, which can terminate the process the first time a Web App
# creates a WKWebView and then repeat on every launch once that profile is saved.
# The Monterey package therefore uses the existing conservative WebKit UA token
# fallback instead of probing the private key. The standard macOS 13+ package is
# untouched by this compatibility preparation.
replace_once(
    source,
    '''    @MainActor
    static func webKitVersion() -> String {
        if let cachedWebKitVersion {
            return cachedWebKitVersion
        }

        let webView = WKWebView(frame: .zero)
        guard let nativeUserAgent = webView.value(forKey: "userAgent") as? String,
              let version = firstMatch(
                pattern: #"AppleWebKit\\s*/\\s*([\\d.]+)"#,
                in: nativeUserAgent
              ) else {
            cachedWebKitVersion = fallbackWebKit
            return fallbackWebKit
        }

        cachedWebKitVersion = version
        return version
    }
''',
    '''    @MainActor
    static func webKitVersion() -> String {
        if let cachedWebKitVersion {
            return cachedWebKitVersion
        }

        // Monterey compatibility build deliberately avoids private WKWebView
        // KVC. Automatic desktop rendering still lets WebKit own its native UA;
        // this token is only a conservative compatibility value for explicit
        // Safari-like identities.
        cachedWebKitVersion = fallbackWebKit
        return fallbackWebKit
    }
''',
    'Monterey compatibility build deliberately avoids private WKWebView',
)

replace_once(
    source,
    "        configuration.preferences.isElementFullscreenEnabled = true\n",
    """        if #available(macOS 12.3, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }
""",
    "if #available(macOS 12.3, *) {\n            configuration.preferences.isElementFullscreenEnabled = true",
)

# WKWebpagePreferences.preferredContentMode is an iOS content-mode API in
# WebKit's public header, and FloatTabs' macOS rendering architecture does not
# need it: Website Mode is already implemented by FloatTabsWebView plus the
# AppKit logical viewport host. Older macOS WebKit can runtime-trap when this
# preference is touched even though a newer SDK can compile the call. That
# exactly matches the real-Monterey A/B: no saved profile -> no WKWebView -> app
# stays alive; saved active profile -> makeWebView() -> SIGILL/132. Remove the
# preference mutation from the Monterey-prepared source entirely.
replace_once(
    source,
    '''        configuration.defaultWebpagePreferences.preferredContentMode =
            rendering.effectiveWebsiteMode == .desktop ? .desktop : .mobile
''',
    '''        // Monterey compatibility: do not touch preferredContentMode.
        // FloatTabs owns macOS Website Mode through its AppKit/WebView host.
''',
    'Monterey compatibility: do not touch preferredContentMode',
)

prepared_source = source.read_text()
if 'value(forKey: "userAgent")' in prepared_source:
    raise SystemExit("error: Monterey source still contains private WKWebView userAgent KVC")
if 'defaultWebpagePreferences.preferredContentMode' in prepared_source:
    raise SystemExit("error: Monterey source still mutates WKWebpagePreferences.preferredContentMode")

# Both macOS layout hosts carry the same fallback read. FloatTabsWebView itself
# always owns Website Mode; a non-FloatTabs fallback is conservatively desktop,
# matching Safari/WebKit's native Mac behavior without touching the iOS-oriented
# content-mode preference.
container = ROOT / "FloatTabs/Web/WebViewContainer.swift"
container_old = '''        let mode = (webView as? FloatTabsWebView)?.websiteMode
            ?? (webView.configuration.defaultWebpagePreferences.preferredContentMode == .mobile
                ? .mobile
                : .desktop)
'''
container_new = '''        let mode = (webView as? FloatTabsWebView)?.websiteMode ?? .desktop
        // Monterey compatibility: macOS fallback stays desktop without reading
        // WKWebpagePreferences.preferredContentMode.
'''
container_marker = 'Monterey compatibility: macOS fallback stays desktop without reading'
container_text = container.read_text()
if container_marker not in container_text:
    count = container_text.count(container_old)
    if count != 2:
        raise SystemExit(
            f"error: expected exactly 2 Monterey preferredContentMode fallbacks in {container}, found {count}"
        )
    container.write_text(container_text.replace(container_old, container_new))
prepared_container = container.read_text()
if 'defaultWebpagePreferences.preferredContentMode' in prepared_container:
    raise SystemExit("error: Monterey container still references WKWebpagePreferences.preferredContentMode")

tests = ROOT / "FloatTabsTests/WebViewFactoryTests.swift"
replace_once(
    tests,
    "        XCTAssertTrue(webView.configuration.preferences.isElementFullscreenEnabled)\n",
    """        if #available(macOS 12.3, *) {
            XCTAssertTrue(webView.configuration.preferences.isElementFullscreenEnabled)
        }
""",
    "if #available(macOS 12.3, *) {\n            XCTAssertTrue(webView.configuration.preferences.isElementFullscreenEnabled",
)
replace_once(
    tests,
    "        configuration.preferences.isElementFullscreenEnabled = true\n",
    """        if #available(macOS 12.3, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }
""",
    "if #available(macOS 12.3, *) {\n            configuration.preferences.isElementFullscreenEnabled = true",
)
replace_once(
    tests,
    "        XCTAssertEqual(webView.configuration.defaultWebpagePreferences.preferredContentMode, .mobile)\n",
    "        // Monterey: Website Mode is verified through UA/viewport behavior, not preferredContentMode.\n",
    "Monterey: Website Mode is verified through UA/viewport behavior, not preferredContentMode",
)

prepared_tests = tests.read_text()
if 'defaultWebpagePreferences.preferredContentMode' in prepared_tests:
    raise SystemExit("error: Monterey tests still reference WKWebpagePreferences.preferredContentMode")

print("Applied Monterey WebKit runtime and availability guards to app and tests.")
