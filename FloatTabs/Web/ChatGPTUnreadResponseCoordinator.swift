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

    /// Only a valid completion that was not actually visible to the user
    /// becomes persistent unread state. Starts and runtime resets are
    /// deliberately no-ops, including for a Slot that already has unread
    /// output. The validity and visibility facts come from the PanelController
    /// boundary so this coordinator remains independent of transient
    /// attention state.
    func handle(
        _ observation: ChatGPTAttentionObservation,
        for slotID: UUID,
        isValidGenerationCompletion: Bool,
        userVisible: Bool
    ) {
        guard observation == .generationFinished,
              isValidGenerationCompletion,
              !userVisible else {
            return
        }

        markUnread(slotID: slotID)
    }
}
