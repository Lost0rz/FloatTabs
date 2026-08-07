import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onToggle: () -> Void
    private let onQuit: () -> Void

    init(onToggle: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureStatusItem()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "FloatTabs")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle FloatTabs", action: #selector(toggle), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit FloatTabs", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items {
            item.target = self
        }

        statusItem.menu = menu
    }

    @objc private func toggle() {
        onToggle()
    }

    @objc private func quit() {
        onQuit()
    }
}
