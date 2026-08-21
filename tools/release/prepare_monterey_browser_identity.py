#!/usr/bin/env python3
"""Stage 9: Monterey public Safari-compatible browser identity.

This final compatibility transform restores only the public WebKit
applicationNameForUserAgent seam. It leaves the resident WKWebView, Website
Mode/AppKit geometry, Candidate G popup callback path, and MC-B1 storage
isolation intact.
"""

import re
from pathlib import Path

from monterey_transform_lib import (
    read_source,
    replace_exact_once,
    replace_once_regex,
    replace_span_once,
    require_absent,
    require_present,
    span_of,
    write_source,
)

ROOT = Path(__file__).resolve().parents[2]


SAFARI_IDENTITY_DECLARATION = r'''enum MontereySafariIdentity {
    static let safariBundlePaths = [
        URL(fileURLWithPath: "/Applications/Safari.app", isDirectory: true),
        URL(fileURLWithPath: "/System/Applications/Safari.app", isDirectory: true),
    ]

    // Public compatibility token; never obtained through a hidden WKWebView or KVC.
    static let webKitProductVersion = "605.1.15"

    static var installedSafariVersion: String? {
        installedSafariVersion(fileManager: .default, paths: safariBundlePaths)
    }

    static var applicationName: String? {
        applicationName(fileManager: .default, paths: safariBundlePaths)
    }

    static func installedSafariVersion(
        fileManager: FileManager,
        paths: [URL]
    ) -> String? {
        for bundleURL in paths {
            guard let rawVersion = rawSafariVersion(
                at: bundleURL,
                fileManager: fileManager
            ),
            let normalized = normalizedSafariVersion(rawVersion) else {
                continue
            }
            return normalized
        }
        return nil
    }

    static func applicationName(
        fileManager: FileManager,
        paths: [URL]
    ) -> String? {
        applicationName(
            forSafariVersion: installedSafariVersion(
                fileManager: fileManager,
                paths: paths
            )
        )
    }

    static func applicationName(forSafariVersion version: String?) -> String? {
        guard let version,
              let normalized = normalizedSafariVersion(version) else {
            return nil
        }
        return "Version/\(normalized) Safari/\(webKitProductVersion)"
    }

    static func normalizedSafariVersion(_ version: String) -> String? {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2,
              components.allSatisfy({ component in
                  !component.isEmpty && component.allSatisfy(\.isNumber)
              }),
              let major = Int(components[0]),
              let minor = Int(components[1]) else {
            return nil
        }
        return "\(major).\(minor)"
    }

    private static func rawSafariVersion(
        at bundleURL: URL,
        fileManager: FileManager
    ) -> String? {
        let infoURL = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist", isDirectory: false)
        guard fileManager.fileExists(atPath: infoURL.path),
              let data = try? Data(contentsOf: infoURL),
              let object = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ),
              let dictionary = object as? [String: Any],
              let version = dictionary["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return version
    }
}

'''


def patch_browser_version_resolver() -> None:
    path = ROOT / "FloatTabs/Web/WebViewFactory.swift"
    text = read_source(path)
    text = replace_once_regex(
        text,
        r"^struct BrowserVersionCatalog",
        SAFARI_IDENTITY_DECLARATION + "struct BrowserVersionCatalog",
        label="MC-B2 safe Safari identity resolver declaration",
    )

    safe_resolver = r'''enum BrowserVersionResolver {
    private static let fallbackChrome = "150.0.0.0"
    private static let fallbackEdge = "150.0.0.0"

    static func safariVersion() -> String {
        MontereySafariIdentity.installedSafariVersion ?? ""
    }

    static func webKitVersion() -> String {
        MontereySafariIdentity.webKitProductVersion
    }

    static func chromeVersion() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "/Applications/Google Chrome.app",
            "\(home)/Applications/Google Chrome.app",
        ]
        return normalizedChromiumVersion(applicationVersion(paths: paths) ?? fallbackChrome)
    }

    static func edgeVersion() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "/Applications/Microsoft Edge.app",
            "\(home)/Applications/Microsoft Edge.app",
        ]
        return normalizedChromiumVersion(applicationVersion(paths: paths) ?? fallbackEdge)
    }

    static func normalizedSafariVersion(_ version: String) -> String {
        MontereySafariIdentity.normalizedSafariVersion(version) ?? ""
    }

    static func normalizedChromiumVersion(_ version: String) -> String {
        var numeric = version.split(separator: ".").compactMap { Int($0) }
        guard !numeric.isEmpty else { return fallbackChrome }
        while numeric.count < 4 { numeric.append(0) }
        return numeric.prefix(4).map(String.init).joined(separator: ".")
    }

    private static func applicationVersion(paths: [String]) -> String? {
        for path in paths {
            guard let bundle = Bundle(path: path),
                  let value = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
    }
}

'''
    text = replace_span_once(
        text,
        r"^enum BrowserVersionResolver \{",
        r"^/// Generates the HTTP/JavaScript browser identity",
        safe_resolver,
        label="MC-B2 private Safari/KVC resolver removal",
    )
    write_source(path, text)


