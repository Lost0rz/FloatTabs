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

/// Bounded, normalized notification-settings facts used for preflight
/// decisions and diagnostics. These are public-API enum projections only —
/// never raw system objects, and never a Focus/DND claim.
struct ChatGPTNotificationSettingsFacts: Equatable, Sendable {
    static let authorized = "authorized"
    static let denied = "denied"
    static let notDetermined = "notDetermined"
    static let provisional = "provisional"
    static let ephemeral = "ephemeral"

    let authorizationStatus: String
    let alertSetting: String
    let alertStyle: String
    let notificationCenterSetting: String
    let showPreviewsSetting: String

    var maySubmit: Bool {
        switch authorizationStatus {
        case Self.authorized, Self.provisional, Self.ephemeral:
            return true
        default:
            return false
        }
    }
}

/// The one seam between FloatTabs and the system notification center.
///
/// Only the system implementation below may touch `UNUserNotificationCenter`;
/// the coordinator routes every system operation through the injected backend
/// so tests can use a recording/fake backend instead of real system delivery.
@MainActor
protocol ChatGPTCompletionNotificationBackend: AnyObject {
    /// Reads the current normalized notification settings facts.
    func notificationSettings() async -> ChatGPTNotificationSettingsFacts

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

    func notificationSettings() async -> ChatGPTNotificationSettingsFacts {
        let settings = await center.notificationSettings()
        return Self.facts(from: settings)
    }

    static func facts(from settings: UNNotificationSettings) -> ChatGPTNotificationSettingsFacts {
        let authorization: String
        switch settings.authorizationStatus {
        case .authorized: authorization = ChatGPTNotificationSettingsFacts.authorized
        case .denied: authorization = ChatGPTNotificationSettingsFacts.denied
        case .notDetermined: authorization = ChatGPTNotificationSettingsFacts.notDetermined
        case .provisional: authorization = ChatGPTNotificationSettingsFacts.provisional
        case .ephemeral: authorization = ChatGPTNotificationSettingsFacts.ephemeral
        @unknown default: authorization = "unknown"
        }
        let alertSetting = Self.settingName(settings.alertSetting)
        let alertStyle: String
        switch settings.alertStyle {
        case .none: alertStyle = "none"
        case .banner: alertStyle = "banner"
        case .alert: alertStyle = "alert"
        @unknown default: alertStyle = "unknown"
        }
        return ChatGPTNotificationSettingsFacts(
            authorizationStatus: authorization,
            alertSetting: alertSetting,
            alertStyle: alertStyle,
            notificationCenterSetting: Self.settingName(settings.notificationCenterSetting),
            showPreviewsSetting: Self.showPreviewsSettingName(settings.showPreviewsSetting)
        )
    }

