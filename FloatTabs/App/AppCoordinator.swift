import AppKit

@MainActor
final class AppCoordinator {
    private let panelController: PanelController
    private var statusItemController: StatusItemController?
    private var globalHotkeyController: GlobalHotkeyController?

    init(panelController: PanelController? = nil) {
        self.panelController = panelController ?? PanelController()
    }

    func start() {
        statusItemController = StatusItemController(
            onToggle: { [weak self] in self?.toggleFloatTabs() },
            onQuit: { NSApp.terminate(nil) }
        )

        globalHotkeyController = GlobalHotkeyController(
            onToggle: { [weak self] in self?.toggleFloatTabs() }
        )
    }

    private func toggleFloatTabs() {
        if panelController.isVisible {
            panelController.hideFloatTabs()
        } else {
            panelController.showFloatTabs()
        }
    }
}