def patch_primary_webview() -> None:
    path = ROOT / "FloatTabs/Web/WebViewFactory.swift"
    text = read_source(path)
    old = """        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
"""
    new = """        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        if let applicationName = MontereySafariIdentity.applicationName {
            configuration.applicationNameForUserAgent = applicationName
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
"""
    text = replace_exact_once(
        text,
        old,
        new,
        label="MC-B2 primary public applicationNameForUserAgent assignment",
    )
    write_source(path, text)


def patch_disabled_runtime_surface() -> None:
    factory_path = ROOT / "FloatTabs/Web/WebViewFactory.swift"
    text = read_source(factory_path)
    old_zoom_body = """    private func refreshWebsiteLayoutScale() {
        websiteLayoutScale = 1
        if abs(pageZoom - userPageZoom) > 0.0001 {
            pageZoom = userPageZoom
        }
    }
"""
    new_zoom_body = """    private func refreshWebsiteLayoutScale() {
        // Monterey Compatibility Edition keeps stock WebKit zoom neutral.
        websiteLayoutScale = 1
    }
"""
    text = replace_exact_once(
        text,
        old_zoom_body,
        new_zoom_body,
        label="MC-B2 disable FloatTabsWebView pageZoom mutation",
    )
    write_source(factory_path, text)

    observer_path = ROOT / "FloatTabs/Web/SlotNavigationObserver.swift"
    text = read_source(observer_path)
    text = text.replace(
        "/// not mutate WKWebpagePreferences.preferredContentMode here: WebKit exposes that\n"
        "/// desktop-class browsing API for iOS, not as the macOS layout mechanism.\n",
        "/// not mutate WebKit's content-mode preference here; AppKit owns the macOS\n"
        "/// Website Mode layout mechanism.\n",
    )
    write_source(observer_path, text)


def patch_site_policy_and_ui() -> None:
    pool_path = ROOT / "FloatTabs/Web/WebViewPool.swift"
    text = read_source(pool_path)
    text = replace_span_once(
        text,
        r"^enum SiteCompatibilityPolicy \{",
        r"^enum WebContentRecoveryDisposition",
        """enum SiteCompatibilityPolicy {
    static func runtimeRendering(
        for renderingProfile: WebRenderingProfile,
        navigationURL: URL
    ) -> WebRenderingProfile {
        // MC-B2 has no hostname-specific rendering or identity behavior.
        _ = navigationURL
        return renderingProfile.normalized()
    }
}

""",
        label="MC-B2 generic rendering policy without hostname exceptions",
    )
    text = text.replace(
        "            // Reapply the effective runtime profile, not the persisted base profile.\n"
        "            // Narrow compatibility overrides such as ChatGPT Automatic+Mobile must\n"
        "            // remain stable when a warm WKWebView is detached and later reused.\n",
        "            // Reapply compatibility rendering metadata while retaining the resident\n"
        "            // WKWebView. Browser identity is fixed at construction time.\n",
    )
    write_source(pool_path, text)

    ui_path = ROOT / "FloatTabs/UI/WebAppEditorController.swift"
    text = read_source(ui_path)
    text = replace_exact_once(
        text,
        'static let effectiveUserAgentPreview = "System WebKit · Monterey Compatibility"',
        'static let effectiveUserAgentPreview = "System WebKit · Installed Safari Identity"',
        label="MC-B2 honest browser identity UI text",
    )
    write_source(ui_path, text)


