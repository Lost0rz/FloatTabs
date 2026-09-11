import Foundation

/// Machine-local persistence for completed ChatGPT responses that the user has
/// not explicitly acknowledged. This is intentionally separate from the
/// runtime attention state and from the backup document schema.
@MainActor
final class UnreadResponseStore {
    static let slotIDsKey = "FloatTabs.chatGPTUnreadResponseSlotIDs"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Invalid or legacy values are treated as an empty set. UUID parsing is
    /// deliberately best-effort so one malformed entry cannot hide valid
    /// unread markers.
    var unreadSlotIDs: Set<UUID> {
        guard let values = defaults.array(forKey: Self.slotIDsKey) else {
            return []
        }
        return Set(values.compactMap { value in
            guard let string = value as? String else { return nil }
            return UUID(uuidString: string)
        })
    }

    func markUnread(_ slotID: UUID) {
        var slotIDs = unreadSlotIDs
        guard slotIDs.insert(slotID).inserted else { return }
        persist(slotIDs)
    }

    func acknowledge(_ slotID: UUID) {
        var slotIDs = unreadSlotIDs
        guard slotIDs.remove(slotID) != nil else { return }
        persist(slotIDs)
    }

    func removeSlot(_ slotID: UUID) {
        acknowledge(slotID)
    }

    func prune(validSlotIDs: Set<UUID>) {
        let pruned = unreadSlotIDs.intersection(validSlotIDs)
        guard pruned != unreadSlotIDs else { return }
        persist(pruned)
    }

    private func persist(_ slotIDs: Set<UUID>) {
        defaults.set(
            slotIDs.map(\.uuidString).sorted(),
            forKey: Self.slotIDsKey
        )
    }
}
