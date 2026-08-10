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
    private var selectedFaviconOriginKey: String?

    init(
        onToggle: @escaping () -> Void,
        isVisible: @escaping () -> Bool,
        onQuit: @escaping () -> Void
    ) {
        self.onToggle = onToggle
        self.isVisible = isVisible
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()
        configureStatusItem()
        configureMenu()
    }

    static func displayTitle(for activeWebAppName: String?) -> String {
        let value = activeWebAppName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "FloatTabs" : value
    }

    static func faviconOriginKey(for activeWebAppURL: URL?) -> String? {
        activeWebAppURL.flatMap(WebsiteFaviconProvider.originKey(for:))
    }

    func setActiveWebApp(name: String?, homeURL: URL?) {
        guard let button = statusItem.button else { return }
        button.title = Self.displayTitle(for: name)
        button.toolTip = name.map { "Current Web App · \($0)" } ?? "FloatTabs"

        guard let homeURL,
              let originKey = Self.faviconOriginKey(for: homeURL) else {
            selectedFaviconOriginKey = nil
            button.image = Self.fallbackImage()
            return
        }

        selectedFaviconOriginKey = originKey
        // Never leave the previous site's favicon visible while a newly selected
        // origin is loading. The shared provider normally returns immediately from
        // the same cache already populated by the tab rail.
        button.image = Self.fallbackImage()
        WebsiteFaviconProvider.shared.load(for: homeURL) { [weak self] image in
            guard let self,
                  self.selectedFaviconOriginKey == originKey else { return }
            self.applyStatusImage(image)
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = Self.fallbackImage()
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.title = Self.displayTitle(for: nil)
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func applyStatusImage(_ favicon: NSImage?) {
        guard let button = statusItem.button,
              let favicon else {
            statusItem.button?.image = Self.fallbackImage()
            return
        }

        // Do not mutate the shared cached NSImage because the rail uses the same
        // instance. Status-bar sizing is presentation-specific.
        let image = (favicon.copy() as? NSImage) ?? favicon
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = false
        button.image = image
    }

    private static func fallbackImage() -> NSImage? {
        let image = NSImage(
            systemSymbolName: "rectangle.on.rectangle",
            accessibilityDescription: "FloatTabs"
        )
        image?.isTemplate = true
        return image
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
