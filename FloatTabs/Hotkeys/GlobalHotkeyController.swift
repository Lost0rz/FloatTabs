import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleFloatTabs = Self(
        "toggleFloatTabs",
        initial: .init(.f, modifiers: [.control, .option, .command])
    )
}

@MainActor
final class GlobalHotkeyController {
    private let onToggle: () -> Void

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle

        KeyboardShortcuts.onKeyUp(for: .toggleFloatTabs) { [weak self] in
            Task { @MainActor [weak self] in
                self?.onToggle()
            }
        }
    }
}
