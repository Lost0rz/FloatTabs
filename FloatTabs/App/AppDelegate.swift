import AppKit

@MainActor
final class FullscreenExitShellCoordinator {
    private var observerTokens: [NSObjectProtocol] = []
    private weak var shellToRestore: FloatingPanel?
    private var observedFullscreenWindowNumber: Int?
    private var restoreWorkItem: DispatchWorkItem?

    func start() {
        guard observerTokens.isEmpty else { return }

        let center = NotificationCenter.default
        observerTokens.append(
            center.addObserver(
                forName: NSWindow.willExitFullScreenNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleWillExitFullScreen(notification)
                }
            }
        )
        observerTokens.append(
            center.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                Task { @MainActor [weak self] in
                    self?.handleDidExitFullScreen(notification)
                }
            }
        )
    }

    func stop() {
        restoreWorkItem?.cancel()
        restoreWorkItem = nil
        shellToRestore = nil
        observedFullscreenWindowNumber = nil

        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()
    }

    private func handleWillExitFullScreen(_ notification: Notification) {
        guard let fullscreenWindow = notification.object as? NSWindow,
              fullscreenWindow.collectionBehavior.contains(.fullScreenPrimary),
              let shell = NSApp.windows
                .compactMap({ $0 as? FloatingPanel })
                .first(where: { $0.isOwnElementFullscreenActive }),
              shell.isVisible else {
            return
        }

        restoreWorkItem?.cancel()
        restoreWorkItem = nil
        shellToRestore = shell
        observedFullscreenWindowNumber = fullscreenWindow.windowNumber

        FloatTabsDiagnostics.record(
            "fullscreen_shell_withdraw_before_webkit_exit",
            fields: [
                "fullscreen_window_number": String(fullscreenWindow.windowNumber),
                "fullscreen_window_active_space": String(fullscreenWindow.isOnActiveSpace),
                "fullscreen_window_screen_frame": fullscreenWindow.screen.map { NSStringFromRect($0.frame) } ?? "nil",
                "shell_window_number": String(shell.windowNumber),
                "shell_key": String(shell.isKeyWindow),
                "shell_active_space": String(shell.isOnActiveSpace),
                "shell_screen_frame": shell.screen.map { NSStringFromRect($0.frame) } ?? "nil",
            ]
        )

        // A physical dual-display trace showed that a successful fullscreen exit
        // left WebKit's reusable fullscreen window off the active Space, while an
        // otherwise identical exit with the explicitly summoned FloatTabs Shell
        // still visible caused that same WebKit window to become active-Space
        // affiliated again just before NSWindowDidExitFullScreen. Temporarily
        // withdraw only the Shell window while AppKit completes the fullscreen
        // exit. Keep the PanelController lifecycle logically visible so no WebView
        // ownership, media, or Slot residency changes occur during this transient.
        shell.orderOut(nil)

        FloatTabsDiagnostics.record(
            "fullscreen_shell_withdrawn_for_webkit_exit",
            fields: [
                "fullscreen_window_number": String(fullscreenWindow.windowNumber),
                "shell_window_number": String(shell.windowNumber),
                "shell_visible": String(shell.isVisible),
            ]
        )
    }

    private func handleDidExitFullScreen(_ notification: Notification) {
        guard let fullscreenWindow = notification.object as? NSWindow,
              fullscreenWindow.windowNumber == observedFullscreenWindowNumber,
              let shell = shellToRestore else {
            return
        }

        observedFullscreenWindowNumber = nil
        restoreWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self, weak shell, weak fullscreenWindow] in
            guard let self,
                  let shell,
                  !shell.isOwnElementFullscreenActive else {
                return
            }

            self.shellToRestore = nil
            self.restoreWorkItem = nil
            FloatTabsDiagnostics.record(
                "fullscreen_shell_restored_after_webkit_exit",
                fields: [
                    "fullscreen_window_number": fullscreenWindow.map { String($0.windowNumber) } ?? "nil",
                    "fullscreen_window_active_space": fullscreenWindow.map { String($0.isOnActiveSpace) } ?? "nil",
                    "shell_window_number": String(shell.windowNumber),
                ]
            )
            shell.orderFront(nil)
        }
        restoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var fullscreenExitShellCoordinator: FullscreenExitShellCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()

        let fullscreenExitShellCoordinator = FullscreenExitShellCoordinator()
        self.fullscreenExitShellCoordinator = fullscreenExitShellCoordinator
        fullscreenExitShellCoordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        fullscreenExitShellCoordinator?.stop()
        coordinator?.prepareForTermination()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
