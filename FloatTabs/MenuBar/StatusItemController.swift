import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let toggleMenuItem = NSMenuItem(
        title: "Show FloatTabs",
        action: #selector(toggleFromMenu),
        keyEquivalent: ""
    )

    private let onToggle: () -> Void
    private let isVisible: () -> Bool
    private let onQuit: () -> Void

    init(
        onToggle: @escaping () -> Void,
        isVisible: @escaping () -> Bool,
        onQuit: @escaping () -> Void
    ) {
        self.onToggle = onToggle
        self.isVisible = isVisible
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        super.init()
        configureStatusItem()
        configureMenu()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        let image = NSImage(
            systemSymbolName: "rectangle.on.rectangle",
            accessibilityDescription: "FloatTabs"
        )
        image?.isTemplate = true
        button.image = image
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit FloatTabs",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            onToggle()
            return
        }

        let shouldOpenMenu = event.type == .rightMouseUp
            || event.modifierFlags.contains(.control)

        if shouldOpenMenu {
            presentMenu(from: sender)
        } else {
            onToggle()
        }
    }

    private func presentMenu(from button: NSStatusBarButton) {
        toggleMenuItem.title = isVisible() ? "Hide FloatTabs" : "Show FloatTabs"
        menu.popUp(
            positioning: toggleMenuItem,
            at: NSPoint(x: 0, y: button.bounds.minY),
            in: button
        )
    }

    @objc private func toggleFromMenu() {
        onToggle()
    }

    @objc private func quit() {
        onQuit()
    }
}
