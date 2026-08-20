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
replace_once(
    source,
    "        configuration.preferences.isElementFullscreenEnabled = true\n",
    """        if #available(macOS 12.3, *) {
            configuration.preferences.isElementFullscreenEnabled = true
        }
""",
    "if #available(macOS 12.3, *) {\n            configuration.preferences.isElementFullscreenEnabled = true",
)

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

print("Applied Monterey WebKit preference availability guards to app and tests.")
