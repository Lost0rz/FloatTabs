import Foundation

/// The independent authority for persistent unread ChatGPT response badges.
/// It consumes normalized bridge observations but never reads or mutates the
/// transient WebAttentionCoordinator.
@MainActor
final class ChatGPTUnreadResponseCoordinator {
    private let store: UnreadResponseStore
    private(set) var unreadSlotIDs: Set<UUID>

    init(store: UnreadResponseStore = UnreadResponseStore()) {
        self.store = store
        unreadSlotIDs = store.unreadSlotIDs
    }

    func markUnread(slotID: UUID) {
        store.markUnread(slotID)
        unreadSlotIDs = store.unreadSlotIDs
    }

    func acknowledge(slotID: UUID) {
        store.acknowledge(slotID)
        unreadSlotIDs = store.unreadSlotIDs
    }

    func removeSlot(slotID: UUID) {
        store.removeSlot(slotID)
        unreadSlotIDs = store.unreadSlotIDs
    }

    func prune(validSlotIDs: Set<UUID>) {
        store.prune(validSlotIDs: validSlotIDs)
        unreadSlotIDs = store.unreadSlotIDs
    }

    /// A completed generation is unread regardless of where the user was and
    /// whether the panel happened to be visible. Starts and runtime resets are
    /// deliberately no-ops, including for a Slot that already has unread
    /// output.
    func handle(
        _ observation: ChatGPTAttentionObservation,
        for slotID: UUID
    ) {
        switch observation {
        case .generationFinished:
            markUnread(slotID: slotID)
        case .generationStarted, .runtimeReset:
            break
        }
    }
}
