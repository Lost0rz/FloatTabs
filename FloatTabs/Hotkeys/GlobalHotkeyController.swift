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
    private let diagnostics: any RuntimeDiagnosticRecording
    private let onToggleWithTrace: ((RuntimeDiagnosticTrace) -> Void)?
    private let onPrimaryFocusWithTrace: ((RuntimeDiagnosticTrace) -> Void)?

    init(
        onToggle: @escaping () -> Void,
        isPrimaryFocusEnabled: @escaping () -> Bool = { false },
        onPrimaryFocus: @escaping () -> Void = {},
        diagnostics: any RuntimeDiagnosticRecording = RuntimeDiagnosticNoopRecorder(),
        onToggleWithTrace: ((RuntimeDiagnosticTrace) -> Void)? = nil,
        onPrimaryFocusWithTrace: ((RuntimeDiagnosticTrace) -> Void)? = nil
    ) {
        self.onToggle = onToggle
        self.isPrimaryFocusEnabled = isPrimaryFocusEnabled
        self.onPrimaryFocus = onPrimaryFocus
        self.diagnostics = diagnostics
        self.onToggleWithTrace = onToggleWithTrace
        self.onPrimaryFocusWithTrace = onPrimaryFocusWithTrace
        KeyboardShortcuts.onKeyUp(for: .toggleFloatTabs) { [weak self] in
            self?.handleToggleShortcut()
        }
        KeyboardShortcuts.onKeyUp(for: .togglePrimaryFocus) { [weak self] in
            self?.handlePrimaryFocusShortcut()
        }
    }

    private func handleToggleShortcut() {
        let trace = diagnostics.beginTrace(root: "hotkey.toggle")
        diagnostics.record(
            event: "hotkey.toggle.received",
            level: .info,
            subsystem: "hotkey",
            trace: trace
        )
        if let onToggleWithTrace {
            onToggleWithTrace(trace)
        } else {
            onToggle()
        }
    }

    private func handlePrimaryFocusShortcut() {
        guard isPrimaryFocusEnabled() else { return }
        let trace = diagnostics.beginTrace(root: "hotkey.primary-focus")
        diagnostics.record(
            event: "hotkey.primary_focus.received",
            level: .info,
            subsystem: "hotkey",
            trace: trace
        )
        if let onPrimaryFocusWithTrace {
            onPrimaryFocusWithTrace(trace)
        } else {
            onPrimaryFocus()
        }
    }
}
