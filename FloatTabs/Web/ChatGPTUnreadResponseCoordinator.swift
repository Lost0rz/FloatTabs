import Foundation

enum ChatGPTUnreadCompletionResult: Equatable {
    case ignored
    case marked(identityAvailable: Bool)
    case alreadyHandled
}

enum ChatGPTUnreadAcknowledgementResult: Equatable {
    case cleared(responseIdentity: ChatGPTResponseIdentity?)
    case preservedIdentityMismatch
    case noUnread
}

enum ChatGPTUnreadSnapshotReconciliationResult: Equatable {
    case cleared
    case preservedIdentityMismatch
    case preservedLegacyIdentity
    case noUnread
}

/// The independent authority for persistent unread ChatGPT response badges.
/// It consumes normalized bridge events but never reads or mutates the
/// transient WebAttentionCoordinator.
@MainActor
final class ChatGPTUnreadResponseCoordinator {
    private static let handledHistoryLimit = 16

    let coordinatorInstanceID: UUID
    private let store: UnreadResponseStore
    private let diagnostics: any RuntimeDiagnosticRecording
    private let diagnosticContext: UnreadRuntimeDiagnosticContext
    private(set) var unreadSlotIDs: Set<UUID>
    private var handledResponseIdentities: [UUID: [ChatGPTResponseIdentity]] = [:]

    init(
        store: UnreadResponseStore = UnreadResponseStore(),
        diagnostics: any RuntimeDiagnosticRecording = RuntimeDiagnosticNoopRecorder(),
        coordinatorInstanceID: UUID = UUID(),
        diagnosticContext: UnreadRuntimeDiagnosticContext = .shared
    ) {
        self.coordinatorInstanceID = coordinatorInstanceID
        self.store = store
        self.diagnostics = diagnostics
        self.diagnosticContext = diagnosticContext
        unreadSlotIDs = store.unreadSlotIDs
        diagnostics.record(
            event: "unread.coordinator.created",
            level: .info,
            subsystem: "unread",
            fields: diagnosticContext.fields([
                "coordinator_instance_id": .string(coordinatorInstanceID.uuidString),
                "unread_count": .integer(Int64(unreadSlotIDs.count))
            ])
        )
    }

    var unreadResponseIdentityBySlot: [UUID: ChatGPTResponseIdentity] {
        store.unreadResponseIdentityBySlot
    }

    func unreadResponseIdentity(for slotID: UUID) -> ChatGPTResponseIdentity? {
        store.unreadResponseIdentityBySlot[slotID]
    }

    func markUnread(
        slotID: UUID,
        responseIdentity: ChatGPTResponseIdentity? = nil
    ) {
        store.markUnread(slotID, responseIdentity: responseIdentity)
        unreadSlotIDs = store.unreadSlotIDs
    }

    func recordHandled(
        slotID: UUID,
        responseIdentity: ChatGPTResponseIdentity
    ) {
        var history = handledResponseIdentities[slotID, default: []]
        history.removeAll { $0 == responseIdentity }
        history.append(responseIdentity)
        if history.count > Self.handledHistoryLimit {
            history.removeFirst(history.count - Self.handledHistoryLimit)
        }
        handledResponseIdentities[slotID] = history
    }

    func isHandled(
        slotID: UUID,
        responseIdentity: ChatGPTResponseIdentity
    ) -> Bool {
        handledResponseIdentities[slotID]?.contains(responseIdentity) == true
    }

    func diagnosticHandledLookup(
        slotID: UUID,
        responseIdentity: ChatGPTResponseIdentity?
    ) -> UnreadRuntimeDiagnosticHandledLookup {
        guard let responseIdentity else { return .unavailable }
        return isHandled(slotID: slotID, responseIdentity: responseIdentity)
            ? .hit
            : .miss
    }

    func acknowledge(slotID: UUID) {
        if let responseIdentity = unreadResponseIdentity(for: slotID) {
            recordHandled(slotID: slotID, responseIdentity: responseIdentity)
        }
        store.acknowledge(slotID)
        unreadSlotIDs = store.unreadSlotIDs
    }

    @discardableResult
    func acknowledge(
        slotID: UUID,
        responseIdentity: ChatGPTResponseIdentity?
    ) -> ChatGPTUnreadAcknowledgementResult {
        guard unreadSlotIDs.contains(slotID) else { return .noUnread }
        let currentIdentity = unreadResponseIdentity(for: slotID)
        if let currentIdentity,
           currentIdentity != responseIdentity {
            return .preservedIdentityMismatch
        }
        acknowledge(slotID: slotID)
        return .cleared(responseIdentity: currentIdentity)
    }

    /// Records a completed response as handled, then clears only an unread
    /// sidecar owned by that exact response. A newer response or legacy
    /// identity-unknown unread marker is never cleared by this reconciliation.
    @discardableResult
    func reconcileHandledSnapshot(
        slotID: UUID,
        responseIdentity: ChatGPTResponseIdentity
    ) -> ChatGPTUnreadSnapshotReconciliationResult {
        recordHandled(slotID: slotID, responseIdentity: responseIdentity)

        guard unreadSlotIDs.contains(slotID) else { return .noUnread }
        guard let currentIdentity = unreadResponseIdentity(for: slotID) else {
            return .preservedLegacyIdentity
        }
        guard currentIdentity == responseIdentity else {
            return .preservedIdentityMismatch
        }

        _ = acknowledge(slotID: slotID, responseIdentity: responseIdentity)
        return .cleared
    }

    func removeSlot(slotID: UUID) {
        handledResponseIdentities.removeValue(forKey: slotID)
        store.removeSlot(slotID)
        unreadSlotIDs = store.unreadSlotIDs
    }

    func prune(validSlotIDs: Set<UUID>) {
        handledResponseIdentities = handledResponseIdentities.filter {
            validSlotIDs.contains($0.key)
        }
        store.prune(validSlotIDs: validSlotIDs)
        unreadSlotIDs = store.unreadSlotIDs
    }

    /// Only a valid completion that was not actually visible to the user
    /// becomes persistent unread state. A stable identity suppresses a late
    /// completion after the user has already processed that exact response.
    // `userVisible` is retained for compatibility and diagnostics callers; a
    // presentation fact alone is never an unread acknowledgement.
    @discardableResult
    func handle(
        _ event: ChatGPTAttentionEvent,
        for slotID: UUID,
        isValidGenerationCompletion: Bool,
        userVisible _: Bool
    ) -> ChatGPTUnreadCompletionResult {
        guard event.observation == .generationFinished,
              isValidGenerationCompletion else {
            return .ignored
        }

        if let responseIdentity = event.responseIdentity {
            if isHandled(slotID: slotID, responseIdentity: responseIdentity) {
                return .alreadyHandled
            }
            markUnread(slotID: slotID, responseIdentity: responseIdentity)
            return .marked(identityAvailable: true)
        }

        markUnread(slotID: slotID)
        return .marked(identityAvailable: false)
    }

    /// Compatibility entry point for callers/tests that still provide the
    /// pre-U3 observation-only envelope.
    @discardableResult
    func handle(
        _ observation: ChatGPTAttentionObservation,
        for slotID: UUID,
        isValidGenerationCompletion: Bool,
        userVisible: Bool
    ) -> ChatGPTUnreadCompletionResult {
        handle(
            ChatGPTAttentionEvent(observation: observation, responseIdentity: nil),
            for: slotID,
            isValidGenerationCompletion: isValidGenerationCompletion,
            userVisible: userVisible
        )
    }
}
