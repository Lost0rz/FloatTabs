#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

fullscreen = ROOT / "FloatTabs/Panel/FullscreenSourceHost.swift"
text = fullscreen.read_text()
old = '''        if #available(macOS 13.0, *) {
            observeModernFullscreenState(of: webView)
        } else {
            startLegacyFullscreenPolling(of: webView)
        }
'''
new = '''        if #available(macOS 13.0, *) {
            observeModernFullscreenState(of: webView)
        } else {
            // Monterey runtime safe mode: do not start the compatibility polling
            // loop during ordinary WebView creation. The polling implementation
            // is compile-valid but cannot be runtime-validated on GitHub's newer
            // macOS runner, and it is entered immediately while restoring a saved
            // active Profile. Keep the observed WebView reference so ordinary
            // source hosting still works; element-fullscreen observation is
            // temporarily disabled on macOS 12 until real-Monterey validation.
            legacyFullscreenPollGeneration &+= 1
        }
'''
marker = "Monterey runtime safe mode: do not start the compatibility polling"
if marker not in text:
    if old not in text:
        raise SystemExit(f"error: expected Monterey fullscreen safe-mode context not found in {fullscreen}")
    fullscreen.write_text(text.replace(old, new, 1))

web_factory = ROOT / "FloatTabs/Web/WebViewFactory.swift"
web_text = web_factory.read_text()
if 'value(forKey: "userAgent")' in web_text:
    raise SystemExit("error: private WKWebView userAgent KVC survived Monterey preparation")

print("Applied Monterey runtime safe mode: legacy fullscreen polling disabled.")
