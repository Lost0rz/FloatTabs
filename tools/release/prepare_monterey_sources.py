#!/usr/bin/env python3
"""Stage 1: standard source -> dual-path (macOS 13+ / Monterey) compile compat.

Anchors are function signatures and stable declaration boundaries, never
verbatim multi-line blocks; every structural replacement validates that its
anchor matches exactly once (see monterey_transform_lib).
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from monterey_transform_lib import (
    read_source,
    replace_once_regex,
    replace_span_once,
    require_present,
    write_source,
)

ROOT = Path(__file__).resolve().parents[2]

# ---------------------------------------------------------------------------
# FloatingPanel: make the macOS-13-only collection member availability-guarded
# so a 12.0 deployment target still compiles.
# ---------------------------------------------------------------------------
floating = ROOT / "FloatTabs/Panel/FloatingPanel.swift"
text = read_source(floating)
text = replace_once_regex(
    text,
    r"    private static let ordinaryCollectionBehavior: NSWindow\.CollectionBehavior = \[\s*"
    r"\.canJoinAllSpaces,\s*"
    r"\.canJoinAllApplications,\s*"
    r"\.ignoresCycle,\s*"
    r"\]",
    """    private static var ordinaryCollectionBehavior: NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        if #available(macOS 13.0, *) {
            behavior.insert(.canJoinAllApplications)
        }
        return behavior
    }
""",
    label="FloatingPanel.ordinaryCollectionBehavior",
)
write_source(floating, text)

# ---------------------------------------------------------------------------
# FullscreenSourceHost: give the session state machine a 12-compatible
# FullscreenWebKitState shim and split fullscreen observation into a modern
# (macOS 13+) observer and a legacy polling path.
# ---------------------------------------------------------------------------
fullscreen = ROOT / "FloatTabs/Panel/FullscreenSourceHost.swift"
text = read_source(fullscreen)

# Replace the whole session-state enum (its `WKWebView.FullscreenState`
# parameter is macOS 13-only) with the shim enum + adapter + a compatible
# state machine.
text = replace_span_once(
    text,
    r"^enum FullscreenSourceSessionState: String, Equatable \{",
    r"^enum FullscreenRestoreWatchdogDecision",
    """enum FullscreenWebKitState: Equatable {
    case enteringFullscreen
    case inFullscreen
    case exitingFullscreen
    case notInFullscreen
}

@available(macOS 13.0, *)
private extension FullscreenWebKitState {
    init(_ state: WKWebView.FullscreenState) {
        switch state {
        case .enteringFullscreen:
            self = .enteringFullscreen
        case .inFullscreen:
            self = .inFullscreen
        case .exitingFullscreen:
            self = .exitingFullscreen
        case .notInFullscreen:
            self = .notInFullscreen
        @unknown default:
            self = .notInFullscreen
        }
    }
}

enum FullscreenSourceSessionState: String, Equatable {
    case idle
    case entering
    case fullscreen
    case exiting
    case restoring

    var locksSourceHost: Bool { self != .idle }

    static func next(
        from current: FullscreenSourceSessionState,
        webKitState: FullscreenWebKitState
    ) -> FullscreenSourceSessionState {
        switch webKitState {
        case .enteringFullscreen:
            return .entering
        case .inFullscreen:
            return .fullscreen
        case .exitingFullscreen:
            return .exiting
        case .notInFullscreen:
            return current == .idle ? .idle : .restoring
        }
    }
}

""",
    label="FullscreenSourceHost.session-state enum",
)

# The legacy polling path needs its own generation counter.
text = replace_once_regex(
    text,
    r"    private var fullscreenObservation: NSKeyValueObservation\?\s*"
    r"    private var restoreGeneration = 0",
    """    private var fullscreenObservation: NSKeyValueObservation?
    private var legacyFullscreenPollGeneration = 0
    private var restoreGeneration = 0""",
    label="FullscreenSourceHost.poll generation storage",
)

# Retiring the observer must also retire any in-flight legacy poll.
text = replace_once_regex(
    text,
    r"    deinit \{\s*fullscreenObservation\?\.invalidate\(\)\s*\}",
    """    deinit {
        fullscreenObservation?.invalidate()
        legacyFullscreenPollGeneration &+= 1
    }""",
    label="FullscreenSourceHost.deinit",
)

# observeFullscreenState: split into availability-branched modern observer +
# legacy polling loop. Span runs to the next sibling declaration.
text = replace_span_once(
    text,
    r"^    func observeFullscreenState\(of webView: WKWebView\) \{",
    r"^    static func sourceFrame\(",
    """    func observeFullscreenState(of webView: WKWebView) {
        if observedWebView === webView { return }

        // Never swap the observation target while WebKit still owns the active
        // source view. Tab changes are queued by PanelController until restore.
        guard !isSessionLocked else { return }

        fullscreenObservation?.invalidate()
        legacyFullscreenPollGeneration &+= 1
        observedWebView = webView

        if #available(macOS 13.0, *) {
            observeModernFullscreenState(of: webView)
        } else {
            startLegacyFullscreenPolling(of: webView)
        }
    }

    @available(macOS 13.0, *)
    private func observeModernFullscreenState(of webView: WKWebView) {
        fullscreenObservation = webView.observe(\\.fullscreenState, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, let webView = self.observedWebView else { return }
                self.handleFullscreenStateChange(
                    of: webView,
                    webKitState: FullscreenWebKitState(webView.fullscreenState)
                )
            }
        }

        handleFullscreenStateChange(
            of: webView,
            webKitState: FullscreenWebKitState(webView.fullscreenState)
        )
    }

    private func startLegacyFullscreenPolling(of webView: WKWebView) {
        legacyFullscreenPollGeneration &+= 1
        let generation = legacyFullscreenPollGeneration
        pollLegacyFullscreenState(of: webView, generation: generation)
    }

    private func pollLegacyFullscreenState(of webView: WKWebView, generation: Int) {
        guard generation == legacyFullscreenPollGeneration,
              observedWebView === webView else {
            return
        }

        captureFullscreenPresentationWindowIfNeeded(for: webView)

        if sessionState != .restoring {
            let hasForeignWindow = webView.window.map { $0 !== window } ?? false
            let presentationActive = Self.isWebKitFullscreenPresentationActive(
                capturedWindow: fullscreenPresentationWindow,
                applicationWindows: NSApp.windows
            )
            let webKitState: FullscreenWebKitState
            if hasForeignWindow || presentationActive {
                webKitState = sessionState == .idle ? .enteringFullscreen : .inFullscreen
            } else {
                webKitState = .notInFullscreen
            }
            handleFullscreenStateChange(of: webView, webKitState: webKitState)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak webView] in
            guard let self, let webView else { return }
            self.pollLegacyFullscreenState(of: webView, generation: generation)
        }
    }

