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
            // macOS runner. Element fullscreen is disabled for the Monterey
            // compatibility package below, so there is no state to infer here.
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

# The compatibility source preparation initially guards this API at macOS 12.3.
# Do not leave element fullscreen enabled on Monterey while FloatTabs' fullscreen
# ownership observation is intentionally disabled. Keep the normal feature on
# macOS 13+ only.
old_fullscreen_enable = '''        if #available(macOS 12.3, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }
'''
new_fullscreen_enable = '''        if #available(macOS 13.0, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }
'''
if old_fullscreen_enable in web_text:
    web_text = web_text.replace(old_fullscreen_enable, new_fullscreen_enable, 1)
elif new_fullscreen_enable not in web_text:
    raise SystemExit("error: expected Monterey element-fullscreen guard not found")
web_factory.write_text(web_text)

prepared_fullscreen = fullscreen.read_text()
if '''        } else {
            startLegacyFullscreenPolling(of: webView)
        }
''' in prepared_fullscreen:
    raise SystemExit("error: Monterey runtime still starts legacy fullscreen polling")

prepared_web = web_factory.read_text()
if '''if #available(macOS 12.3, *) {
            configuration.preferences.isElementFullscreenEnabled = true''' in prepared_web:
    raise SystemExit("error: element fullscreen is still enabled on macOS 12")
if '''if #available(macOS 13.0, *) {
            configuration.preferences.isElementFullscreenEnabled = true''' not in prepared_web:
    raise SystemExit("error: macOS 13+ element-fullscreen behavior was not preserved")

print("Applied Monterey runtime safe mode: fullscreen disabled on macOS 12.")
