import AppKit
import KeyboardShortcuts

enum AppCommand: Equatable {
    case selectSlot(Int)
    case nextSlot
    case previousSlot
    case addWebApp
    case zoomIn
    case zoomOut
    case resetZoom
    case addressBar
    case returnHome
    case reload
    case togglePrimaryFocus
    case settings
    case togglePin
}

extension KeyboardShortcuts.Name {
    static let selectSlot1 = Self("selectSlot1", initial: .init(.one, modifiers: [.command]))
    static let selectSlot2 = Self("selectSlot2", initial: .init(.two, modifiers: [.command]))
    static let selectSlot3 = Self("selectSlot3", initial: .init(.three, modifiers: [.command]))
    static let selectSlot4 = Self("selectSlot4", initial: .init(.four, modifiers: [.command]))
    static let selectSlot5 = Self("selectSlot5", initial: .init(.five, modifiers: [.command]))
    static let selectSlot6 = Self("selectSlot6", initial: .init(.six, modifiers: [.command]))
    static let selectSlot7 = Self("selectSlot7", initial: .init(.seven, modifiers: [.command]))
    static let selectSlot8 = Self("selectSlot8", initial: .init(.eight, modifiers: [.command]))
    static let selectSlot9 = Self("selectSlot9", initial: .init(.nine, modifiers: [.command]))
    static let nextSlot = Self("nextSlot", initial: .init(.tab, modifiers: [.control]))
    static let previousSlot = Self("previousSlot", initial: .init(.tab, modifiers: [.control, .shift]))
    static let addWebApp = Self("addWebApp", initial: .init(.t, modifiers: [.command]))
    static let addressBar = Self("addressBar", initial: .init(.l, modifiers: [.command]))
    static let returnHome = Self("returnHome", initial: .init(.h, modifiers: [.command, .shift]))
    static let reload = Self("reload", initial: .init(.r, modifiers: [.command]))
    static let togglePrimaryFocus = Self(
        "togglePrimaryFocus",
        initial: .init(.f, modifiers: [.control, .option])
    )
    static let zoomIn = Self("zoomIn", initial: .init(.equal, modifiers: [.command, .shift]))
    static let zoomOut = Self("zoomOut", initial: .init(.minus, modifiers: [.command]))
    static let resetZoom = Self("resetZoom", initial: .init(.zero, modifiers: [.command]))
    static let togglePin = Self("togglePin", initial: .init(.p, modifiers: [.command, .shift]))
    static let floatTabsSettings = Self("floatTabsSettings", initial: .init(.comma, modifiers: [.command]))
}

struct AppShortcutBinding {
    let title: String
    let command: AppCommand
    let name: KeyboardShortcuts.Name
}

enum AppShortcutCatalog {
    static let slotBindings: [AppShortcutBinding] = [
        .init(title: "Select Slot 1", command: .selectSlot(1), name: .selectSlot1),
        .init(title: "Select Slot 2", command: .selectSlot(2), name: .selectSlot2),
        .init(title: "Select Slot 3", command: .selectSlot(3), name: .selectSlot3),
        .init(title: "Select Slot 4", command: .selectSlot(4), name: .selectSlot4),
        .init(title: "Select Slot 5", command: .selectSlot(5), name: .selectSlot5),
        .init(title: "Select Slot 6", command: .selectSlot(6), name: .selectSlot6),
        .init(title: "Select Slot 7", command: .selectSlot(7), name: .selectSlot7),
        .init(title: "Select Slot 8", command: .selectSlot(8), name: .selectSlot8),
        .init(title: "Select Slot 9", command: .selectSlot(9), name: .selectSlot9),
    ]

    static let navigationBindings: [AppShortcutBinding] = [
        .init(title: "Next Slot", command: .nextSlot, name: .nextSlot),
        .init(title: "Previous Slot", command: .previousSlot, name: .previousSlot),
        .init(title: "Add Web App", command: .addWebApp, name: .addWebApp),
        .init(title: "Address Bar", command: .addressBar, name: .addressBar),
        .init(title: "Return Home", command: .returnHome, name: .returnHome),
        .init(title: "Reload", command: .reload, name: .reload),
        .init(
            title: "Toggle Conversation / Web Focus",
            command: .togglePrimaryFocus,
            name: .togglePrimaryFocus
        ),
    ]

    static let viewBindings: [AppShortcutBinding] = [
        .init(title: "Zoom In", command: .zoomIn, name: .zoomIn),
        .init(title: "Zoom Out", command: .zoomOut, name: .zoomOut),
        .init(title: "Reset Zoom", command: .resetZoom, name: .resetZoom),
        .init(title: "Pin / Auto-hide", command: .togglePin, name: .togglePin),
    ]

