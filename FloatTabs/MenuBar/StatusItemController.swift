import AppKit
import KeyboardShortcuts

struct MenuShortcutPresentation: Equatable {
    let keyEquivalent: String
    let modifiers: NSEvent.ModifierFlags
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let toggleMenuItem = NSMenuItem(
        title: "Show FloatTabs",
        action: #selector(toggleFromMenu),
        keyEquivalent: ""
    )
    private let settingsMenuItem = NSMenuItem(
        title: "Settings…",
        action: #selector(openSettings),
        keyEquivalent: ""
    )

    private let onToggle: () -> Void
    private let onCaptureForegroundGeneration: () -> UInt
    private let onReassertForeground: (UInt) -> Void
    private let isVisible: () -> Bool
    private let onSettings: () -> Void
    private let onQuit: () -> Void
    private var selectedFaviconOriginKey: String?

    var menuShortcutPresentations: [String: MenuShortcutPresentation] {
        [
            toggleMenuItem.title: MenuShortcutPresentation(
                keyEquivalent: toggleMenuItem.keyEquivalent,
                modifiers: toggleMenuItem.keyEquivalentModifierMask
            ),
            settingsMenuItem.title: MenuShortcutPresentation(
                keyEquivalent: settingsMenuItem.keyEquivalent,
                modifiers: settingsMenuItem.keyEquivalentModifierMask
            ),
        ]
    }

    init(
        onToggle: @escaping () -> Void,
        onCaptureForegroundGeneration: @escaping () -> UInt = { 0 },
        onReassertForeground: @escaping (UInt) -> Void = { _ in },
        isVisible: @escaping () -> Bool,
        onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onToggle = onToggle
        self.onCaptureForegroundGeneration = onCaptureForegroundGeneration
        self.onReassertForeground = onReassertForeground
        self.isVisible = isVisible
        self.onSettings = onSettings
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
        menu.delegate = self
        toggleMenuItem.target = self
        toggleMenuItem.setShortcut(for: .toggleFloatTabs)
        menu.addItem(toggleMenuItem)
        menu.addItem(.separator())

        settingsMenuItem.setShortcut(for: .floatTabsSettings)
        settingsMenuItem.target = self
        menu.addItem(settingsMenuItem)
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
            requestToggleFromStatusItem()
            return
        }

        let shouldOpenMenu = event.type == .rightMouseUp
            || event.modifierFlags.contains(.control)

        if shouldOpenMenu {
            presentMenu(from: sender)
        } else {
            requestToggleFromStatusItem()
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
        requestToggleFromStatusItem()
    }

    /// Showing from the status item has two phases. The normal show path runs
    /// synchronously inside the user's action and already performs FloatTabs'
    /// activation request. Capture that presentation generation, then defer only
    /// the state verification/key-window repair until status tracking unwinds.
    private func requestToggleFromStatusItem() {
        let shouldShow = !isVisible()
        onToggle()

        guard shouldShow else { return }
        let activationGeneration = onCaptureForegroundGeneration()
        Self.scheduleAfterStatusItemTracking { [weak self] in
            self?.onReassertForeground(activationGeneration)
        }
    }

    static func scheduleAfterStatusItemTracking(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) {
        DispatchQueue.main.async {
            DispatchQueue.main.async(execute: action)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        // The menu item owns this key equivalent while tracking. Disable the
        // global listener temporarily so the same key-up cannot toggle twice.
        KeyboardShortcuts.disable(.toggleFloatTabs)
    }

    func menuDidClose(_ menu: NSMenu) {
        KeyboardShortcuts.enable(.toggleFloatTabs)
    }

    @objc private func openSettings() {
        onSettings()
    }

    @objc private func quit() {
        onQuit()
    }
}
