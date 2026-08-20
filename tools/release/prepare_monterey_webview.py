#!/usr/bin/env python3
"""Stage 2: Monterey WebKit runtime and availability guards (app + tests).

Removes the private `userAgent` KVC probe, availability-guards
`isElementFullscreenEnabled`, and strips the `preferredContentMode` mutation
from the Monterey-prepared source. All anchors validate exactly one match.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from monterey_transform_lib import (
    read_source,
    replace_exact_once,
    replace_once_regex,
    replace_span_once,
    require_absent,
    require_present,
    write_source,
)

ROOT = Path(__file__).resolve().parents[2]

source = ROOT / "FloatTabs/Web/WebViewFactory.swift"
text = read_source(source)

# Monterey runtime hardening: WKWebView's private KVC `userAgent` key is not a
# public API contract. A missing KVC key throws an Objective-C exception rather
# than a Swift error, which can terminate the process the first time a Web App
# creates a WKWebView and then repeat on every launch once that profile is saved.
# The Monterey package therefore uses the existing conservative WebKit UA token
# fallback instead of probing the private key. The standard macOS 13+ package is
# untouched by this compatibility preparation.
text = replace_span_once(
    text,
    r"^    @MainActor\n    static func webKitVersion\(\) -> String \{",
    r"^    static func chromeVersion\(\) -> String \{",
    """    @MainActor
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

""",
    label="WebViewFactory.webKitVersion KVC probe removal",
)

text = replace_once_regex(
    text,
    r"^        configuration\.preferences\.isElementFullscreenEnabled = true$",
    """        if #available(macOS 12.3, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }
""",
    label="WebViewFactory element-fullscreen availability guard",
)

# WKWebpagePreferences.preferredContentMode is an iOS content-mode API in
# WebKit's public header, and FloatTabs' macOS rendering architecture does not
# need it: Website Mode is already implemented by FloatTabsWebView plus the
# AppKit logical viewport host. Older macOS WebKit can runtime-trap when this
# preference is touched even though a newer SDK can compile the call. That
# exactly matches the real-Monterey A/B: no saved profile -> no WKWebView -> app
# stays alive; saved active profile -> makeWebView() -> SIGILL/132. Remove the
# preference mutation from the Monterey-prepared source entirely.
text = replace_once_regex(
    text,
    r"        configuration\.defaultWebpagePreferences\.preferredContentMode =\s*"
    r"            rendering\.effectiveWebsiteMode == \.desktop \? \.desktop : \.mobile",
    """        // Monterey compatibility: do not touch preferredContentMode.
        // FloatTabs owns macOS Website Mode through its AppKit/WebView host.""",
    label="WebViewFactory preferredContentMode removal",
)
write_source(source, text)

prepared_source = read_source(source)
require_absent(
    prepared_source,
    'value(forKey: "userAgent")',
    label="Monterey WebViewFactory private KVC",
)
require_absent(
    prepared_source,
    "defaultWebpagePreferences.preferredContentMode",
    label="Monterey WebViewFactory preferredContentMode",
)

# Both macOS layout hosts carry the same fallback read. FloatTabsWebView itself
# always owns Website Mode; a non-FloatTabs fallback is conservatively desktop,
# matching Safari/WebKit's native Mac behavior without touching the iOS-oriented
# content-mode preference.
container = ROOT / "FloatTabs/Web/WebViewContainer.swift"
container_old = """        let mode = (webView as? FloatTabsWebView)?.websiteMode
            ?? (webView.configuration.defaultWebpagePreferences.preferredContentMode == .mobile
                ? .mobile
                : .desktop)
"""
container_new = """        let mode = (webView as? FloatTabsWebView)?.websiteMode ?? .desktop
        // Monterey compatibility: macOS fallback stays desktop without reading
        // WKWebpagePreferences.preferredContentMode.
"""
text = read_source(container)
text = replace_exact_once(
    text,
    container_old,
    container_new,
    expected=2,
    label="WebViewContainer preferredContentMode fallbacks",
)
write_source(container, text)
require_absent(
    read_source(container),
    "defaultWebpagePreferences.preferredContentMode",
    label="Monterey WebViewContainer preferredContentMode",
)

tests = ROOT / "FloatTabsTests/WebViewFactoryTests.swift"
text = read_source(tests)
text = replace_once_regex(
    text,
    r"^        XCTAssertTrue\(webView\.configuration\.preferences\.isElementFullscreenEnabled\)$",
    """        if #available(macOS 12.3, *) {
            XCTAssertTrue(webView.configuration.preferences.isElementFullscreenEnabled)
        }""",
    label="WebViewFactoryTests stage-zero fullscreen assertion guard",
)
text = replace_once_regex(
    text,
    r"^        configuration\.preferences\.isElementFullscreenEnabled = true$",
    """        if #available(macOS 12.3, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }""",
    label="WebViewFactoryTests policy-webview fullscreen guard",
)
text = replace_once_regex(
    text,
    r"^        XCTAssertEqual\(webView\.configuration\.defaultWebpagePreferences\.preferredContentMode, \.mobile\)$",
    "        // Monterey: Website Mode is verified through UA/viewport behavior, not preferredContentMode.",
    label="WebViewFactoryTests preferredContentMode assertion",
)
write_source(tests, text)
require_absent(
    read_source(tests),
    "XCTAssertEqual(webView.configuration.defaultWebpagePreferences.preferredContentMode",
    label="Monterey WebViewFactoryTests preferredContentMode assertion",
)

print("Applied Monterey WebKit runtime and availability guards to app and tests.")
