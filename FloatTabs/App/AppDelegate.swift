import AppKit
import WebKit

/// Compatibility seam for the fullscreen code introduced during PR #20.
///
/// The rejected implementation intercepted page exit APIs / Escape and forced a
/// media-presentation shutdown. Real-Mac validation showed that this could return
/// a live YouTube WKWebView as a black surface. This coordinator is now passive:
/// WebKit and the page own native element-fullscreen entry and exit end-to-end.
///
/// Its only runtime responsibility is preserving the WKWebView's original AppKit
/// host geometry while WebKit temporarily reparents the view into and back out of
/// its native fullscreen controller.
@MainActor
final class NativeFullscreenSessionResetCoordinator: NSObject {
    static let shared = NativeFullscreenSessionResetCoordinator()
    static let handlerName = "floatTabsNativeFullscreenExit"
    static let escapeKeyCode: UInt16 = 53

    private weak var fullscreenWebView: WKWebView?
    private weak var fullscreenHostView: NSView?
    private var hostRestoreWorkItem: DispatchWorkItem?

    /// Kept temporarily as a compatibility marker for existing PR tests. This
    /// script does not replace, call, or observe any fullscreen API and can be
    /// removed with the compatibility seam after Real-Mac acceptance.
    static func exitBridgeUserScript() -> WKUserScript {
        WKUserScript(
            source: """
            (() => {
              if (window.__floatTabsNativeFullscreenExitBridgeInstalled) return;
              window.__floatTabsNativeFullscreenExitBridgeInstalled = true;
              // Passive compatibility marker only: Document.prototype, 'exitFullscreen'
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    func install(in configuration: WKWebViewConfiguration) {
        configuration.userContentController.addUserScript(Self.exitBridgeUserScript())
    }

    func start() {}

    func stop() {
        hostRestoreWorkItem?.cancel()
        hostRestoreWorkItem = nil
        fullscreenWebView = nil
        fullscreenHostView = nil
    }

    /// Compatibility-only pure policy helpers retained until the surrounding PR
    /// tests are simplified. They no longer drive any runtime exit operation.
    static func shouldResetForEscape(
        keyCode: UInt16,
        fullscreenState: WKWebView.FullscreenState,
        resetInFlight: Bool
    ) -> Bool {
        keyCode == escapeKeyCode
            && fullscreenState == .inFullscreen
            && !resetInFlight
    }

    static func canResetForPageExit(
        fullscreenState: WKWebView.FullscreenState,
        resetInFlight: Bool
    ) -> Bool {
        guard !resetInFlight else { return false }
        return fullscreenState == .enteringFullscreen
            || fullscreenState == .inFullscreen
    }

    static func shouldDisposeObservedNativeExit(
        previousState: WKWebView.FullscreenState,
        currentState: WKWebView.FullscreenState,
        resetInFlight: Bool
    ) -> Bool {
        guard !resetInFlight,
              previousState != .notInFullscreen else {
            return false
        }
        return currentState == .exitingFullscreen
            || currentState == .notInFullscreen
    }

    /// WebKit's macOS fullscreen controller temporarily reparents WKWebView. The
    /// original immediate host stays owned by FloatTabs. We remember that host at
    /// `.enteringFullscreen`, make the WKWebView frame/autoresizing based, then
    /// wait for WebKit itself to reattach the same view before restoring geometry.
    ///
    /// This method never orders, hides, moves, resizes, retains, or otherwise
    /// mutates WebKit's fullscreen NSWindow and never initiates an exit.
    func handleObservedFullscreenTransition(
        for webView: WKWebView,
        previousState: WKWebView.FullscreenState,
        currentState: WKWebView.FullscreenState,
        window: NSWindow?
    ) {
        switch currentState {
        case .enteringFullscreen:
            hostRestoreWorkItem?.cancel()
            hostRestoreWorkItem = nil
            fullscreenWebView = webView
            fullscreenHostView = webView.superview
            applyFullscreenSafeAutoresizing(to: webView, phase: "entering")

            FloatTabsDiagnostics.record(
                "fullscreen_original_host_captured",
                fields: [
                    "host_class": fullscreenHostView.map { String(describing: type(of: $0)) } ?? "nil",
                    "host_bounds": fullscreenHostView.map { NSStringFromRect($0.bounds) } ?? "nil",
                    "webview_frame": NSStringFromRect(webView.frame),
                ]
            )

        case .notInFullscreen:
            guard previousState != .notInFullscreen else { return }
            scheduleHostRestore(for: webView, remainingAttempts: 8)

        case .inFullscreen, .exitingFullscreen:
            break

        @unknown default:
            break
        }
    }

    private func applyFullscreenSafeAutoresizing(
        to webView: WKWebView,
        phase: String
    ) {
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]

        FloatTabsDiagnostics.record(
            "fullscreen_host_autoresizing_applied",
            fields: [
                "phase": phase,
                "webview_frame": NSStringFromRect(webView.frame),
                "host_bounds": webView.superview.map { NSStringFromRect($0.bounds) } ?? "nil",
                "window_number": webView.window.map { String($0.windowNumber) } ?? "nil",
            ]
        )
    }

    private func scheduleHostRestore(
        for webView: WKWebView,
        remainingAttempts: Int
    ) {
        guard fullscreenWebView === webView else { return }

        if restoreWebViewToOriginalHostIfAvailable(webView) {
            finishHostRestore()
            return
        }

        guard remainingAttempts > 0 else {
            FloatTabsDiagnostics.record(
                "fullscreen_host_restore_timed_out",
                fields: [
                    "webview_window_class": webView.window.map { String(describing: type(of: $0)) } ?? "nil",
                    "webview_superview_class": webView.superview.map { String(describing: type(of: $0)) } ?? "nil",
                    "expected_host_class": fullscreenHostView.map { String(describing: type(of: $0)) } ?? "nil",
                ]
            )
            finishHostRestore()
            return
        }

        hostRestoreWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak webView] in
            guard let self, let webView else { return }
            self.hostRestoreWorkItem = nil
            self.scheduleHostRestore(
                for: webView,
                remainingAttempts: remainingAttempts - 1
            )
        }
        hostRestoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func restoreWebViewToOriginalHostIfAvailable(_ webView: WKWebView) -> Bool {
        guard fullscreenWebView === webView,
              let host = fullscreenHostView,
              webView.window is FloatingPanel,
              webView.superview === host,
              host.bounds.width > 0,
              host.bounds.height > 0 else {
            FloatTabsDiagnostics.record(
                "fullscreen_host_restore_waiting",
                fields: [
                    "webview_window_class": webView.window.map { String(describing: type(of: $0)) } ?? "nil",
                    "webview_superview_class": webView.superview.map { String(describing: type(of: $0)) } ?? "nil",
                    "expected_host_class": fullscreenHostView.map { String(describing: type(of: $0)) } ?? "nil",
                ]
            )
            return false
        }

        applyFullscreenSafeAutoresizing(to: webView, phase: "restored")

        let targetFrame = host.bounds
        if abs(webView.frame.minX - targetFrame.minX) > 0.5
            || abs(webView.frame.minY - targetFrame.minY) > 0.5
            || abs(webView.frame.width - targetFrame.width) > 0.5
            || abs(webView.frame.height - targetFrame.height) > 0.5 {
            webView.frame = targetFrame
        }

        host.needsLayout = true
        host.layoutSubtreeIfNeeded()
        webView.needsLayout = true
        webView.layoutSubtreeIfNeeded()

        FloatTabsDiagnostics.record(
            "fullscreen_host_restored",
            fields: [
                "webview_frame": NSStringFromRect(webView.frame),
                "host_bounds": NSStringFromRect(host.bounds),
                "window_number": webView.window.map { String($0.windowNumber) } ?? "nil",
            ]
        )
        return true
    }

    private func finishHostRestore() {
        hostRestoreWorkItem?.cancel()
        hostRestoreWorkItem = nil
        fullscreenWebView = nil
        fullscreenHostView = nil
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
        NativeFullscreenSessionResetCoordinator.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NativeFullscreenSessionResetCoordinator.shared.stop()
        coordinator?.prepareForTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
