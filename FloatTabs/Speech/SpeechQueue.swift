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
}

struct SpeechQueue {
    let maximumPendingSegments: Int
    private(set) var items: [SpeechQueueItem] = []

    init(maximumPendingSegments: Int = 64) {
        self.maximumPendingSegments = max(1, maximumPendingSegments)
    }

    var isEmpty: Bool { items.isEmpty }

    mutating func enqueue(
        responseID: SpeechResponseIdentity,
        segments: [String],
        startingSequence: UInt64
    ) {
        // A newly extracted response takes priority over unfinished pending
        // segments from an older response. The current AVSpeech utterance is
        // stopped by the coordinator before this method is called.
        items.removeAll()
        for (offset, segment) in segments.prefix(maximumPendingSegments).enumerated() {
            guard !segment.isEmpty else { continue }
            items.append(
                SpeechQueueItem(
                    responseID: responseID,
                    sequence: startingSequence + UInt64(offset),
                    text: segment
                )
            )
        }
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