def patch_generated_tests() -> None:
    factory_path = ROOT / "FloatTabsTests/WebViewFactoryTests.swift"
    text = read_source(factory_path)
    text = replace_exact_once(
        text,
        'safari: "26.6",',
        'safari: "17.6",',
        label="MC-B2 test catalog Safari version",
    )
    text = text.replace(
        'XCTAssertTrue((webView.configuration.applicationNameForUserAgent ?? "").isEmpty)',
        "XCTAssertEqual(webView.configuration.applicationNameForUserAgent, MontereySafariIdentity.applicationName)",
    )
    text = text.replace(
        "        // Monterey Compatibility Edition: the stock WKWebView keeps WebKit's\n"
        "        // native UA; no application-name suffix is applied at construction.\n",
        "        // MC-B2 uses WebKit's native UA base plus the public application-name\n"
        "        // suffix resolved from installed Safari metadata.\n",
    )
    text = text.replace(
        'XCTAssertEqual(BrowserVersionResolver.normalizedSafariVersion("26.6.1"), "26.6")',
        'XCTAssertEqual(MontereySafariIdentity.normalizedSafariVersion("17.6.1"), "17.6")',
    )
    text = text.replace(
        'XCTAssertTrue(ua.contains("Version/26.6"))',
        'XCTAssertTrue(ua.contains("Version/17.6"))',
    )
    text = text.replace(
        '"Version/26.6 Safari/619.3.7"',
        '"Version/17.6 Safari/619.3.7"',
    )
    text = text.replace('Version/26.6', 'Version/17.6')

    identity_tests = r'''    func testMontereySafariMetadataResolutionIsDeterministic() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsMCB2Safari-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let safariBundle = root.appendingPathComponent("Safari.app", isDirectory: true)
        let contents = safariBundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleShortVersionString": "17.6.1"],
            format: .xml,
            options: 0
        )
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))

        XCTAssertEqual(
            MontereySafariIdentity.installedSafariVersion(
                fileManager: .default,
                paths: [safariBundle]
            ),
            "17.6"
        )
        XCTAssertEqual(
            MontereySafariIdentity.applicationName(forSafariVersion: "17.6"),
            "Version/17.6 Safari/605.1.15"
        )
        XCTAssertEqual(
            MontereySafariIdentity.applicationName(forSafariVersion: "17.6.1"),
            "Version/17.6 Safari/605.1.15"
        )
        XCTAssertNil(
            MontereySafariIdentity.applicationName(forSafariVersion: "malformed")
        )
        XCTAssertNil(
            MontereySafariIdentity.installedSafariVersion(
                fileManager: .default,
                paths: [root.appendingPathComponent("Missing.app", isDirectory: true)]
            )
        )

        try Data("malformed".utf8).write(
            to: contents.appendingPathComponent("Info.plist")
        )
        XCTAssertNil(
            MontereySafariIdentity.installedSafariVersion(
                fileManager: .default,
                paths: [safariBundle]
            )
        )
        XCTAssertNil(MontereySafariIdentity.applicationName(forSafariVersion: nil))
    }

    func testMontereyPrimaryWebViewUsesPublicIdentityAndNoCustomUserAgent() {
        let webView = WebViewFactory.makeWebView()

        XCTAssertTrue(webView is WKWebView)
        XCTAssertFalse(webView is FloatTabsWebView)
        XCTAssertTrue(webView.configuration.websiteDataStore.isPersistent)
        XCTAssertEqual(
            webView.configuration.applicationNameForUserAgent,
            MontereySafariIdentity.applicationName
        )
        XCTAssertTrue(
            webView.customUserAgent == nil || webView.customUserAgent?.isEmpty == true
        )
    }

'''
    text = replace_once_regex(
        text,
        r"^final class WebViewFactoryTests: XCTestCase \{\n",
        "final class WebViewFactoryTests: XCTestCase {\n" + identity_tests,
        label="MC-B2 generated Safari identity tests",
    )
    write_source(factory_path, text)

    pool_path = ROOT / "FloatTabsTests/WebViewPoolTests.swift"
    text = read_source(pool_path)
    identity_matrix_tests = r'''    func testAutomaticIdentityIsHostnameIndependentAcrossRealHostFixtures() {
        let fixtures = [
            URL(string: "https://example.com/")!,
            URL(string: "https://chatgpt.com/")!,
            URL(string: "https://www.bilibili.com/")!,
        ]
        let rendering = WebRenderingProfile.canonicalDefault
        let pool = makePool()
        var webViews: [WKWebView] = []
        var runtimeProfiles: [WebRenderingProfile] = []

        for (index, fixture) in fixtures.enumerated() {
            var profile = makeProfile(
                name: "AutomaticFixture-\(index)",
                homeURL: fixture
            )
            profile.renderingProfile = rendering
            runtimeProfiles.append(
                SiteCompatibilityPolicy.runtimeRendering(
                    for: rendering,
                    navigationURL: fixture
                )
            )

            let first = pool.webView(for: profile)
            profile.currentURL = fixture.appendingPathComponent("follow-up")
            let second = pool.webView(for: profile)
            XCTAssertTrue(first === second)
            webViews.append(second)
        }

        XCTAssertEqual(
            runtimeProfiles,
            Array(repeating: rendering.normalized(), count: fixtures.count)
        )
        XCTAssertEqual(
            runtimeProfiles.map(\.browserIdentity),
            Array(repeating: .automatic, count: fixtures.count)
        )
        XCTAssertEqual(
            runtimeProfiles.map(\.websiteMode),
            Array(repeating: .desktop, count: fixtures.count)
        )
        XCTAssertEqual(
            webViews.map { $0.configuration.applicationNameForUserAgent },
            Array(
                repeating: MontereySafariIdentity.applicationName,
                count: fixtures.count
            )
        )
        XCTAssertTrue(
            webViews.allSatisfy {
                $0.customUserAgent == nil || $0.customUserAgent?.isEmpty == true
            }
        )
        XCTAssertTrue(webViews.allSatisfy { $0.configuration.websiteDataStore.isPersistent })
        XCTAssertEqual(pool.count, fixtures.count)
    }

'''
    text = replace_once_regex(
        text,
        r"^final class WebViewPoolTests: XCTestCase \{\n",
        "final class WebViewPoolTests: XCTestCase {\n" + identity_matrix_tests,
        label="MC-B2 real-host automatic identity matrix",
    )
    text = re.sub(
        r'XCTAssertTrue\(\((\w+)\.configuration\.applicationNameForUserAgent \?\? ""\)\.isEmpty\)',
        r"XCTAssertEqual(\1.configuration.applicationNameForUserAgent, MontereySafariIdentity.applicationName)",
        text,
    )
    text = re.sub(
        r'XCTAssertTrue\(\((\w+)\.customUserAgent \?\? ""\)\.isEmpty\)',
        r"XCTAssertTrue(\1.customUserAgent == nil || \1.customUserAgent?.isEmpty == true)",
        text,
    )
    text = re.sub(
        r"        XCTAssertEqual\(\n"
        r"            \w+\.configuration\.defaultWebpagePreferences\.preferredContentMode,\n"
        r"            \.recommended\n"
        r"        \)\n\n?",
        "",
        text,
    )
    text = re.sub(
        r"        XCTAssertEqual\(\w+\.configuration\.defaultWebpagePreferences\.preferredContentMode, \.recommended\)\n",
        "",
        text,
    )
    text = text.replace("        first.pageZoom = 1.35\n", "")
    text = text.replace("        initial.pageZoom = 1.35\n", "")
    text = text.replace("pageZoom, 1.35", "pageZoom, 1")
    text = text.replace(
        "        let configuration = WKWebViewConfiguration()\n"
        "        let popup = coordinator.makeTemporaryPopupWebView(\n",
        "        guard let configuration = source.configuration.copy() as? WKWebViewConfiguration else {\n"
        "            XCTFail(\"Unable to copy WKWebViewConfiguration\")\n"
        "            return\n"
        "        }\n"
        "        let popup = coordinator.makeTemporaryPopupWebView(\n",
    )
    text = text.replace(
        "        XCTAssertTrue(popup.configuration.processPool === configuration.processPool)\n",
        "        XCTAssertEqual(configuration.applicationNameForUserAgent, source.configuration.applicationNameForUserAgent)\n"
        "        XCTAssertTrue(popup.configuration.websiteDataStore === configuration.websiteDataStore)\n"
        "        XCTAssertTrue(popup.configuration.processPool === configuration.processPool)\n"
        "        XCTAssertEqual(popup.configuration.applicationNameForUserAgent, configuration.applicationNameForUserAgent)\n"
        "        XCTAssertEqual(popup.configuration.applicationNameForUserAgent, source.configuration.applicationNameForUserAgent)\n",
    )
    text = text.replace('        source.customUserAgent = "FloatTabs-Test-UA/1.0"\n', "")
    write_source(pool_path, text)


