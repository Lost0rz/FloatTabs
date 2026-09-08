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
        queue.replace(items: [
            SpeechQueueItem(responseID: responseA, sequence: 10, text: "One"),
            SpeechQueueItem(responseID: responseA, sequence: 11, text: "Two"),
        ])

        XCTAssertEqual(queue.dequeue(), SpeechQueueItem(responseID: responseA, sequence: 10, text: "One"))
        XCTAssertEqual(queue.dequeue(), SpeechQueueItem(responseID: responseA, sequence: 11, text: "Two"))
        XCTAssertTrue(queue.isEmpty)
    }

    func testNewResponseDropsOlderPendingSegments() {
        var queue = SpeechQueue(maximumPendingSegments: 4)
        queue.replace(items: [
            SpeechQueueItem(responseID: responseA, sequence: 0, text: "old 1"),
            SpeechQueueItem(responseID: responseA, sequence: 1, text: "old 2"),
        ])
        queue.replace(items: [
            SpeechQueueItem(responseID: responseB, sequence: 2, text: "new"),
        ])

        XCTAssertEqual(queue.items.map(\.responseID), [responseB])
        XCTAssertEqual(queue.dequeue()?.text, "new")
    }

    func testAppendPreservesExistingPendingSegmentsAcrossResponses() {
        var queue = SpeechQueue(maximumPendingSegments: 4)
        queue.append(items: [
            SpeechQueueItem(
                responseID: responseA,
                sequence: 0,
                text: "A one",
                languageRole: .english
            ),
            SpeechQueueItem(
                responseID: responseA,
                sequence: 1,
                text: "A two",
                languageRole: .english
            ),
        ])
        queue.append(items: [
            SpeechQueueItem(
                responseID: responseB,
                sequence: 2,
                text: "B one",
                languageRole: .chinese
            ),
        ])

        XCTAssertEqual(queue.items.map(\.text), ["A one", "A two", "B one"])
        XCTAssertEqual(queue.items.map(\.languageRole), [.english, .english, .chinese])
    }

    func testAppendIsBoundedByPendingSegmentCapacity() {
        var queue = SpeechQueue(maximumPendingSegments: 2)
        let appended = queue.append(items: [
            SpeechQueueItem(responseID: responseA, sequence: 0, text: "one", languageRole: .english),
            SpeechQueueItem(responseID: responseA, sequence: 1, text: "two", languageRole: .english),
            SpeechQueueItem(responseID: responseA, sequence: 2, text: "three", languageRole: .english),
        ])

        XCTAssertEqual(appended, 2)
        XCTAssertEqual(queue.items.count, 2)
    }

    func testQueueIsBounded() {
        var queue = SpeechQueue(maximumPendingSegments: 2)
        queue.replace(items: [
            SpeechQueueItem(responseID: responseA, sequence: 0, text: "one"),
            SpeechQueueItem(responseID: responseA, sequence: 1, text: "two"),
            SpeechQueueItem(responseID: responseA, sequence: 2, text: "three"),
        ])

        XCTAssertEqual(queue.items.count, 2)
    }

    func testAutomaticRemovalPreservesManualItems() {
        var queue = SpeechQueue(maximumPendingSegments: 4)
        queue.append(items: [
            SpeechQueueItem(
                responseID: responseA,
                sequence: 0,
                text: "Automatic",
                languageRole: .english
            ),
        ])
        queue.replace(items: [
            SpeechQueueItem(
                responseID: responseB,
                sequence: 1,
                text: "Manual",
                languageRole: .chinese,
                origin: .manual
            ),
        ])
        queue.append(items: [
            SpeechQueueItem(
                responseID: responseA,
                sequence: 2,
                text: "Automatic again",
                languageRole: .english
            ),
        ])

        queue.removeAutomaticItems(forSlotID: responseA.slotID)

        XCTAssertEqual(queue.items.map(\.text), ["Manual"])
        XCTAssertEqual(queue.items.first?.origin, .manual)
    }

    func testPreviewItemsHaveNoResponseIdentityOrTabOrigin() {
        var queue = SpeechQueue(maximumPendingSegments: 4)
        queue.replacePreview(items: [
            SpeechQueueItem(
                responseID: nil,
                sequence: 8,
                text: "Preview",
                languageRole: .english,
                origin: .preview
            ),
        ])

        XCTAssertNil(queue.items.first?.responseID)
        XCTAssertEqual(queue.items.first?.origin, .preview)
    }
}
