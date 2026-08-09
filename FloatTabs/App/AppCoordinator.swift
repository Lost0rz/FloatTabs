import AppKit

@MainActor
final class AppCoordinator {
    private let panelController: PanelController
    private var statusItemController: StatusItemController?
    private var globalHotkeyController: GlobalHotkeyController?
    private var appCommandController: AppCommandController?

    init(panelController: PanelController? = nil) {
        if let panelController {
            self.panelController = panelController
        } else {
            let tabStore = TabStore(repository: ProfileRepository())
            let webViewPool = WebViewPool(
                onURLChange: { slotID, url in
                    tabStore.updateCurrentURL(id: slotID, url: url)
                },
                isSlotActive: { slotID in
                    tabStore.activeTabID == slotID
                }
            )
            self.panelController = PanelController(
                tabStore: tabStore,
                webViewPool: webViewPool
            )
        }
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

        appCommandController = AppCommandController(
            isEnabled: { [weak self] in
                NSApp.isActive && (self?.panelController.isVisible ?? false)
            },
            onCommand: { [weak self] command in
                self?.panelController.handle(command)
            }
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
