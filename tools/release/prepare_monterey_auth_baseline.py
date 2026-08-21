#!/usr/bin/env python3
"""Stage 11: isolated stock-WKWebView authentication baseline.

This transform is only used by build_monterey_auth_baseline_dmg.sh.  It
replaces the generated compatibility AppDelegate in the temporary build tree;
the normal MC-B4 source and build path are not changed.
"""

import os
from pathlib import Path

from monterey_transform_lib import read_source, require_present, write_source


ROOT = Path(
    os.environ.get(
        "FLOATTABS_TRANSFORM_ROOT",
        str(Path(__file__).resolve().parents[2]),
    )
)


BASELINE_APP_DELEGATE = r'''import AppKit
import Foundation
import WebKit

@MainActor
private extension MontereyBrowserDataStoreManager {
    var persistentStore: WKWebsiteDataStore { websiteDataStore }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        removeBrowsingDataThenLaunch()
    }

    private func removeBrowsingDataThenLaunch() {
        let store = MontereyBrowserDataStoreManager.shared.persistentStore
        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.launchBaselineWindow()
            }
        }
    }

    private func launchBaselineWindow() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = MontereyBrowserDataStoreManager.shared.persistentStore

        if let applicationName = MontereySafariIdentity.applicationName {
            configuration.applicationNameForUserAgent = applicationName
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        assert(webView.customUserAgent == nil)
        assert(
            webView.configuration.applicationNameForUserAgent
                == MontereySafariIdentity.applicationName
        )

        let contentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 900, height: 760)
        )
        webView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: contentView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FloatTabs Monterey Auth Baseline"
        window.contentView = contentView
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.webView = webView
        self.window = window
        NSApp.activate(ignoringOtherApps: true)

        webView.load(
            URLRequest(url: URL(string: "https://chatgpt.com/")!)
        )
    }
}
'''


def main() -> None:
    app_delegate = ROOT / "FloatTabs/App/AppDelegate.swift"
    write_source(app_delegate, BASELINE_APP_DELEGATE)

    # The MC-B3 data-store manager and MC-B2 identity are supplied by the
    # earlier build-time transforms.  Fail closed if either authority is not
    # present in the generated tree.
    factory = read_source(ROOT / "FloatTabs/Web/WebViewFactory.swift")
    require_present(
        factory,
        "static let shared = MontereyBrowserDataStoreManager()",
        label="auth-baseline persistent data-store authority",
    )
    require_present(
        factory,
        "websiteDataStore: WKWebsiteDataStore = .default()",
        label="auth-baseline default WebsiteDataStore authority",
    )
    require_present(
        factory,
        "enum MontereySafariIdentity",
        label="auth-baseline Safari identity",
    )
    print("Applied isolated Monterey stock WKWebView auth baseline.")


if __name__ == "__main__":
    main()
