import Foundation

struct SpeechResponseIdentity: Hashable, Equatable, Sendable {
    let slotID: UUID
    let documentToken: String
    let responseID: String
}

enum SpeechPlaybackOrigin: Equatable, Sendable {
    case automatic
    case manual
    case preview
}

struct SpeechQueueItem: Equatable, Sendable {
    let responseID: SpeechResponseIdentity?
    let sequence: UInt64
    let text: String
    let languageRole: SpeechLanguageRole
    let origin: SpeechPlaybackOrigin
    let sourceLocator: SpeechSourceLocator?

    init(
        responseID: SpeechResponseIdentity?,
        sequence: UInt64,
        text: String,
        languageRole: SpeechLanguageRole = .automatic,
        origin: SpeechPlaybackOrigin = .automatic,
        sourceLocator: SpeechSourceLocator? = nil
    ) {
        self.responseID = responseID
        self.sequence = sequence
        self.text = text
        self.languageRole = languageRole
        self.origin = origin
        self.sourceLocator = sourceLocator
    }
}

struct SpeechQueue {
    let maximumPendingSegments: Int
    private(set) var items: [SpeechQueueItem] = []

    init(maximumPendingSegments: Int = 64) {
        self.maximumPendingSegments = max(1, maximumPendingSegments)
    }

    var isEmpty: Bool { items.isEmpty }

    var availableCapacity: Int {
        max(0, maximumPendingSegments - items.count)
    }

    @discardableResult
    mutating func replace(items newItems: [SpeechQueueItem]) -> Int {
        items.removeAll()
        return appendItems(newItems, limit: maximumPendingSegments)
    }

    @discardableResult
    mutating func append(items newItems: [SpeechQueueItem]) -> Int {
        appendItems(newItems, limit: availableCapacity)
    }

    @discardableResult
    mutating func replacePreview(items newItems: [SpeechQueueItem]) -> Int {
        items.removeAll()
        return appendItems(newItems, limit: maximumPendingSegments)
    }

    @discardableResult
    private mutating func appendItems(
        _ newItems: [SpeechQueueItem],
        limit: Int
    ) -> Int {
        guard limit > 0 else { return 0 }
        var appended = 0
        for item in newItems where appended < limit {
            guard !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            items.append(item)
            appended += 1
        }
        return appended
    }

    mutating func dequeue() -> SpeechQueueItem? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    mutating func clear() {
        items.removeAll(keepingCapacity: true)
    }

    mutating func removeItems(forSlotID slotID: UUID) {
        items.removeAll { $0.responseID?.slotID == slotID }
    }

    mutating func removeItems(forResponseID responseID: SpeechResponseIdentity) {
        items.removeAll { $0.responseID == responseID }
    }

    mutating func removeAutomaticItems(
        forSlotID slotID: UUID,
        preservingResponseID responseID: SpeechResponseIdentity? = nil
    ) {
        items.removeAll { item in
            guard item.origin == .automatic,
                  item.responseID?.slotID == slotID else {
                return false
            }
            return item.responseID != responseID
        }
    }
}
