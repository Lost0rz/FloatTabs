#!/usr/bin/env python3
"""Stage 8: Candidate H Monterey authentication A/B diagnostics.

After Candidate G has restored native popup context, this stage intentionally
changes exactly one variable per diagnostic package:
- safari-identity: apply the repository's existing macOS Safari UA generator to
  the primary WebView and the native temporary popup child.
- delegate-off: retain MontereyNavigationObserver for ownership but leave the
  primary WebView's navigationDelegate nil.

An unset mode is a strict no-op so the Candidate G baseline remains buildable.
"""

import os
import re
from pathlib import Path

from monterey_transform_lib import (
    read_source,
    replace_exact_once,
    replace_once_regex,
    require_absent,
    require_present,
    span_of,
    write_source,
)

ROOT = Path(__file__).resolve().parents[2]
MODE = os.environ.get("FLOATTABS_MONTEREY_H_MODE", "").strip().lower()
ALLOWED_MODES = {"", "safari-identity", "delegate-off"}

if MODE not in ALLOWED_MODES:
    raise SystemExit(
        "error: FLOATTABS_MONTEREY_H_MODE must be one of: "
        "safari-identity, delegate-off, or unset"
    )


def add_h1_identity() -> None:
    pool_path = ROOT / "FloatTabs/Web/WebViewPool.swift"
    text = read_source(pool_path)
    declaration = """@MainActor
enum MontereySafariIdentityDiagnostic {
    // Candidate H1 deliberately reuses the repository's existing macOS Safari
    // identity generator; no Chrome, iPhone, or custom identity is selectable.
    static let userAgent = UserAgentProvider.userAgent(
        for: .macosSafari,
        websiteMode: .desktop
    )
}

"""
    text = replace_once_regex(
        text,
        r"^enum SiteCompatibilityPolicy",
        declaration + "enum SiteCompatibilityPolicy",
        label="Candidate H1 Safari identity diagnostic declaration",
    )
    text = replace_exact_once(
        text,
        "        let webView = WebViewFactory.makeWebView(renderingProfile: runtimeRendering)\n"
        "        NSLog(\"[FloatTabs Monterey] createWebView factory ready slot=%@\", profile.id.uuidString)\n",
        "        let webView = WebViewFactory.makeWebView(renderingProfile: runtimeRendering)\n"
        "        webView.customUserAgent = MontereySafariIdentityDiagnostic.userAgent\n"
        "        NSLog(\"[FloatTabs Monterey] createWebView factory ready slot=%@\", profile.id.uuidString)\n",
        label="Candidate H1 primary Safari UA assignment",
    )
    write_source(pool_path, text)

    popup_path = ROOT / "FloatTabs/Web/PopupCoordinator.swift"
    text = read_source(popup_path)
    text = replace_exact_once(
        text,
        "        popupWebView.allowsBackForwardNavigationGestures = true\n",
        "        popupWebView.customUserAgent = MontereySafariIdentityDiagnostic.userAgent\n"
        "        popupWebView.allowsBackForwardNavigationGestures = true\n",
        label="Candidate H1 temporary popup Safari UA assignment",
    )
    write_source(popup_path, text)

    ui_path = ROOT / "FloatTabs/UI/WebAppEditorController.swift"
    text = read_source(ui_path)
    text = replace_exact_once(
        text,
        '    static let effectiveUserAgentPreview = "System WebKit · Monterey Compatibility"\n',
        '    static let effectiveUserAgentPreview = "System WebKit · Safari Identity Diagnostic"\n',
        label="Candidate H1 honest Safari diagnostic preview",
    )
    write_source(ui_path, text)


def add_h2_delegate_off() -> None:
    path = ROOT / "FloatTabs/Web/SlotNavigationObserver.swift"
    text = read_source(path)
    text = replace_exact_once(
        text,
        "        // Candidate F deliberately registers only this lifecycle delegate.\n"
        "        webView.navigationDelegate = self\n",
        "        // Candidate H2 delegate-off diagnostic: retain the observer for\n"
        "        // ownership and source compatibility, but do not register it.\n",
        label="Candidate H2 primary navigation delegate removal",
    )
    write_source(path, text)


