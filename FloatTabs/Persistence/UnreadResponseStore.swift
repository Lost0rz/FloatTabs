import Foundation

/// Machine-local persistence for completed ChatGPT responses that the user has
/// not explicitly acknowledged. This is intentionally separate from the
/// runtime attention state and from the backup document schema.
@MainActor
final class UnreadResponseStore {
    static let slotIDsKey = "FloatTabs.chatGPTUnreadResponseSlotIDs"
    static let responseIdentityBySlotKey = "FloatTabs.chatGPTUnreadResponseIdentityBySlotV1"

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

    var unreadResponseIdentityBySlot: [UUID: ChatGPTResponseIdentity] {
        guard let values = defaults.dictionary(forKey: Self.responseIdentityBySlotKey) else {
            return [:]
        }
        return values.reduce(into: [:]) { result, entry in
            guard let slotID = UUID(uuidString: entry.key),
                  let rawIdentity = entry.value as? String,
                  let identity = ChatGPTResponseIdentity(rawValue: rawIdentity) else {
                return
            }
            result[slotID] = identity
        }
    }

    func markUnread(
        _ slotID: UUID,
        responseIdentity: ChatGPTResponseIdentity? = nil
    ) {
        var slotIDs = unreadSlotIDs
        slotIDs.insert(slotID)
        var identities = unreadResponseIdentityBySlot
        if let responseIdentity {
            identities[slotID] = responseIdentity
        } else {
            identities.removeValue(forKey: slotID)
        }
        persist(slotIDs, identities: identities)
    }

    func acknowledge(_ slotID: UUID) {
        var slotIDs = unreadSlotIDs
        let removed = slotIDs.remove(slotID) != nil
        var identities = unreadResponseIdentityBySlot
        let removedIdentity = identities.removeValue(forKey: slotID) != nil
        guard removed || removedIdentity else { return }
        persist(slotIDs, identities: identities)
    }

    func removeSlot(_ slotID: UUID) {
        acknowledge(slotID)
    }

    func prune(validSlotIDs: Set<UUID>) {
        let existing = unreadSlotIDs
        let pruned = existing.intersection(validSlotIDs)
        var identities = unreadResponseIdentityBySlot
        identities = identities.filter { validSlotIDs.contains($0.key) && pruned.contains($0.key) }
        guard pruned != existing || identities != unreadResponseIdentityBySlot else { return }
        persist(pruned, identities: identities)
    }

    private func persist(
        _ slotIDs: Set<UUID>,
        identities: [UUID: ChatGPTResponseIdentity]
    ) {
        defaults.set(
            slotIDs.map(\.uuidString).sorted(),
            forKey: Self.slotIDsKey
        )
        defaults.set(
            Dictionary(uniqueKeysWithValues: identities.map { ($0.key.uuidString, $0.value.rawValue) }),
            forKey: Self.responseIdentityBySlotKey
        )
    }
}