    static let applicationBindings: [AppShortcutBinding] = [
        .init(title: "Global Settings", command: .settings, name: .floatTabsSettings),
    ]

    static var allBindings: [AppShortcutBinding] {
        slotBindings + navigationBindings + viewBindings + applicationBindings
    }

    static var allNames: [KeyboardShortcuts.Name] {
        allBindings.map(\.name)
    }

    @MainActor
    static func command(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> AppCommand? {
        command(
            keyCode: keyCode,
            modifiers: modifiers,
            shortcutFor: { KeyboardShortcuts.getShortcut(for: $0) }
        )
    }

    static func command(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        shortcutFor: (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut?
    ) -> AppCommand? {
        let normalizedEventModifiers = normalizedModifiers(modifiers)

        for binding in allBindings {
            guard let shortcut = shortcutFor(binding.name) else {
                continue
            }

            let configuredModifiers = normalizedModifiers(shortcut.modifiers)
            guard shortcut.carbonKeyCode == Int(keyCode) else { continue }

            if configuredModifiers == normalizedEventModifiers {
                return binding.command
            }

            // Keep both historical physical-key forms for the default Zoom In
            // binding: Cmd+= and Cmd+Shift+= (displayed as Cmd++). A custom
            // non-equals binding remains exact.
            if binding.command == .zoomIn,
               shortcut.key == .equal,
               isDefaultZoomModifierFamily(configuredModifiers),
               isDefaultZoomModifierFamily(normalizedEventModifiers) {
                return .zoomIn
            }
        }

        return nil
    }

    static func normalizedModifiers(
        _ modifiers: NSEvent.ModifierFlags
    ) -> NSEvent.ModifierFlags {
        var flags = modifiers.intersection(.deviceIndependentFlagsMask)
        flags.subtract([.capsLock, .numericPad, .function])
        return flags
    }

    private static func isDefaultZoomModifierFamily(
        _ modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        modifiers == [.command] || modifiers == [.command, .shift]
    }
}

@MainActor
final class AppCommandController {
    private var monitor: Any?
    private let isEnabled: () -> Bool
    private let onCommand: (AppCommand) -> Void

    init(
        isEnabled: @escaping () -> Bool,
        onCommand: @escaping (AppCommand) -> Void
    ) {
        self.isEnabled = isEnabled
        self.onCommand = onCommand

        // Touch the catalog at launch so every initial binding is materialized
        // before the first local key event arrives.
        _ = AppShortcutCatalog.allBindings

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }

            if let overlay = Self.presentedAddressOverlay(in: event.window ?? NSApp.keyWindow),
               Self.shouldDismissAddressBar(for: event, overlay: overlay) {
                overlay.dismiss()
                overlay.onDismiss?()

                // Escape / the configured Address Bar shortcut are consumed.
                // Outside mouse clicks continue to the underlying website after
                // dismissing the temporary overlay.
                return event.type == .keyDown ? nil : event
            }

            guard event.type == .keyDown,
                  let command = Self.command(for: event) else {
                return event
            }

            // Global Settings is application-level chrome. Allow its configured
            // app-local shortcut while FloatTabs is active even when the panel
            // itself is hidden.
            if command == .settings {
                self.onCommand(command)
                return nil
            }

            guard self.isEnabled() else { return event }
            self.onCommand(command)
            return nil
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    static func command(for event: NSEvent) -> AppCommand? {
        command(
            characters: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifiers: event.modifierFlags
        )
    }

    static func command(
        characters: String?,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> AppCommand? {
        _ = characters
        return AppShortcutCatalog.command(keyCode: keyCode, modifiers: modifiers)
    }

    static func presentedAddressOverlay(in window: NSWindow?) -> AddressOverlayView? {
        guard let contentView = window?.contentView else { return nil }
        return firstPresentedAddressOverlay(in: contentView)
    }

    static func shouldDismissAddressBar(
        for event: NSEvent,
        overlay: AddressOverlayView
    ) -> Bool {
        if event.type == .keyDown {
            if event.keyCode == 53 { // Escape
                return true
            }
            return command(for: event) == .addressBar
        }

        guard event.type == .leftMouseDown
                || event.type == .rightMouseDown
                || event.type == .otherMouseDown,
              let superview = overlay.superview else {
            return false
        }

        let point = superview.convert(event.locationInWindow, from: nil)
        return !overlay.frame.contains(point)
    }

    private static func firstPresentedAddressOverlay(in view: NSView) -> AddressOverlayView? {
        if let overlay = view as? AddressOverlayView, overlay.isPresented {
            return overlay
        }

        for subview in view.subviews {
            if let found = firstPresentedAddressOverlay(in: subview) {
                return found
            }
        }
        return nil
    }
}