def update_h1_primary_ua_expectations() -> None:
    """Make Candidate G's primary-WebView assertions match the H1 diagnostic."""
    expectations = {
        "FloatTabsTests/WebViewFactoryTests.swift": (
            "desktop",
            "mobile",
        ),
        "FloatTabsTests/WebViewPoolTests.swift": (
            "reused",
            "desktop",
            "mobile",
            "desktopAgain",
            "webView",
            "first",
            "second",
            "third",
            "initial",
        ),
    }
    for relative_path, variables in expectations.items():
        path = ROOT / relative_path
        text = read_source(path)
        for variable in variables:
            old = f'        XCTAssertTrue(({variable}.customUserAgent ?? "").isEmpty)\n'
            new = (
                f"        XCTAssertEqual({variable}.customUserAgent, "
                "MontereySafariIdentityDiagnostic.userAgent)\n"
            )
            occurrences = text.count(old)
            if occurrences == 0:
                raise SystemExit(
                    f"error: Candidate H1 {variable} primary UA expectation: "
                    "anchor not found"
                )
            text = text.replace(old, new)
        write_source(path, text)


def add_generated_tests() -> None:
    path = ROOT / "FloatTabsTests/WebViewPoolTests.swift"
    text = read_source(path)

    if MODE == "safari-identity":
        primary_test = """    func testCandidateH1SafariIdentityCoversPrimaryWebView() {
        let pool = makePool()
        let primary = pool.webView(for: makeProfile(name: "H1"))

        XCTAssertTrue(primary.navigationDelegate is MontereyNavigationObserver)
        XCTAssertTrue(primary.uiDelegate is PopupCoordinator)
        XCTAssertEqual(
            primary.customUserAgent,
            MontereySafariIdentityDiagnostic.userAgent
        )
        XCTAssertTrue(primary.customUserAgent?.contains("Macintosh") == true)
        XCTAssertTrue(primary.customUserAgent?.contains("Version/") == true)
        XCTAssertFalse(primary.customUserAgent?.contains("Chrome") == true)
        NSLog(
            "[FloatTabs Monterey H1] Safari diagnostic UA=%@",
            MontereySafariIdentityDiagnostic.userAgent
        )
    }

"""
        text = replace_once_regex(
            text,
            r"^    func testPooledWebViewsUsePersistentWebsiteDataStore\(\) \{",
            primary_test + "    func testPooledWebViewsUsePersistentWebsiteDataStore() {",
            label="Candidate H1 primary identity test",
        )
        text = replace_exact_once(
            text,
            "        XCTAssertTrue(popup.configuration.processPool === configuration.processPool)\n"
            "        XCTAssertFalse(popup is FloatTabsWebView)\n",
            "        XCTAssertTrue(popup.configuration.processPool === configuration.processPool)\n"
            "        XCTAssertEqual(\n"
            "            popup.customUserAgent,\n"
            "            MontereySafariIdentityDiagnostic.userAgent\n"
            "        )\n"
            "        XCTAssertFalse(popup is FloatTabsWebView)\n",
            label="Candidate H1 temporary identity test",
        )
    elif MODE == "delegate-off":
        primary_test = """    func testCandidateH2DelegateOffPrimaryContract() {
        let pool = makePool()
        let primary = pool.webView(for: makeProfile(name: "H2"))

        XCTAssertNil(primary.navigationDelegate)
        XCTAssertTrue(primary.uiDelegate is PopupCoordinator)
        XCTAssertTrue((primary.customUserAgent ?? "").isEmpty)
    }

"""
        text = replace_once_regex(
            text,
            r"^    func testPooledWebViewsUsePersistentWebsiteDataStore\(\) \{",
            primary_test + "    func testPooledWebViewsUsePersistentWebsiteDataStore() {",
            label="Candidate H2 primary delegate test",
        )
        text = replace_exact_once(
            text,
            "        XCTAssertTrue(webView.navigationDelegate is MontereyNavigationObserver)\n",
            "        XCTAssertNil(webView.navigationDelegate)\n",
            label="Candidate H2 existing primary delegate expectation",
        )
        text = replace_exact_once(
            text,
            "        XCTAssertTrue(popup.configuration.processPool === configuration.processPool)\n"
            "        XCTAssertFalse(popup is FloatTabsWebView)\n",
            "        XCTAssertTrue(popup.configuration.processPool === configuration.processPool)\n"
            '        XCTAssertTrue((popup.customUserAgent ?? "").isEmpty)\n'
            "        XCTAssertFalse(popup is FloatTabsWebView)\n",
            label="Candidate H2 temporary identity test",
        )
    else:
        raise SystemExit("error: Candidate H tests require an explicit diagnostic mode")

    write_source(path, text)
    if MODE == "safari-identity":
        update_h1_primary_ua_expectations()


