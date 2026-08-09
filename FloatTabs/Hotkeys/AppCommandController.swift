import AppKit

enum AppCommand: Equatable {
    case selectSlot(Int)
    case nextSlot
    case previousSlot
    case addWebApp
    case zoomIn
    case zoomOut
    case resetZoom
    case quickURL
    case returnHome
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

            if let overlay = Self.presentedQuickURLOverlay(in: event.window ?? NSApp.keyWindow),
               Self.shouldDismissQuickURL(for: event, overlay: overlay) {
                overlay.dismiss()
                overlay.onDismiss?()

                // Escape / Cmd+L are consumed. Outside mouse clicks continue to
                // the underlying website after dismissing the temporary overlay.
                return event.type == .keyDown ? nil : event
            }

            guard event.type == .keyDown,
                  self.isEnabled(),
                  let command = Self.command(for: event) else {
                return event
            }

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
                return .quickURL
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

        if flags == [.command, .shift],
           let characters,
           characters.lowercased() == "h" {
            return .returnHome
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

    static func presentedQuickURLOverlay(in window: NSWindow?) -> QuickURLOverlayView? {
        guard let contentView = window?.contentView else { return nil }
        return firstPresentedQuickURLOverlay(in: contentView)
    }

    static func shouldDismissQuickURL(
        for event: NSEvent,
        overlay: QuickURLOverlayView
    ) -> Bool {
        if event.type == .keyDown {
            if event.keyCode == 53 { // Escape
                return true
            }
            return command(for: event) == .quickURL
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

    private static func firstPresentedQuickURLOverlay(in view: NSView) -> QuickURLOverlayView? {
        if let overlay = view as? QuickURLOverlayView, overlay.isPresented {
            return overlay
        }

        for subview in view.subviews {
            if let found = firstPresentedQuickURLOverlay(in: subview) {
                return found
            }
        }
        return nil
    }
}
