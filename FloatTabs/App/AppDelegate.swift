import AppKit
import WebKit

@MainActor
final class FullscreenSessionCoordinator {
    private var localEventMonitor: Any?
    private var closeInFlight = false

    func start() {
        guard localEventMonitor == nil else { return }

        // WebKit's macOS element-fullscreen implementation reuses one
        // WKFullScreenWindowController / WebCoreFullScreenWindow across normal
        // exits. Real-Mac dual-display traces show that after a successful
        // cross-display session the reused controller can continue to enter on
        // one display while AppKit aborts entry on the other, even when
        // NSScreen.main, the window frame/screen, and key status are all correct.
        //
        // Do not mutate that private WebKit window. Instead intercept the two
        // user exit gestures we can identify without site-specific JavaScript
        // (Escape and a video double-click) while WKWebView is stably fullscreen,
        // and ask WebKit through its public API to close the presentation. Current
        // WebKit routes closeAllMediaPresentations() through its fullscreen manager
        // while fullscreen is active, which closes the macOS fullscreen manager
        // rather than leaving the normal reusable controller behind.
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated {
                self.handleLocalEvent(event)
            }
        }
    }

    func stop() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        closeInFlight = false
    }

    static func shouldCloseFullscreenPresentation(
        eventType: NSEvent.EventType,
        clickCount: Int,
        keyCode: UInt16,
        fullscreenState: WKWebView.FullscreenState,
        closeInFlight: Bool
    ) -> Bool {
        guard fullscreenState == .inFullscreen, !closeInFlight else { return false }

        if eventType == .keyDown {
            return keyCode == 53 // Escape
        }

        if eventType == .leftMouseDown {
            return clickCount >= 2
        }

        return false
    }

    private func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        let window = event.window ?? NSApp.keyWindow
        guard let window,
              window.collectionBehavior.contains(.fullScreenPrimary),
              let webView = firstWebView(in: window.contentView),
              Self.shouldCloseFullscreenPresentation(
                eventType: event.type,
                clickCount: event.clickCount,
                keyCode: event.keyCode,
                fullscreenState: webView.fullscreenState,
                closeInFlight: closeInFlight
              ) else {
            return event
        }

        let trigger = event.type == .keyDown ? "escape" : "double_click"
        closeInFlight = true

        FloatTabsDiagnostics.record(
            "fullscreen_public_close_requested",
            fields: [
                "trigger": trigger,
                "fullscreen_state": String(describing: webView.fullscreenState),
                "window_number": String(window.windowNumber),
                "window_active_space": String(window.isOnActiveSpace),
                "window_screen_frame": window.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                "main_screen_frame": NSScreen.main.map { NSStringFromRect($0.frame) } ?? "nil",
            ]
        )

        webView.closeAllMediaPresentations { [weak self, weak webView, weak window] in
            Task { @MainActor [weak self, weak webView, weak window] in
                guard let self else { return }
                self.closeInFlight = false

                FloatTabsDiagnostics.record(
                    "fullscreen_public_close_completed",
                    fields: [
                        "trigger": trigger,
                        "fullscreen_state": webView.map { String(describing: $0.fullscreenState) } ?? "released",
                        "window_number": window.map { String($0.windowNumber) } ?? "released",
                        "window_visible": window.map { String($0.isVisible) } ?? "released",
                        "window_active_space": window.map { String($0.isOnActiveSpace) } ?? "released",
                        "window_screen_frame": window?.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                    ]
                )
            }
        }

        // Suppress the site's own exit event. WebKit now owns this exit through
        // closeAllMediaPresentations(), so the same gesture cannot start a second,
        // overlapping normal-exit path.
        return nil
    }

    private func firstWebView(in view: NSView?) -> WKWebView? {
        guard let view else { return nil }
        if let webView = view as? WKWebView {
            return webView
        }

        for subview in view.subviews {
            if let webView = firstWebView(in: subview) {
                return webView
            }
        }
        return nil
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var fullscreenSessionCoordinator: FullscreenSessionCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()

        let fullscreenSessionCoordinator = FullscreenSessionCoordinator()
        self.fullscreenSessionCoordinator = fullscreenSessionCoordinator
        fullscreenSessionCoordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        fullscreenSessionCoordinator?.stop()
        coordinator?.prepareForTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