def verify_common_contract() -> None:
    popup = read_source(ROOT / "FloatTabs/Web/PopupCoordinator.swift")
    pool = read_source(ROOT / "FloatTabs/Web/WebViewPool.swift")
    tests = read_source(ROOT / "FloatTabsTests/WebViewPoolTests.swift")

    require_present(
        popup,
        "let popupWebView = WKWebView(\n            frame: .zero,\n            configuration: configuration\n        )",
        label="Candidate H callback-provided popup construction",
    )
    require_present(
        popup,
        "popupWebView.uiDelegate = self",
        label="Candidate H popup UI delegate",
    )
    require_absent(
        popup,
        "popupWebView.navigationDelegate =",
        label="Candidate H popup navigation delegate assignment",
    )
    require_absent(
        popup,
        "WKNavigationDelegate",
        label="Candidate H PopupCoordinator navigation conformance",
    )
    require_absent(
        popup,
        "decidePolicyFor navigationAction",
        label="Candidate H PopupCoordinator navigation policy",
    )
    require_absent(
        popup,
        "decidePolicyFor navigationResponse",
        label="Candidate H PopupCoordinator response policy",
    )
    create_span = span_of(
        popup,
        r"^    func webView\(\n        _ webView: WKWebView,\n        createWebViewWith configuration",
        r"^    @discardableResult\n    func makeTemporaryPopupWebView",
        label="Candidate H popup callback span",
    )
    require_present(
        create_span,
        "return makeTemporaryPopupWebView",
        label="Candidate H popup callback return",
    )
    require_absent(
        create_span,
        ".load(",
        label="Candidate H popup callback manual load",
    )

    require_present(
        pool,
        "let observer = MontereyNavigationObserver(",
        label="Candidate H primary observer construction",
    )
    require_present(
        pool,
        "webView.uiDelegate = popupCoordinator",
        label="Candidate H primary UI delegate",
    )
    require_absent(
        pool,
        "userContentController.add",
        label="Candidate H primary script-message injection",
    )

    for source_path in sorted((ROOT / "FloatTabs").rglob("*.swift")):
        source = source_path.read_text(encoding="utf-8")
        require_absent(
            source,
            "FloatTabsWebView(frame:",
            label=f"Candidate H FloatTabsWebView construction in {source_path.name}",
        )
        require_absent(
            source,
            "preferredContentMode =",
            label=f"Candidate H preferredContentMode mutation in {source_path.name}",
        )
        require_absent(
            source,
            "applicationNameForUserAgent =",
            label=f"Candidate H applicationNameForUserAgent mutation in {source_path.name}",
        )
        require_absent(
            source,
            "webView.pageZoom =",
            label=f"Candidate H pageZoom mutation in {source_path.name}",
        )


