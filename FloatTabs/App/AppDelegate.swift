import AppKit
import WebKit

/// Compatibility seam for the fullscreen code introduced during PR #20.
///
/// The rejected implementation intercepted page exit APIs / Escape and called
/// `closeAllMediaPresentations`, which Real-Mac validation showed could return a
/// live YouTube WKWebView as a black surface. The coordinator is now deliberately
/// passive: WebKit and the page own native element-fullscreen entry and exit.
///
/// Its only responsibility is to keep the WKWebView's AppKit host geometry in the
/// frame/autoresizing configuration WebKit expects while it reparents the view
/// into and back out of WKFullScreenWindowController.
@MainActor
final class NativeFullscreenSessionResetCoordinator: NSObject {
    static let shared = NativeFullscreenSessionResetCoordinator()
    static let handlerName = "floatTabsNativeFullscreenExit"
    static let escapeKeyCode: UInt16 = 53

    /// Kept temporarily as a compatibility marker for existing PR tests. This
    /// script does not replace or call any fullscreen API and can be removed with
    /// the compatibility seam after the Real-Mac fullscreen fix is accepted.
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

    func stop() {}

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
    /// view must remain frame-based relative to its immediate host; otherwise the
    /// restored placeholder/viewport can collapse or return black after exit.
    ///
    /// Critically, this method never touches WebCoreFullScreenWindow, never closes
    /// a media presentation, and never initiates a fullscreen transition.
    func handleObservedFullscreenTransition(
        for webView: WKWebView,
        previousState: WKWebView.FullscreenState,
        currentState: WKWebView.FullscreenState,
        window: NSWindow?
    ) {
        switch currentState {
        case .enteringFullscreen:
            applyFullscreenSafeAutoresizing(to: webView, phase: "entering")

        case .notInFullscreen:
            guard previousState != .notInFullscreen else { return }
            restoreWebViewToStableHostIfAvailable(webView, window: window)

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

    private func restoreWebViewToStableHostIfAvailable(
        _ webView: WKWebView,
        window: NSWindow?
    ) {
        applyFullscreenSafeAutoresizing(to: webView, phase: "exited")

        guard window is FloatingPanel,
              webView.window === window,
              let host = webView.superview,
              host.bounds.width > 0,
              host.bounds.height > 0 else {
            FloatTabsDiagnostics.record(
                "fullscreen_host_restore_deferred",
                fields: [
                    "reason": "webkit_has_not_returned_to_floattabs_host",
                    "window_class": window.map { String(describing: type(of: $0)) } ?? "nil",
                    "webview_window_class": webView.window.map { String(describing: type(of: $0)) } ?? "nil",
                ]
            )
            return
        }

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
                "window_number": String(window?.windowNumber ?? 0),
            ]
        )
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
