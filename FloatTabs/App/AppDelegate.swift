import AppKit

@MainActor
final class FullscreenSpaceRebindCoordinator {
    private var localEventMonitor: Any?
    private var cleanupWorkItem: DispatchWorkItem?

    func start() {
        guard localEventMonitor == nil else { return }

        // WebKit historically had a macOS fullscreen bug where its reusable
        // fullscreen window remembered the Space from the first presentation.
        // The upstream fix was to orderBack the fullscreen window immediately
        // before starting the next fullscreen transition so AppKit associates it
        // with the current Space. FloatTabs can reproduce the same shape across
        // displays: Shell/source stays on A, WebKit fullscreen succeeds on B,
        // exit returns the WKWebView to A, while the hidden reusable fullscreen
        // window remains associated with B and a later A enter aborts.
        //
        // Observe only the second click of a local double-click. Never swallow or
        // rewrite the event. The event is returned unchanged to the WKWebView.
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) {
            [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated {
                self.prepareReusableFullscreenWindowIfNeeded(for: event)
                return event
            }
        }
    }

    func stop() {
        cleanupWorkItem?.cancel()
        cleanupWorkItem = nil
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
    }

    private func prepareReusableFullscreenWindowIfNeeded(for event: NSEvent) {
        guard event.clickCount >= 2,
              let panel = (event.window ?? NSApp.keyWindow) as? FloatingPanel,
              !panel.isOwnElementFullscreenActive,
              let targetScreen = NSScreen.main,
              let fullscreenWindow = NSApp.windows.first(where: { window in
                  window !== panel
                      && !window.isVisible
                      && window.collectionBehavior.contains(.fullScreenPrimary)
              }) else {
            return
        }

        cleanupWorkItem?.cancel()
        cleanupWorkItem = nil

        FloatTabsDiagnostics.record(
            "fullscreen_space_rebind_before",
            fields: [
                "panel_window_number": String(panel.windowNumber),
                "panel_screen_frame": panel.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                "window_number": String(fullscreenWindow.windowNumber),
                "window_visible": String(fullscreenWindow.isVisible),
                "window_key": String(fullscreenWindow.isKeyWindow),
                "window_active_space": String(fullscreenWindow.isOnActiveSpace),
                "window_frame": NSStringFromRect(fullscreenWindow.frame),
                "window_screen_frame": fullscreenWindow.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                "target_screen_frame": NSStringFromRect(targetScreen.frame),
                "main_screen_frame": NSScreen.main.map { NSStringFromRect($0.frame) } ?? "nil",
            ]
        )

        // Keep WebKit's own collectionBehavior intact. The old FloatTabs re-arm
        // changed behavior, made the window key, and ordered it out again; Real-Mac
        // testing proved that path does not repair the stale Space membership.
        // Here we do the narrower operation used by WebKit's historical Space fix:
        // place the hidden reusable window on the target display, then orderBack it
        // immediately before the user's double-click reaches WebKit. WebKit remains
        // responsible for makeKeyAndOrderFront and enterFullScreenMode.
        if fullscreenWindow.screen?.frame != targetScreen.frame {
            fullscreenWindow.setFrame(targetScreen.frame, display: false)
        }
        fullscreenWindow.orderBack(nil)

        FloatTabsDiagnostics.record(
            "fullscreen_space_rebind_after",
            fields: [
                "window_number": String(fullscreenWindow.windowNumber),
                "window_visible": String(fullscreenWindow.isVisible),
                "window_key": String(fullscreenWindow.isKeyWindow),
                "window_active_space": String(fullscreenWindow.isOnActiveSpace),
                "window_frame": NSStringFromRect(fullscreenWindow.frame),
                "window_screen_frame": fullscreenWindow.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                "target_screen_frame": NSStringFromRect(targetScreen.frame),
            ]
        )

        // A random page double-click may not request fullscreen. If WebKit has not
        // entered a fullscreen state shortly afterward, hide the preparation window
        // again. A genuine fullscreen request flips the panel's observed state to
        // enteringFullscreen almost immediately, so this cleanup stays out of the
        // normal WebKit transition.
        let workItem = DispatchWorkItem { [weak self, weak panel, weak fullscreenWindow] in
            guard let self,
                  let panel,
                  let fullscreenWindow else {
                return
            }
            self.cleanupWorkItem = nil
            guard !panel.isOwnElementFullscreenActive,
                  fullscreenWindow.isVisible,
                  !fullscreenWindow.isKeyWindow else {
                return
            }

            FloatTabsDiagnostics.record(
                "fullscreen_space_rebind_cleanup",
                fields: [
                    "window_number": String(fullscreenWindow.windowNumber),
                    "window_active_space": String(fullscreenWindow.isOnActiveSpace),
                    "window_screen_frame": fullscreenWindow.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                ]
            )
            fullscreenWindow.orderOut(nil)
        }
        cleanupWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40, execute: workItem)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var fullscreenSpaceRebindCoordinator: FullscreenSpaceRebindCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()

        let fullscreenSpaceRebindCoordinator = FullscreenSpaceRebindCoordinator()
        self.fullscreenSpaceRebindCoordinator = fullscreenSpaceRebindCoordinator
        fullscreenSpaceRebindCoordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        fullscreenSpaceRebindCoordinator?.stop()
        coordinator?.prepareForTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
