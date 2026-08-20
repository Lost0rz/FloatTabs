#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parents[2] / "FloatTabs/Web/WebViewFactory.swift"
text = path.read_text()
old = "        configuration.preferences.isElementFullscreenEnabled = true\n"
new = """        if #available(macOS 12.3, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }
"""
marker = "if #available(macOS 12.3, *) {\n            configuration.preferences.isElementFullscreenEnabled = true"

if marker not in text:
    if old not in text:
        raise SystemExit(f"error: expected Monterey WebKit patch context not found in {path}")
    path.write_text(text.replace(old, new, 1))

print("Applied Monterey WebKit preference availability guard.")
