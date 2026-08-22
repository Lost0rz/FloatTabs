import AppKit
import KeyboardShortcuts

struct MenuShortcutPresentation: Equatable {
    let keyEquivalent: String
    let modifiers: NSEvent.ModifierFlags
}

enum StatusItemAttentionBadge: Equatable {
    case none
    case dot
    case count(String)
}

struct StatusItemAttentionPresentation: Equatable {
    let readyCount: Int
    let floatTabsVisible: Bool
    let badge: StatusItemAttentionBadge

    static func resolve(
        readyCount: Int,
        floatTabsVisible: Bool
    ) -> StatusItemAttentionPresentation {
        let normalizedCount = max(0, readyCount)
        let badge: StatusItemAttentionBadge

        if floatTabsVisible || normalizedCount == 0 {
            badge = .none
        } else if normalizedCount == 1 {
            badge = .dot
        } else if normalizedCount < 10 {
            badge = .count(String(normalizedCount))
        } else {
            badge = .count("9+")
        }

        return StatusItemAttentionPresentation(
            readyCount: normalizedCount,
            floatTabsVisible: floatTabsVisible,
            badge: badge
        )
    }
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
    private let onWillShow: () -> Void
    private let isVisible: () -> Bool
    private let onSettings: () -> Void
    private let onQuit: () -> Void
    private let preferencesStore: AppPreferencesStore
    private var selectedFaviconOriginKey: String?
    private var selectedFaviconImage: NSImage?
    private var latestActiveWebAppName: String?
    private(set) var attentionPresentation = StatusItemAttentionPresentation.resolve(
        readyCount: 0,
        floatTabsVisible: false
    )

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

#if DEBUG
    var debugStatusButtonTitle: String {
        statusItem.button?.title ?? ""
    }

    var debugStatusButtonImagePosition: NSControl.ImagePosition? {
        statusItem.button?.imagePosition
    }

    var debugStatusButtonImageTIFF: Data? {
        statusItem.button?.image?.tiffRepresentation
    }
#endif

