import XCTest
@testable import FloatTabs

final class SpeechQueueTests: XCTestCase {
    private let responseA = SpeechResponseIdentity(
        slotID: UUID(),
        documentToken: "document-a",
        responseID: "document-a:response-a"
    )
    private let responseB = SpeechResponseIdentity(
        slotID: UUID(),
        documentToken: "document-b",
        responseID: "document-b:response-b"
    )

    func testQueueCarriesIdentityAndSequence() {
        var queue = SpeechQueue(maximumPendingSegments: 4)
        queue.enqueue(
            responseID: responseA,
            segments: ["One", "Two"],
            startingSequence: 10
        )

        XCTAssertEqual(queue.dequeue(), SpeechQueueItem(responseID: responseA, sequence: 10, text: "One"))
        XCTAssertEqual(queue.dequeue(), SpeechQueueItem(responseID: responseA, sequence: 11, text: "Two"))
        XCTAssertTrue(queue.isEmpty)
    }

    func testNewResponseDropsOlderPendingSegments() {
        var queue = SpeechQueue(maximumPendingSegments: 4)
        queue.enqueue(responseID: responseA, segments: ["old 1", "old 2"], startingSequence: 0)
        queue.enqueue(responseID: responseB, segments: ["new"], startingSequence: 2)

        XCTAssertEqual(queue.items.map(\.responseID), [responseB])
        XCTAssertEqual(queue.dequeue()?.text, "new")
    }

    func testAppendPreservesExistingPendingSegmentsAcrossResponses() {
        var queue = SpeechQueue(maximumPendingSegments: 4)
        queue.append(
            responseID: responseA,
            requests: [
                SpeechUtteranceRequest(text: "A one", token: 0, languageRole: .english),
                SpeechUtteranceRequest(text: "A two", token: 1, languageRole: .english),
            ]
        )
        queue.append(
            responseID: responseB,
            requests: [
                SpeechUtteranceRequest(text: "B one", token: 2, languageRole: .chinese),
            ]
        )

        XCTAssertEqual(queue.items.map(\.text), ["A one", "A two", "B one"])
        XCTAssertEqual(queue.items.map(\.languageRole), [.english, .english, .chinese])
    }

    func testAppendIsBoundedByPendingSegmentCapacity() {
        var queue = SpeechQueue(maximumPendingSegments: 2)
        let appended = queue.append(
            responseID: responseA,
            requests: [
                SpeechUtteranceRequest(text: "one", token: 0, languageRole: .english),
                SpeechUtteranceRequest(text: "two", token: 1, languageRole: .english),
                SpeechUtteranceRequest(text: "three", token: 2, languageRole: .english),
            ]
        )

        XCTAssertEqual(appended, 2)
        XCTAssertEqual(queue.items.count, 2)
    }

    func testQueueIsBounded() {
        var queue = SpeechQueue(maximumPendingSegments: 2)
        queue.enqueue(
            responseID: responseA,
            segments: ["one", "two", "three"],
            startingSequence: 0
        )

        XCTAssertEqual(queue.items.count, 2)
    }

    func testAutomaticRemovalPreservesManualItems() {
        var queue = SpeechQueue(maximumPendingSegments: 4)
        queue.append(
            responseID: responseA,
            requests: [
                SpeechUtteranceRequest(text: "Automatic", token: 0, languageRole: .english),
            ]
        )
        queue.replace(
            responseID: responseB,
            requests: [
                SpeechUtteranceRequest(text: "Manual", token: 1, languageRole: .chinese),
            ]
        )
        queue.append(
            responseID: responseA,
            requests: [
                SpeechUtteranceRequest(text: "Automatic again", token: 2, languageRole: .english),
            ]
        )

        queue.removeAutomaticItems(forSlotID: responseA.slotID)

        XCTAssertEqual(queue.items.map(\.text), ["Manual"])
        XCTAssertEqual(queue.items.first?.origin, .manual)
    }

    func testPreviewItemsHaveNoResponseIdentityOrTabOrigin() {
        var queue = SpeechQueue(maximumPendingSegments: 4)
        queue.replacePreview(requests: [
            SpeechUtteranceRequest(text: "Preview", token: 8, languageRole: .english),
        ])

        XCTAssertNil(queue.items.first?.responseID)
        XCTAssertEqual(queue.items.first?.origin, .preview)
    }
}