    private static func settingName(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .notSupported: return "notSupported"
        case .disabled: return "disabled"
        case .enabled: return "enabled"
        @unknown default: return "unknown"
        }
    }

    private static func showPreviewsSettingName(_ setting: UNShowPreviewsSetting) -> String {
        switch setting {
        case .always: return "always"
        case .whenAuthenticated: return "whenAuthenticated"
        case .never: return "never"
        @unknown default: return "unknown"
        }
    }

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
    static let notificationTitleFallback = "ChatGPT"
    static let notificationBodyFallback = "A ChatGPT response is ready."
    static let titleCharacterLimit = 80
    static let bodyCharacterLimit = 240

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
    /// completion handoff. `displayName` and `assistantPreview` are ephemeral
    /// projection input only — they are never persisted or logged. Missing or
    /// untrusted input falls back to bounded generic content.
    func notify(
        slotID: UUID,
        displayName: String?,
        assistantPreview: String?
    ) {
        Task { @MainActor [weak self] in
            await self?.performNotify(
                slotID: slotID,
                displayName: displayName,
                assistantPreview: assistantPreview
            )
        }
    }

    func performNotify(
        slotID: UUID,
        displayName: String?,
        assistantPreview: String?
    ) async {
        diagnostics.record(
            event: "notification.requested",
            level: .info,
            subsystem: "notification",
            fields: [
                "slot_id": .string(slotID.uuidString),
                "has_preview": .bool(assistantPreview != nil)
            ]
        )

        var settings = await backend.notificationSettings()
        if settings.authorizationStatus == ChatGPTNotificationSettingsFacts.notDetermined {
            // Contextual authorization request — never at launch, and never
            // repeated for already-authorized completions.
            await backend.requestAlertAuthorization()
            settings = await backend.notificationSettings()
        }

        guard settings.maySubmit else {
            // Denied/error/unavailable authorization is a projection failure
            // only: unread, sound, generation, Runtime and user data continue
            // unchanged.
            diagnostics.record(
                event: "notification.skipped",
                level: .warning,
                subsystem: "notification",
                fields: [
                    "slot_id": .string(slotID.uuidString),
                    "reason": .string("authorization_unavailable"),
                    "permission_status": .string(settings.authorizationStatus)
                ]
            )
            return
        }

        diagnostics.record(
            event: "notification.settings",
            level: .info,
            subsystem: "notification",
            fields: [
                "slot_id": .string(slotID.uuidString),
                "permission_status": .string(settings.authorizationStatus),
                "alert_setting": .string(settings.alertSetting),
                "alert_style": .string(settings.alertStyle),
                "notification_center_setting": .string(settings.notificationCenterSetting),
                "show_previews_setting": .string(settings.showPreviewsSetting)
            ]
        )

        let identifier = Self.notificationIdentifier(for: slotID)
        await backend.withdraw(identifier: identifier)
        let request = ChatGPTCompletionNotificationRequest(
            identifier: identifier,
            title: Self.normalizedTitle(displayName),
            body: Self.normalizedBody(assistantPreview),
            payload: ChatGPTCompletionNotificationPayload(
                version: ChatGPTCompletionNotificationPayload.currentVersion,
                kind: ChatGPTCompletionNotificationPayload.kind,
                slotID: slotID
            )
        )
        if await backend.deliver(request) {
            // Submission success means the system accepted the request — it
            // does NOT prove a banner was visibly displayed. Alert style,
            // Notification Center policy, preview policy and Focus/system
            // policy can all affect what the user actually sees.
            diagnostics.record(
                event: "notification.submitted",
                level: .notice,
                subsystem: "notification",
                fields: [
                    "slot_id": .string(slotID.uuidString),
                    "alert_setting": .string(settings.alertSetting),
                    "alert_style": .string(settings.alertStyle),
                    "banner_expected": .bool(settings.alertSetting == "enabled")
                ]
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

    /// Normalized notification title: trimmed Slot/Web App display name,
    /// capped at 80 user-perceived characters, falling back to `ChatGPT`.
    /// The value is projection-only input and is never logged.
    static func normalizedTitle(_ displayName: String?) -> String {
        let normalized = normalizeUserPerceivedText(
            displayName,
            limit: titleCharacterLimit
        )
        return normalized ?? notificationTitleFallback
    }

    /// Normalized notification body: bounded plain-text assistant preview,
    /// capped at 240 user-perceived characters, falling back to the generic
    /// completion body. The value is projection-only input and is never
    /// logged.
    static func normalizedBody(_ assistantPreview: String?) -> String {
        normalizeUserPerceivedText(
            assistantPreview,
            limit: bodyCharacterLimit
        ) ?? notificationBodyFallback
    }

    private static func normalizeUserPerceivedText(
        _ value: String?,
        limit: Int
    ) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let collapsed = trimmed.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        guard !collapsed.isEmpty else { return nil }
        guard limit > 0 else { return nil }
        if collapsed.count <= limit {
            return collapsed
        }
        let prefix = String(collapsed.prefix(limit))
        return prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : prefix.trimmingCharacters(in: .whitespacesAndNewlines)
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