def verify_contract() -> None:
    build_script = read_source(ROOT / "tools/release/build_monterey_dmg.sh")
    web_factory = read_source(ROOT / "FloatTabs/Web/WebViewFactory.swift")
    popup = read_source(ROOT / "FloatTabs/Web/PopupCoordinator.swift")
    pool = read_source(ROOT / "FloatTabs/Web/WebViewPool.swift")
    observer = read_source(ROOT / "FloatTabs/Web/SlotNavigationObserver.swift")
    ui = read_source(ROOT / "FloatTabs/UI/WebAppEditorController.swift")
    factory_tests = read_source(ROOT / "FloatTabsTests/WebViewFactoryTests.swift")
    pool_tests = read_source(ROOT / "FloatTabsTests/WebViewPoolTests.swift")

    require_present(
        build_script,
        "python3 tools/release/prepare_monterey_edition_isolation.py\n"
        "python3 tools/release/prepare_monterey_browser_identity.py\n",
        label="MC-B2 transform ordering after MC-B1",
    )
    require_absent(
        build_script,
        "prepare_monterey_candidate_h.py",
        label="MC-B2 Candidate H transform exclusion",
    )
    require_present(
        web_factory,
        "configuration.websiteDataStore = .default()",
        label="MC-B2 persistent WebsiteDataStore",
    )
    require_present(
        web_factory,
        "if let applicationName = MontereySafariIdentity.applicationName",
        label="MC-B2 public Safari identity assignment",
    )
    require_present(
        web_factory,
        "configuration.applicationNameForUserAgent = applicationName",
        label="MC-B2 applicationNameForUserAgent assignment",
    )
    make_span = span_of(
        web_factory,
        r"^    static func makeWebView\(",
        r"^    static func makeStageZeroWebView\(",
        label="MC-B2 primary WebView construction span",
    )
    require_present(
        make_span,
        "WKWebView(frame: .zero, configuration: configuration)",
        label="MC-B2 stock primary WKWebView construction",
    )
    require_absent(
        make_span,
        "BrowserVersionCatalog.current",
        label="MC-B2 BrowserVersionCatalog construction coupling",
    )
    require_absent(
        make_span,
        "customUserAgent",
        label="MC-B2 primary customUserAgent mutation",
    )
    require_absent(
        web_factory,
        'value(forKey: "userAgent")',
        label="MC-B2 private userAgent KVC",
    )
    require_absent(
        web_factory,
        'private static let fallbackSafari = "26.0"',
        label="MC-B2 Safari 26 fallback",
    )
    require_absent(
        web_factory,
        'applicationNameForUserAgent = UserAgentProvider.safariApplicationName(',
        label="MC-B2 legacy application identity assignment",
    )
    require_absent(
        popup,
        "popupWebView.navigationDelegate =",
        label="MC-B2 popup navigation delegate mutation",
    )
    require_present(
        popup,
        "configuration: configuration\n        )",
        label="MC-B2 callback popup configuration preservation",
    )
    require_present(
        observer,
        "webView.navigationDelegate = self",
        label="MC-B2 primary MontereyNavigationObserver delegate",
    )
    require_present(
        ui,
        "System WebKit · Installed Safari Identity",
        label="MC-B2 honest identity UI wording",
    )
    for source, label in [
        (web_factory, "WebViewFactory production source"),
        (popup, "PopupCoordinator production source"),
        (pool, "WebViewPool production source"),
    ]:
        for forbidden in [
            "chatgpt.com",
            "chat.openai.com",
            "openai.com",
            "bilibili.com",
            "b23.tv",
            "ChatGPT",
        ]:
            require_absent(
                source,
                forbidden,
                label=f"MC-B2 hostname-specific {label}: {forbidden}",
            )
    for source, label in [
        (web_factory, "WebViewFactory"),
        (popup, "PopupCoordinator"),
        (pool, "WebViewPool"),
    ]:
        for forbidden in [
            "WKWebsiteDataStore(forIdentifier:",
            "removeData(",
            "fetchDataRecords",
            "allWebsiteDataTypes",
            "MontereySafariIdentityDiagnostic",
            "FLOATTABS_MONTEREY_H_MODE",
        ]:
            require_absent(
                source,
                forbidden,
                label=f"MC-B2 {label} forbidden feature: {forbidden}",
            )
    require_present(
        factory_tests,
        "testMontereySafariMetadataResolutionIsDeterministic",
        label="MC-B2 Safari resolution test",
    )
    require_present(
        factory_tests,
        "testMontereyPrimaryWebViewUsesPublicIdentityAndNoCustomUserAgent",
        label="MC-B2 primary identity test",
    )
    require_present(
        pool_tests,
        "testAutomaticIdentityIsHostnameIndependentAcrossRealHostFixtures",
        label="MC-B2 real-host automatic identity matrix",
    )
    for fixture in [
        "https://example.com/",
        "https://chatgpt.com/",
        "https://www.bilibili.com/",
    ]:
        require_present(
            pool_tests,
            fixture,
            label=f"MC-B2 real-host fixture: {fixture}",
        )
    require_absent(
        pool_tests,
        "source.customUserAgent =",
        label="MC-B2 test customUserAgent assignment",
    )
    require_absent(
        pool_tests,
        "configuration.applicationNameForUserAgent =",
        label="MC-B2 popup test applicationNameForUserAgent assignment",
    )
    generated_swift = "\n".join(
        path.read_text(encoding="utf-8")
        for directory in (ROOT / "FloatTabs", ROOT / "FloatTabsTests")
        for path in sorted(directory.rglob("*.swift"))
    )
    for forbidden in [
        "preferredContentMode",
        "pageZoom =",
        'value(forKey: "userAgent")',
    ]:
        require_absent(
            generated_swift,
            forbidden,
            label=f"MC-B2 forbidden generated Swift content: {forbidden}",
        )

    generated_production_swift = "\n".join(
        path.read_text(encoding="utf-8")
        for directory in (ROOT / "FloatTabs",)
        for path in sorted(directory.rglob("*.swift"))
    )
    for forbidden in [
        "chatgpt.com",
        "chat.openai.com",
        "openai.com",
        "bilibili.com",
        "b23.tv",
        "ChatGPT",
    ]:
        require_absent(
            generated_production_swift,
            forbidden,
            label=f"MC-B2 forbidden generated production Swift content: {forbidden}",
        )


def main() -> None:
    patch_browser_version_resolver()
    patch_primary_webview()
    patch_disabled_runtime_surface()
    patch_site_policy_and_ui()
    patch_generated_tests()
    verify_contract()
    print("Applied Monterey public Safari-compatible browser identity.")


if __name__ == "__main__":
    main()
