import AppKit

enum AppCommand: Equatable {
    case selectSlot(Int)
    case nextSlot
    case previousSlot
    case addWebApp
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

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
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
            if characters == "t" || characters == "T" {
                return .addWebApp
            }

            if let value = Int(characters), (1...9).contains(value) {
                return .selectSlot(value)
            }
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
}
