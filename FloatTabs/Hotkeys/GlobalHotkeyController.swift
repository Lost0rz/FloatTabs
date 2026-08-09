import KeyboardShortcuts

@MainActor
final class GlobalHotkeyController {
    private static let summonShortcut = KeyboardShortcuts.Shortcut(
        .backtick,
        modifiers: [.command]
    )

    private let onToggle: () -> Void
    private var eventTask: Task<Void, Never>?

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle

        let shortcut = Self.summonShortcut
        eventTask = Task { [weak self] in
            for await eventType in KeyboardShortcuts.events(for: shortcut)
            where eventType == .keyUp {
                guard !Task.isCancelled else { return }
                self?.onToggle()
            }
        }
    }

    deinit {
        eventTask?.cancel()
    }
}
