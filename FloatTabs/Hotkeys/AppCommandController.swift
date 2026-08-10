import AppKit

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
    case settings
    case togglePin
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

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return event }

            if let overlay = Self.presentedAddressOverlay(in: event.window ?? NSApp.keyWindow),
               Self.shouldDismissAddressBar(for: event, overlay: overlay) {
                overlay.dismiss()
                overlay.onDismiss?()

                // Escape / Cmd+L are consumed. Outside mouse clicks continue to
                // the underlying website after dismissing the temporary overlay.
                return event.type == .keyDown ? nil : event
            }

            guard event.type == .keyDown,
                  let command = Self.command(for: event) else {
                return event
            }

            // Global Settings is application-level chrome. Allow Cmd+, while
            // FloatTabs is active even when the floating panel itself is hidden.
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
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    static func command(for event: NSEvent) -> AppCommand? {
        command(
            characters: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifiers: event.modifierFlags
        )
    }

    nonisolated static func command(
        characters: String?,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> AppCommand? {
        var flags = modifiers.intersection(.deviceIndependentFlagsMask)
        flags.subtract([.capsLock, .numericPad, .function])

        if flags == [.command], let characters, characters.count == 1 {
            switch characters.lowercased() {
            case "t":
                return .addWebApp
            case "l":
                return .addressBar
            case "r":
                return .reload
            case ",":
                return .settings
            case "-":
                return .zoomOut
            case "0":
                return .resetZoom
            case "=", "+":
                return .zoomIn
            default:
                if let value = Int(characters), (1...9).contains(value) {
                    return .selectSlot(value)
                }
            }
        }

        if flags == [.command, .shift], let characters {
            switch characters.lowercased() {
            case "h":
                return .returnHome
            case "p":
                return .togglePin
            default:
                break
            }
        }

        // The physical + key is Shift+= on common Mac keyboard layouts.
        if flags == [.command, .shift],
           let characters,
           characters == "+" || characters == "=" {
            return .zoomIn
        }

        // Hardware Tab key. Using keyCode avoids Shift+Tab character-shape
        // differences while still requiring exact app-local modifiers.
        if keyCode == 48 {
            if flags == [.control] {
                return .nextSlot
            }
            if flags == [.control, .shift] {
                return .previousSlot
            }
        }

        return nil
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
