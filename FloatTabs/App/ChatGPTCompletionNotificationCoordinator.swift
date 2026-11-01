import Foundation
import UserNotifications

/// The privacy-bounded routing payload of a Phase 3 completion notification.
/// It carries only the payload schema version, the notification kind, and the
/// persistent Slot UUID — never prompt/response content, URLs, Browser Profile
/// identity, document tokens, or Runtime identity.
struct ChatGPTCompletionNotificationPayload: Equatable {
    static let currentVersion = 1
    static let kind = "chatgpt_completion"

    static let versionKey = "version"
    static let kindKey = "kind"
    static let slotIDKey = "slot_id"

    let version: Int
    let kind: String
    let slotID: UUID

    var userInfo: [AnyHashable: Any] {
        [
            Self.versionKey: Self.currentVersion,
            Self.kindKey: Self.kind,
            Self.slotIDKey: slotID.uuidString
        ]
    }

    /// Strict parse: an unknown version, unknown kind, or malformed Slot UUID
    /// is not a FloatTabs completion notification and must never route.
    static func parse(userInfo: [AnyHashable: Any]) -> ChatGPTCompletionNotificationPayload? {
        guard let rawSlotID = userInfo[Self.slotIDKey] as? String,
              let slotID = UUID(uuidString: rawSlotID),
              let version = userInfo[Self.versionKey] as? Int,
              version == Self.currentVersion,
              let kind = userInfo[Self.kindKey] as? String,
              kind == Self.kind else {
            return nil
        }
        return Self(version: version, kind: kind, slotID: slotID)
    }
}

/// One generic local-notification projection request. Content is fixed and
/// generic; the only routing metadata is the bounded payload.
struct ChatGPTCompletionNotificationRequest: Equatable {
    let identifier: String
    let title: String
    let body: String
    let payload: ChatGPTCompletionNotificationPayload
}

/// The one seam between FloatTabs and the system notification center.
///
/// Only the system implementation below may touch `UNUserNotificationCenter`;
/// the coordinator routes every system operation through the injected backend
/// so tests can use a recording/fake backend instead of real system delivery.
@MainActor
protocol ChatGPTCompletionNotificationBackend: AnyObject {
    /// Contextually requests `.alert` authorization. Returns true only when
    /// alert notifications may actually be presented.
    @discardableResult
    func requestAlertAuthorization() async -> Bool

    /// Adds the notification request to the system center. Returns false on
    /// any delivery error; callers treat that as a projection failure only.
    @discardableResult
    func deliver(_ request: ChatGPTCompletionNotificationRequest) async -> Bool

    /// Explicitly withdraws prior delivered/pending system notification state
    /// for one identifier before a same-Slot replacement is delivered.
    func withdraw(identifier: String) async

    /// Installs the notification-center delegate during application startup.
    func installDelegate(_ delegate: UNUserNotificationCenterDelegate)
}

/// The production backend: the only FloatTabs code that directly accesses
/// `UNUserNotificationCenter.current()`. Failures fail closed as notification
/// projection failures and never propagate product-state side effects.
@MainActor
final class SystemChatGPTCompletionNotificationBackend: ChatGPTCompletionNotificationBackend {
    private let center = UNUserNotificationCenter.current()

    func requestAlertAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert])
        } catch {
            return false
        }
    }

    func deliver(_ request: ChatGPTCompletionNotificationRequest) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.userInfo = request.payload.userInfo
        let systemRequest = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(systemRequest)
            return true
        } catch {
            return false
        }
    }

    func withdraw(identifier: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func installDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        center.delegate = delegate
    }
}

