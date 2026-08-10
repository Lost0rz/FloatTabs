import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleFloatTabs = Self(
        "toggleFloatTabs",
        initial: .init(.backtick, modifiers: [.command])
    )
}

@MainActor
final class GlobalHotkeyController {
    private let onToggle: () -> Void

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        KeyboardShortcuts.onKeyUp(for: .toggleFloatTabs) { [weak self] in
            self?.onToggle()
        }
    }
}
