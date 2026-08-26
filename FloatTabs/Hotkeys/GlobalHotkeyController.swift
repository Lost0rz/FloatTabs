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
    private let isPrimaryFocusEnabled: () -> Bool
    private let onPrimaryFocus: () -> Void

    init(
        onToggle: @escaping () -> Void,
        isPrimaryFocusEnabled: @escaping () -> Bool = { false },
        onPrimaryFocus: @escaping () -> Void = {}
    ) {
        self.onToggle = onToggle
        self.isPrimaryFocusEnabled = isPrimaryFocusEnabled
        self.onPrimaryFocus = onPrimaryFocus
        KeyboardShortcuts.onKeyUp(for: .toggleFloatTabs) { [weak self] in
            self?.onToggle()
        }
        KeyboardShortcuts.onKeyUp(for: .togglePrimaryFocus) { [weak self] in
            guard let self, self.isPrimaryFocusEnabled() else { return }
            self.onPrimaryFocus()
        }
    }
}
