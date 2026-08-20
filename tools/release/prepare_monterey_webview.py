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

prepared_source = source.read_text()
if 'value(forKey: "userAgent")' in prepared_source:
    raise SystemExit("error: Monterey source still contains private WKWebView userAgent KVC")

tests = ROOT / "FloatTabsTests/WebViewFactoryTests.swift"
replace_once(
    tests,
    "        XCTAssertTrue(webView.configuration.preferences.isElementFullscreenEnabled)\n",
    """        if #available(macOS 12.3, *) {
            XCTAssertTrue(webView.configuration.preferences.isElementFullscreenEnabled)
        }
""",
    "if #available(macOS 12.3, *) {\n            XCTAssertTrue(webView.configuration.preferences.isElementFullscreenEnabled)",
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

print("Applied Monterey WebKit runtime and availability guards to app and tests.")