""",
    label="FullscreenSourceHost.observeFullscreenState",
)

# handleFullscreenStateChange: take the 12-compatible state as a parameter and
# de-duplicate transitions. Span runs to the next sibling declaration.
text = replace_span_once(
    text,
    r"^    private func handleFullscreenStateChange\(of webView: WKWebView\) \{",
    r"^    private func captureFullscreenPresentationWindowIfNeeded\(",
    """    private func handleFullscreenStateChange(
        of webView: WKWebView,
        webKitState: FullscreenWebKitState
    ) {
        let previous = sessionState
        let next = FullscreenSourceSessionState.next(
            from: sessionState,
            webKitState: webKitState
        )

        captureFullscreenPresentationWindowIfNeeded(for: webView)
        guard next != previous else { return }

        let wasLocked = isSessionLocked
        sessionState = next
        onSessionStateChange?(next)

        if !wasLocked, next.locksSourceHost {
            fullscreenPresentationWindow = nil
            captureFullscreenPresentationWindowIfNeeded(for: webView)
            // In ordinary presentation the source is a child of the shell so
            // Mission Control treats the rail, outline and Web surface as one
            // window group. Detach before hiding the shell: WebKit must keep
            // its source window independently ordered throughout fullscreen.
            detachSourceWindowFromShell()
            window.collectionBehavior = Self.sourceWindowCollectionBehavior
            // Preserve the ordered source and hierarchy WebKit needs for
            // restoration without exposing its tab-less placeholder window.
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            restoreGeneration &+= 1
            fullscreenExperimentLog(
                "FULLSCREEN state=\\(next.rawValue) source=\\(window.windowNumber) "
                    + "screen=\\(fullscreenExperimentScreenID(window.screen))"
            )
            onSessionLockChange?(true)
        }

        guard next == .restoring else { return }
        if previous != .restoring {
            restoreStartedAtUptime = ProcessInfo.processInfo.systemUptime
        }
        waitForPublicSourceRestoration(
            of: webView,
            generation: restoreGeneration,
            stableChecks: 0
        )
    }

""",
    label="FullscreenSourceHost.handleFullscreenStateChange",
)

# waitForPublicSourceRestoration must not read `.fullscreenState` (13-only).
text = replace_once_regex(
    text,
    r"        let isBackInSourceHierarchy = webView\.fullscreenState == \.notInFullscreen\s*"
    r"&& webView\.window === window",
    """        let isBackInSourceHierarchy = webView.window === window""",
    label="FullscreenSourceHost.waitForPublicSourceRestoration",
)
write_source(fullscreen, text)

# ---------------------------------------------------------------------------
# Tests: the suite must not reference a 13-only OptionSet member while
# compiling with a 12.0 deployment target.
# ---------------------------------------------------------------------------
shell_tests = ROOT / "FloatTabsTests/ExternalShellTests.swift"
text = read_source(shell_tests)
text = replace_once_regex(
    text,
    r"        XCTAssertFalse\(behavior\.contains\(\.canJoinAllApplications\)\)",
    """        if #available(macOS 13.0, *) {
            XCTAssertFalse(behavior.contains(.canJoinAllApplications))
        }""",
    label="ExternalShellTests.canJoinAllApplications",
)
write_source(shell_tests, text)

# ---------------------------------------------------------------------------
# Post-transform contract for this stage.
# ---------------------------------------------------------------------------
prepared_fullscreen = read_source(fullscreen)
for required in [
    "enum FullscreenWebKitState: Equatable",
    "private func startLegacyFullscreenPolling(of webView: WKWebView)",
    "webKitState: FullscreenWebKitState",
    "legacyFullscreenPollGeneration &+= 1\n    }",
]:
    require_present(
        prepared_fullscreen,
        required,
        label="sources stage FullscreenSourceHost output",
    )
require_present(
    read_source(floating),
    "if #available(macOS 13.0, *) {\n            behavior.insert(.canJoinAllApplications)",
    label="sources stage FloatingPanel output",
)
require_present(
    read_source(shell_tests),
    "if #available(macOS 13.0, *) {\n            XCTAssertFalse(behavior.contains(.canJoinAllApplications))",
    label="sources stage ExternalShellTests output",
)

print("Applied deterministic Monterey source compatibility patches.")
