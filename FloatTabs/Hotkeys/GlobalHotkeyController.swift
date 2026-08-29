import Foundation
import KeyboardShortcuts

/// Commands that can be sent by MiRemoteBridge without depending on the
/// currently configured keyboard shortcut. The notification is intentionally
/// local to the current macOS user session; FloatTabs remains a menu-bar app
/// and does not need to expose a network listener.
enum FloatTabsExternalCommand: String {
    case show = "show"
    case toggleVisibility = "toggleVisibility"
    case nextSlot = "nextSlot"
    case previousSlot = "previousSlot"
    case togglePrimaryFocus = "togglePrimaryFocus"
    case scrollUp = "scrollUp"
    case scrollDown = "scrollDown"
    case focusInputForVoice = "focusInputForVoice"
    case settings = "settings"

    static let notificationName = Notification.Name(
        "com.lost0rz.FloatTabs.external-command.v1"
    )
    static let focusReadyNotificationName = Notification.Name(
        "com.lost0rz.FloatTabs.focus-ready.v1"
    )
}

@MainActor
final class FloatTabsExternalCommandReceiver {
    private let onCommand: (FloatTabsExternalCommand, Int, String?) -> Void
    private var observer: NSObjectProtocol?

    init(onCommand: @escaping (FloatTabsExternalCommand, Int, String?) -> Void) {
        self.onCommand = onCommand
        observer = DistributedNotificationCenter.default().addObserver(
            forName: FloatTabsExternalCommand.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let rawValue = notification.userInfo?["command"] as? String,
                  let command = FloatTabsExternalCommand(rawValue: rawValue)
            else { return }
            let scrollLines = (notification.userInfo?["scrollLines"] as? NSNumber)?.intValue ?? 6
            let requestID = notification.userInfo?["requestID"] as? String
            self?.onCommand(command, min(max(scrollLines, 1), 40), requestID)
        }
    }

    deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }
}

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