    init(
        onToggle: @escaping () -> Void,
        onWillShow: @escaping () -> Void = {},
        isVisible: @escaping () -> Bool,
        onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        preferencesStore: AppPreferencesStore = AppPreferencesStore()
    ) {
        self.onToggle = onToggle
        self.onWillShow = onWillShow
        self.isVisible = isVisible
        self.onSettings = onSettings
        self.onQuit = onQuit
        self.preferencesStore = preferencesStore
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()
        configureStatusItem()
        configureMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuBarDisplayModeDidChange(_:)),
            name: .floatTabsMenuBarDisplayModeDidChange,
            object: preferencesStore
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(
            self,
            name: .floatTabsMenuBarDisplayModeDidChange,
            object: preferencesStore
        )
    }

    static func displayTitle(for activeWebAppName: String?) -> String {
        let value = activeWebAppName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "FloatTabs" : value
    }

    static func displayTitle(
        for activeWebAppName: String?,
        displayMode: MenuBarDisplayMode
    ) -> String {
        guard displayMode == .iconAndName else { return "" }
        return displayTitle(for: activeWebAppName)
    }

    static func imagePosition(for displayMode: MenuBarDisplayMode) -> NSControl.ImagePosition {
        displayMode == .iconOnly ? .imageOnly : .imageLeading
    }

    static func faviconOriginKey(for activeWebAppURL: URL?) -> String? {
        activeWebAppURL.flatMap(WebsiteFaviconProvider.originKey(for:))
    }

    static func acceptsFaviconCompletion(
        selectedOriginKey: String?,
        completionOriginKey: String
    ) -> Bool {
        selectedOriginKey == completionOriginKey
    }

    func setActiveWebApp(name: String?, homeURL: URL?) {
        latestActiveWebAppName = name
        if let button = statusItem.button {
            button.toolTip = name.map { "Current Web App · \($0)" } ?? "FloatTabs"
            applyMenuBarDisplayMode(to: button)
        }

        guard let homeURL,
              let originKey = Self.faviconOriginKey(for: homeURL) else {
            selectedFaviconOriginKey = nil
            selectedFaviconImage = nil
            redrawStatusImage()
            return
        }

        selectedFaviconOriginKey = originKey
        // Never leave the previous site's favicon visible while a newly selected
        // origin is loading. The shared provider normally returns immediately from
        // the same cache already populated by the tab rail.
        selectedFaviconImage = nil
        redrawStatusImage()
        WebsiteFaviconProvider.shared.load(for: homeURL) { [weak self] image in
            guard let self,
                  Self.acceptsFaviconCompletion(
                      selectedOriginKey: self.selectedFaviconOriginKey,
                      completionOriginKey: originKey
                  ) else { return }
            self.applyStatusImage(image)
        }
    }

    func setAttentionPresentation(readyCount: Int, floatTabsVisible: Bool) {
        attentionPresentation = Self.attentionPresentation(
            readyCount: readyCount,
            floatTabsVisible: floatTabsVisible
        )
        redrawStatusImage()
    }

    static func attentionPresentation(
        readyCount: Int,
        floatTabsVisible: Bool
    ) -> StatusItemAttentionPresentation {
        StatusItemAttentionPresentation.resolve(
            readyCount: readyCount,
            floatTabsVisible: floatTabsVisible
        )
    }

    static func renderStatusImage(
        favicon: NSImage?,
        attention: StatusItemAttentionPresentation
    ) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        if favicon == nil,
           attention.badge == .none,
           let fallback = fallbackImage() {
            // Keep the existing template fallback behavior when there is no
            // badge to composite. A badge requires an owned rasterized image
            // so its semantic red remains independent of menu-bar tinting.
            return fallback
        }

        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let sourceImage = (favicon ?? fallbackImage())?.copy() as? NSImage
        sourceImage?.size = size
        sourceImage?.isTemplate = false
        sourceImage?.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: false,
            hints: nil
        )

        drawAttentionBadge(attention.badge, in: NSRect(origin: .zero, size: size))
        image.isTemplate = false
        return image
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = Self.renderStatusImage(
            favicon: nil,
            attention: attentionPresentation
        )
        applyMenuBarDisplayMode(to: button)
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func applyStatusImage(_ favicon: NSImage?) {
        selectedFaviconImage = favicon
        redrawStatusImage()
    }

    private func redrawStatusImage() {
        statusItem.button?.image = Self.renderStatusImage(
            favicon: selectedFaviconImage,
            attention: attentionPresentation
        )
    }

    private func applyMenuBarDisplayMode(to button: NSStatusBarButton) {
        let mode = preferencesStore.menuBarDisplayMode
        button.title = Self.displayTitle(
            for: latestActiveWebAppName,
            displayMode: mode
        )
        button.imagePosition = Self.imagePosition(for: mode)
    }

    @objc private func menuBarDisplayModeDidChange(_ notification: Notification) {
        guard let button = statusItem.button else { return }
        applyMenuBarDisplayMode(to: button)
    }

    private static func fallbackImage() -> NSImage? {
        let image = NSImage(
            systemSymbolName: "rectangle.on.rectangle",
            accessibilityDescription: "FloatTabs"
        )
        image?.isTemplate = true
        return image
    }

    private static func drawAttentionBadge(
        _ badge: StatusItemAttentionBadge,
        in bounds: NSRect
    ) {
        guard badge != .none else { return }

        NSColor.systemRed.setFill()
        switch badge {
        case .none:
            break

        case .dot:
            let diameter: CGFloat = 5
            let dotRect = NSRect(
                x: bounds.maxX - diameter - 0.5,
                y: bounds.maxY - diameter - 0.5,
                width: diameter,
                height: diameter
            )
            NSBezierPath(ovalIn: dotRect).fill()

        case .count(let text):
            let font = NSFont.systemFont(ofSize: 7, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white,
            ]
            let textSize = (text as NSString).size(withAttributes: attributes)
            let width = max(9, textSize.width + 4)
            let height: CGFloat = 9
            let badgeRect = NSRect(
                x: bounds.maxX - width - 0.5,
                y: bounds.maxY - height - 0.5,
                width: width,
                height: height
            )
            NSBezierPath(
                roundedRect: badgeRect,
                xRadius: height / 2,
                yRadius: height / 2
            ).fill()

            let textRect = NSRect(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2 - 0.5,
                width: textSize.width,
                height: textSize.height
            )
            (text as NSString).draw(in: textRect, withAttributes: attributes)
        }
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
            requestToggleAfterStatusItemTracking()
            return
        }

        let shouldOpenMenu = event.type == .rightMouseUp
            || event.modifierFlags.contains(.control)

        if shouldOpenMenu {
            presentMenu(from: sender)
        } else {
            requestToggleAfterStatusItemTracking()
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
        requestToggleAfterStatusItemTracking()
    }

    /// Preserve the user's activation intent while the status action is still
    /// executing, but do not mutate the window group until AppKit has fully
    /// unwound status-button or menu tracking. `DispatchQueue.main.async` is not
    /// sufficient here because main-queue work can execute in event-tracking
    /// modes before AppKit performs its final window-order update.
    private func requestToggleAfterStatusItemTracking() {
        let shouldShow = !isVisible()
        if shouldShow {
            onWillShow()
        }

        Self.scheduleAfterStatusItemTracking { [weak self] in
            guard let self,
                  self.isVisible() != shouldShow else {
                return
            }
            self.onToggle()
        }
    }

    static func scheduleAfterStatusItemTracking(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) {
        RunLoop.main.perform(inModes: [.default]) {
            action()
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
