import Foundation

struct SpeechResponseIdentity: Hashable, Equatable, Sendable {
    let slotID: UUID
    let documentToken: String
    let responseID: String
}

struct SpeechQueueItem: Equatable, Sendable {
    let responseID: SpeechResponseIdentity
    let sequence: UInt64
    let text: String
    let languageRole: SpeechLanguageRole

    init(
        responseID: SpeechResponseIdentity,
        sequence: UInt64,
        text: String,
        languageRole: SpeechLanguageRole = .automatic
    ) {
        self.responseID = responseID
        self.sequence = sequence
        self.text = text
        self.languageRole = languageRole
    }
}

struct SpeechQueue {
    let maximumPendingSegments: Int
    private(set) var items: [SpeechQueueItem] = []

    init(maximumPendingSegments: Int = 64) {
        self.maximumPendingSegments = max(1, maximumPendingSegments)
    }

    var isEmpty: Bool { items.isEmpty }

    /// Compatibility spelling for replacement semantics. Manual reads use
    /// `replace`; automatic completions must use `append`.
    mutating func enqueue(
        responseID: SpeechResponseIdentity,
        segments: [String],
        startingSequence: UInt64
    ) {
        replace(
            responseID: responseID,
            requests: segments.enumerated().map { offset, segment in
                SpeechUtteranceRequest(
                    text: segment,
                    token: startingSequence + UInt64(offset),
                    languageRole: .automatic
                )
            }
        )
    }

    mutating func replace(
        responseID: SpeechResponseIdentity,
        requests: [SpeechUtteranceRequest]
    ) {
        items.removeAll()
        appendItems(
            responseID: responseID,
            requests: requests,
            limit: maximumPendingSegments
        )
    }

    @discardableResult
    mutating func append(
        responseID: SpeechResponseIdentity,
        requests: [SpeechUtteranceRequest]
    ) -> Int {
        appendItems(
            responseID: responseID,
            requests: requests,
            limit: maximumPendingSegments - items.count
        )
    }

    @discardableResult
    private mutating func appendItems(
        responseID: SpeechResponseIdentity,
        requests: [SpeechUtteranceRequest],
        limit: Int
    ) -> Int {
        guard limit > 0 else { return 0 }
        var appended = 0
        for request in requests where appended < limit {
            guard !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            items.append(
                SpeechQueueItem(
                    responseID: responseID,
                    sequence: request.token,
                    text: request.text,
                    languageRole: request.languageRole
                )
            )
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
        items.removeAll { $0.responseID.slotID == slotID }
    }
}