def verify_h1_contract() -> None:
    popup = read_source(ROOT / "FloatTabs/Web/PopupCoordinator.swift")
    pool = read_source(ROOT / "FloatTabs/Web/WebViewPool.swift")
    observer = read_source(ROOT / "FloatTabs/Web/SlotNavigationObserver.swift")
    ui = read_source(ROOT / "FloatTabs/UI/WebAppEditorController.swift")
    tests = read_source(ROOT / "FloatTabsTests/WebViewPoolTests.swift")

    require_present(
        pool,
        "static let userAgent = UserAgentProvider.userAgent(\n"
        "        for: .macosSafari,\n"
        "        websiteMode: .desktop\n"
        "    )",
        label="Candidate H1 existing Safari UA source",
    )
    require_present(
        pool,
        "webView.customUserAgent = MontereySafariIdentityDiagnostic.userAgent",
        label="Candidate H1 primary custom UA assignment",
    )
    require_present(
        popup,
        "popupWebView.customUserAgent = MontereySafariIdentityDiagnostic.userAgent",
        label="Candidate H1 popup custom UA assignment",
    )
    if pool.count("webView.customUserAgent =") != 1:
        raise SystemExit(
            "error: Candidate H1 primary custom UA assignment count is not exactly 1"
        )
    require_absent(
        popup,
        "floatingWebView.customUserAgent =",
        label="Candidate H1 explicit floating UA copy",
    )
    require_present(
        observer,
        "webView.navigationDelegate = self",
        label="Candidate H1 primary observer registration",
    )
    require_present(
        ui,
        "System WebKit · Safari Identity Diagnostic",
        label="Candidate H1 UI diagnostic label",
    )
    for marker in [
        "testCandidateH1SafariIdentityCoversPrimaryWebView",
        "MontereySafariIdentityDiagnostic.userAgent",
        "XCTAssertNil(popup.navigationDelegate)",
    ]:
        require_present(tests, marker, label=f"Candidate H1 generated test marker: {marker}")

    # The only active WebKit UA assignments added by H1 are the primary and
    # callback-created temporary popup. Profile metadata assignments are not
    # WebView runtime mutations.
    active_assignments = []
    for source_path in sorted((ROOT / "FloatTabs").rglob("*.swift")):
        source = source_path.read_text(encoding="utf-8")
        for line in source.splitlines():
            if re.search(r"\b(?:webView|popupWebView|floatingWebView)\.customUserAgent\s*=", line):
                active_assignments.append((source_path.name, line.strip()))
    expected = [
        ("PopupCoordinator.swift", "popupWebView.customUserAgent = MontereySafariIdentityDiagnostic.userAgent"),
        ("WebViewPool.swift", "webView.customUserAgent = MontereySafariIdentityDiagnostic.userAgent"),
    ]
    if sorted(active_assignments) != sorted(expected):
        raise SystemExit(
            "error: Candidate H1 active custom UA assignment set differs: "
            f"{active_assignments!r}"
        )


def verify_h2_contract() -> None:
    popup = read_source(ROOT / "FloatTabs/Web/PopupCoordinator.swift")
    pool = read_source(ROOT / "FloatTabs/Web/WebViewPool.swift")
    observer = read_source(ROOT / "FloatTabs/Web/SlotNavigationObserver.swift")
    ui = read_source(ROOT / "FloatTabs/UI/WebAppEditorController.swift")
    tests = read_source(ROOT / "FloatTabsTests/WebViewPoolTests.swift")

    require_absent(
        observer,
        "webView.navigationDelegate = self",
        label="Candidate H2 primary navigation delegate registration",
    )
    require_absent(
        pool,
        "MontereySafariIdentityDiagnostic",
        label="Candidate H2 Safari diagnostic identity leaked into pool",
    )
    require_absent(
        popup,
        "MontereySafariIdentityDiagnostic",
        label="Candidate H2 Safari diagnostic identity leaked into popup",
    )
    require_absent(
        pool,
        "webView.customUserAgent =",
        label="Candidate H2 primary custom UA assignment",
    )
    require_absent(
        popup,
        "popupWebView.customUserAgent =",
        label="Candidate H2 popup custom UA assignment",
    )
    require_present(
        ui,
        "System WebKit · Monterey Compatibility",
        label="Candidate H2 Candidate G UI identity label",
    )
    require_present(
        tests,
        "testCandidateH2DelegateOffPrimaryContract",
        label="Candidate H2 generated primary test",
    )
    require_present(
        tests,
        "XCTAssertNil(primary.navigationDelegate)",
        label="Candidate H2 generated delegate assertion",
    )


def main() -> None:
    if not MODE:
        print("Candidate H mode unset: preserving Candidate G behavior.")
        return

    if MODE == "safari-identity":
        add_h1_identity()
    else:
        add_h2_delegate_off()

    add_generated_tests()
    verify_common_contract()
    if MODE == "safari-identity":
        verify_h1_contract()
    else:
        verify_h2_contract()
    print(f"Applied Candidate H diagnostic mode: {MODE}")


if __name__ == "__main__":
    main()
