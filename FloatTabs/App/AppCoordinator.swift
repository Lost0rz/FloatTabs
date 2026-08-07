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
            isVisible: { [weak self] in self?.panelController.isVisible ?? false },
            onQuit: { NSApp.terminate(nil) }
        )

        globalHotkeyController = GlobalHotkeyController(
            onToggle: { [weak self] in self?.toggleFloatTabs() }
        )
    }

    func prepareForTermination() {
        panelController.prepareForTermination()
    }

    private func toggleFloatTabs() {
        if panelController.isVisible {
            panelController.hideFloatTabs()
        } else {
            panelController.showFloatTabs()
        }
    }
}