/// App-layer projection owner for native ChatGPT completion notifications.
///
/// It only projects a durable unread `.marked` completion as a generic native
/// alert and routes a default-action tap back to the exact persistent Slot.
/// It is not unread truth, completion truth, Runtime truth, or Browser Profile
/// truth, and it never creates a WebView or clears unread itself.
@MainActor
final class ChatGPTCompletionNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let notificationIdentifierPrefix = "floattabs.chatgpt-completion."
    static let notificationTitle = "FloatTabs"
    static let notificationBody = "A ChatGPT response is ready."

    /// Routes the exact persistent Slot UUID activated through a completion
    /// notification's default action. Dismissal and unrecognized payloads
    /// never reach this callback.
    var onRouteSlot: ((UUID) -> Void)?

    private let backend: ChatGPTCompletionNotificationBackend
    private let diagnostics: any RuntimeDiagnosticRecording

    init(
        backend: ChatGPTCompletionNotificationBackend = SystemChatGPTCompletionNotificationBackend(),
        diagnostics: any RuntimeDiagnosticRecording = RuntimeDiagnosticNoopRecorder()
    ) {
        self.backend = backend
        self.diagnostics = diagnostics
        super.init()
    }

    /// Installs the notification-center delegate during normal application
    /// startup, before any completion notification can be delivered.
    func installAtStartup() {
        backend.installDelegate(self)
    }

    /// One deterministic notification request identifier per Slot, so a newer
    /// completion replaces prior same-Slot notification state explicitly.
    static func notificationIdentifier(for slotID: UUID) -> String {
        notificationIdentifierPrefix + slotID.uuidString
    }

    /// Production entry point: one call per durable unread `.marked`
    /// completion handoff. Authorization is requested contextually here —
    /// never at app launch.
    func notify(slotID: UUID) {
        Task { @MainActor [weak self] in
            await self?.performNotify(slotID: slotID)
        }
    }

    func performNotify(slotID: UUID) async {
        diagnostics.record(
            event: "notification.requested",
            level: .info,
            subsystem: "notification",
            fields: ["slot_id": .string(slotID.uuidString)]
        )
        guard await backend.requestAlertAuthorization() else {
            // Denied/error/unavailable authorization is a projection failure
            // only: unread, sound, generation, Runtime and user data continue
            // unchanged.
            diagnostics.record(
                event: "notification.skipped",
                level: .warning,
                subsystem: "notification",
                fields: [
                    "slot_id": .string(slotID.uuidString),
                    "reason": .string("authorization_unavailable")
                ]
            )
            return
        }

        let identifier = Self.notificationIdentifier(for: slotID)
        await backend.withdraw(identifier: identifier)
        let request = ChatGPTCompletionNotificationRequest(
            identifier: identifier,
            title: Self.notificationTitle,
            body: Self.notificationBody,
            payload: ChatGPTCompletionNotificationPayload(
                version: ChatGPTCompletionNotificationPayload.currentVersion,
                kind: ChatGPTCompletionNotificationPayload.kind,
                slotID: slotID
            )
        )
        if await backend.deliver(request) {
            diagnostics.record(
                event: "notification.delivered",
                level: .notice,
                subsystem: "notification",
                fields: ["slot_id": .string(slotID.uuidString)]
            )
        } else {
            diagnostics.record(
                event: "notification.skipped",
                level: .warning,
                subsystem: "notification",
                fields: [
                    "slot_id": .string(slotID.uuidString),
                    "reason": .string("delivery_failed")
                ]
            )
        }
    }

    /// Default-action routing decision. Only the exact default action with a
    /// strictly parseable FloatTabs completion payload routes a Slot UUID;
    /// dismissal, malformed payloads, unknown kinds and unknown versions are
    /// ignored safely.
    func handleNotificationResponse(
        actionIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) {
        guard actionIdentifier == UNNotificationDefaultActionIdentifier,
              let payload = ChatGPTCompletionNotificationPayload.parse(userInfo: userInfo) else {
            return
        }
        onRouteSlot?(payload.slotID)
    }

    /// Foreground presentation decision. A recognized FloatTabs completion
    /// notification presents as banner/list without a notification sound;
    /// unknown notifications are not presented as Phase 3 completions.
    func foregroundPresentationOptions(
        userInfo: [AnyHashable: Any]
    ) -> UNNotificationPresentationOptions {
        ChatGPTCompletionNotificationPayload.parse(userInfo: userInfo) != nil
            ? [.banner, .list]
            : []
    }

    // MARK: - UNUserNotificationCenterDelegate
    //
    // The system calls these off the main actor; each hops to the
    // coordinator's isolated state and then completes the system handshake.

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        Task { @MainActor [weak self] in
            completionHandler(
                self?.foregroundPresentationOptions(userInfo: userInfo) ?? []
            )
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let actionIdentifier = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor [weak self] in
            self?.handleNotificationResponse(
                actionIdentifier: actionIdentifier,
                userInfo: userInfo
            )
            completionHandler()
        }
    }
}
