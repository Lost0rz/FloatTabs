#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def replace_once(path: Path, old: str, new: str, marker: str) -> None:
    text = path.read_text()
    if marker in text:
        return
    if old not in text:
        raise SystemExit(f"error: expected Monterey patch context not found in {path}")
    path.write_text(text.replace(old, new, 1))


floating = ROOT / "FloatTabs/Panel/FloatingPanel.swift"
replace_once(
    floating,
    '''    private static let ordinaryCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .canJoinAllApplications,
        .ignoresCycle,
    ]
''',
    '''    private static var ordinaryCollectionBehavior: NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = [
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        if #available(macOS 13.0, *) {
            behavior.insert(.canJoinAllApplications)
        }
        return behavior
    }
''',
    'if #available(macOS 13.0, *) {\n            behavior.insert(.canJoinAllApplications)',
)

fullscreen = ROOT / "FloatTabs/Panel/FullscreenSourceHost.swift"
replace_once(
    fullscreen,
    '''enum FullscreenSourceSessionState: String, Equatable {
    case idle
    case entering
    case fullscreen
    case exiting
    case restoring

    var locksSourceHost: Bool { self != .idle }

    static func next(
        from current: FullscreenSourceSessionState,
        webKitState: WKWebView.FullscreenState
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
        @unknown default:
            return current
        }
    }
}
''',
    '''enum FullscreenWebKitState: Equatable {
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
''',
    'enum FullscreenWebKitState: Equatable',
)

replace_once(
    fullscreen,
    '''    private var fullscreenObservation: NSKeyValueObservation?
    private var restoreGeneration = 0
''',
    '''    private var fullscreenObservation: NSKeyValueObservation?
    private var legacyFullscreenPollGeneration = 0
    private var restoreGeneration = 0
''',
    'private var legacyFullscreenPollGeneration = 0',
)

replace_once(
    fullscreen,
    '''    deinit {
        fullscreenObservation?.invalidate()
    }
''',
    '''    deinit {
        fullscreenObservation?.invalidate()
        legacyFullscreenPollGeneration &+= 1
    }
''',
    'legacyFullscreenPollGeneration &+= 1\n    }',
)

replace_once(
    fullscreen,
    '''    func observeFullscreenState(of webView: WKWebView) {
        if observedWebView === webView { return }

        // Never swap the observation target while WebKit still owns the active
        // source view. Tab changes are queued by PanelController until restore.
        guard !isSessionLocked else { return }

        fullscreenObservation?.invalidate()
        observedWebView = webView
        fullscreenObservation = webView.observe(\\.fullscreenState, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, let webView = self.observedWebView else { return }
                self.handleFullscreenStateChange(of: webView)
            }
        }

        handleFullscreenStateChange(of: webView)
    }
''',
    '''    func observeFullscreenState(of webView: WKWebView) {
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
''',
    'private func startLegacyFullscreenPolling(of webView: WKWebView)',
)

replace_once(
    fullscreen,
    '''    private func handleFullscreenStateChange(of webView: WKWebView) {
        let previous = sessionState
        let next = FullscreenSourceSessionState.next(
            from: sessionState,
            webKitState: webView.fullscreenState
        )
        let wasLocked = isSessionLocked
        sessionState = next
        onSessionStateChange?(next)

        if !wasLocked, next.locksSourceHost {
            fullscreenPresentationWindow = nil
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

        captureFullscreenPresentationWindowIfNeeded(for: webView)

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
''',
    '''    private func handleFullscreenStateChange(
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
''',
    'webKitState: FullscreenWebKitState\n    ) {',
)

replace_once(
    fullscreen,
    '''        let isBackInSourceHierarchy = webView.fullscreenState == .notInFullscreen
            && webView.window === window
            && container.window === window
            && webView.isDescendant(of: container)
''',
    '''        let isBackInSourceHierarchy = webView.window === window
            && container.window === window
            && webView.isDescendant(of: container)
''',
    'let isBackInSourceHierarchy = webView.window === window',
)

# The test suite itself must not reference a 13-only OptionSet member while
# compiling with a 12.0 deployment target.
tests = ROOT / "FloatTabsTests/ExternalShellTests.swift"
replace_once(
    tests,
    '''        XCTAssertFalse(behavior.contains(.canJoinAllApplications))
''',
    '''        if #available(macOS 13.0, *) {
            XCTAssertFalse(behavior.contains(.canJoinAllApplications))
        }
''',
    'if #available(macOS 13.0, *) {\n            XCTAssertFalse(behavior.contains(.canJoinAllApplications))',
)

print("Applied deterministic Monterey source compatibility patches.")
