import Foundation
import Darwin
import XCTest
@testable import FloatTabs

@MainActor
final class MemoXCaptureEpochGateTests: XCTestCase {
    func testCompletionARequiresExactResponseIdentity() throws {
        let gate = MemoXCaptureEpochGate()
        let slotID = UUID()
        let identityA = try identity("message:completion-a")

        gate.observe(.generationStarted, for: slotID)
        let attempt = gate.beginCompletion(
            for: slotID,
            responseIdentity: identityA,
            completedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(gate.evaluate(payload(identityA), for: attempt), .accepted)
        XCTAssertEqual(gate.evaluate(payload(identityA), for: attempt), .discarded)
    }

    func testGenerationBStartDropsPendingCompletionA() throws {
        let gate = MemoXCaptureEpochGate()
        let slotID = UUID()
        let identityA = try identity("message:completion-a")

        gate.observe(.generationStarted, for: slotID)
        let attempt = gate.beginCompletion(
            for: slotID,
            responseIdentity: identityA,
            completedAt: Date(timeIntervalSince1970: 100)
        )
        gate.observe(.generationStarted, for: slotID)

        XCTAssertEqual(gate.evaluate(payload(identityA), for: attempt), .discarded)
    }

    func testResponseBTemporarilyMismatchingCompletionADoesNotPassGate() throws {
        let gate = MemoXCaptureEpochGate()
        let slotID = UUID()
        let identityA = try identity("message:completion-a")
        let identityB = try identity("message:completion-b")

        gate.observe(.generationStarted, for: slotID)
        let attempt = gate.beginCompletion(
            for: slotID,
            responseIdentity: identityA,
            completedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(gate.evaluate(payload(identityB), for: attempt), .retryable)
        XCTAssertTrue(gate.isCurrent(attempt))
    }

    func testMissingCompletionIdentityStillRequiresCurrentEpoch() {
        let gate = MemoXCaptureEpochGate()
        let slotID = UUID()

        gate.observe(.generationStarted, for: slotID)
        let attempt = gate.beginCompletion(
            for: slotID,
            responseIdentity: nil,
            completedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(gate.evaluate(payload(nil), for: attempt), .accepted)
    }

    func testGenerationStartDropsIdentityUnavailableCompletion() {
        let gate = MemoXCaptureEpochGate()
        let slotID = UUID()

        gate.observe(.generationStarted, for: slotID)
        let attempt = gate.beginCompletion(
            for: slotID,
            responseIdentity: nil,
            completedAt: Date(timeIntervalSince1970: 100)
        )
        gate.observe(.generationStarted, for: slotID)

        XCTAssertEqual(gate.evaluate(payload(nil), for: attempt), .discarded)
    }

    func testRuntimeResetDropsPendingCompletion() throws {
        let gate = MemoXCaptureEpochGate()
        let slotID = UUID()
        let identityA = try identity("message:completion-a")

        gate.observe(.generationStarted, for: slotID)
        let attempt = gate.beginCompletion(
            for: slotID,
            responseIdentity: identityA,
            completedAt: Date(timeIntervalSince1970: 100)
        )
        gate.observe(.runtimeReset, for: slotID)

        XCTAssertEqual(gate.evaluate(payload(identityA), for: attempt), .discarded)
    }

    func testSequentialCompletionsHaveIndependentAcceptance() throws {
        let gate = MemoXCaptureEpochGate()
        let slotID = UUID()
        let identityA = try identity("message:completion-a")
        let identityB = try identity("message:completion-b")

        gate.observe(.generationStarted, for: slotID)
        let attemptA = gate.beginCompletion(
            for: slotID,
            responseIdentity: identityA,
            completedAt: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(gate.evaluate(payload(identityA), for: attemptA), .accepted)

        gate.observe(.generationStarted, for: slotID)
        let attemptB = gate.beginCompletion(
            for: slotID,
            responseIdentity: identityB,
            completedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertNotEqual(attemptA.id, attemptB.id)
        XCTAssertEqual(gate.evaluate(payload(identityB), for: attemptB), .accepted)
    }

    func testNilFirstExtractionCanRetryInSameEpochAndAcceptOnce() throws {
        let gate = MemoXCaptureEpochGate()
        let slotID = UUID()
        let identityA = try identity("message:completion-a")

        gate.observe(.generationStarted, for: slotID)
        let attempt = gate.beginCompletion(
            for: slotID,
            responseIdentity: identityA,
            completedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(gate.evaluate(nil, for: attempt), .retryable)
        XCTAssertTrue(gate.isCurrent(attempt))
        XCTAssertEqual(gate.evaluate(payload(identityA), for: attempt), .accepted)
        XCTAssertEqual(gate.evaluate(payload(identityA), for: attempt), .discarded)
    }

    func testEpochChangeBeforeRetryAbandonsOldCompletion() throws {
        let gate = MemoXCaptureEpochGate()
        let slotID = UUID()
        let identityA = try identity("message:completion-a")

        gate.observe(.generationStarted, for: slotID)
        let attempt = gate.beginCompletion(
            for: slotID,
            responseIdentity: identityA,
            completedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(gate.evaluate(nil, for: attempt), .retryable)
        gate.observe(.generationStarted, for: slotID)
        XCTAssertFalse(gate.isCurrent(attempt))
        XCTAssertEqual(gate.evaluate(payload(identityA), for: attempt), .discarded)
    }

    private func identity(_ rawValue: String) throws -> ChatGPTResponseIdentity {
        try XCTUnwrap(ChatGPTResponseIdentity(rawValue: rawValue))
    }

    private func payload(_ identity: ChatGPTResponseIdentity?) -> ChatGPTResponsePayload {
        ChatGPTResponsePayload(
            version: ChatGPTResponsePayload.currentVersion,
            kind: .response,
            requestID: "request-memox-12345678",
            documentToken: "document-memox-12345678",
            responseID: "document-memox-12345678:response-1",
            blocks: [
                SpeechContentBlock(kind: .paragraph, text: "synthetic response", level: nil)
            ],
            responseIdentity: identity
        )
    }
}

final class MemoXCaptureWireTests: XCTestCase {
    func testPayloadV1IsStableAndContainsOnlyStructuredBlocks() throws {
        let locator = SpeechSourceLocator(
            slotID: UUID(),
            documentToken: "document-private-token",
            responseID: "document-private-token:response-1",
            blockID: "private-block-id"
        )
        let sourceBlock = SpeechContentBlock(
            kind: .heading,
            text: "Synthetic title",
            level: 2,
            sourceLocator: locator
        )
        let payload = MemoXResponsePayloadV1(blocks: [sourceBlock])

        let first = try payload.encodedData()
        let second = try payload.encodedData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: first) as? [String: Any])
        let blocks = try XCTUnwrap(object["blocks"] as? [[String: Any]])
        let block = try XCTUnwrap(blocks.first)

        XCTAssertEqual(first, second)
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(Set(object.keys), ["version", "blocks"])
        XCTAssertEqual(Set(block.keys), ["kind", "text", "level"])
        XCTAssertEqual(block["kind"] as? String, "heading")
        XCTAssertEqual(block["text"] as? String, "Synthetic title")
        XCTAssertEqual(block["level"] as? Int, 2)
        XCTAssertFalse(String(decoding: first, as: UTF8.self).contains("private-block-id"))
        XCTAssertFalse(String(decoding: first, as: UTF8.self).contains("document-private-token"))
    }

    func testEnvelopeV1HasExactPRDWireKeysAndBigEndianFrame() throws {
        let eventID = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!
        let sourceID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let identity = try XCTUnwrap(ChatGPTResponseIdentity(rawValue: "message:provider-id-1"))
        let payload = try MemoXResponsePayloadV1(blocks: [
            SpeechContentBlock(kind: .paragraph, text: "Synthetic response", level: nil)
        ]).encodedData()
        let envelope = try MemoXCaptureEnvelopeV1.make(
            eventID: eventID,
            sourceInstanceID: sourceID,
            slotID: UUID(uuidString: "99999999-aaaa-4bbb-8ccc-dddddddddddd")!,
            providerNativeEventID: identity,
            occurredAt: Date(timeIntervalSince1970: 1_798_821_300.125),
            payloadBytes: payload
        )
        let json = try envelope.encodedWireJSON()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let expectedKeys: Set<String> = [
            "schema_version", "event_id", "adapter_id", "source_instance_id",
            "provider", "event_kind", "provider_native_event_id", "source_sequence",
            "source_version", "occurred_at", "source_asserted_at", "media_type",
            "encoding", "payload_base64", "payload_sha256", "metadata"
        ]
        let frame = try envelope.framedRequest()
        let frameLength = frame.prefix(4).reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        }

        XCTAssertEqual(Set(object.keys), expectedKeys)
        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["adapter_id"] as? String, "floattabs")
        XCTAssertEqual(object["provider"] as? String, "chatgpt")
        XCTAssertEqual(object["event_kind"] as? String, "assistant_response_completed")
        XCTAssertEqual(object["event_id"] as? String, eventID.uuidString.lowercased())
        XCTAssertEqual(object["source_instance_id"] as? String, sourceID.uuidString.lowercased())
        XCTAssertEqual(object["provider_native_event_id"] as? String, identity.rawValue)
        XCTAssertTrue(object["source_sequence"] is NSNull)
        XCTAssertTrue(object["source_version"] is NSNull)
        XCTAssertTrue(object["source_asserted_at"] is NSNull)
        XCTAssertEqual(object["occurred_at"] as? String, "2027-01-01T16:35:00.125Z")
        XCTAssertEqual(object["media_type"] as? String, MemoXResponsePayloadV1.mediaType)
        XCTAssertEqual(object["encoding"] as? String, "utf-8")
        XCTAssertEqual(object["payload_sha256"] as? String, envelope.payloadSHA256)
        XCTAssertEqual(envelope.payloadSHA256.count, 64)
        XCTAssertTrue(envelope.payloadSHA256.allSatisfy { $0.isNumber || "abcdef".contains($0) })
        XCTAssertEqual(frameLength, UInt32(json.count))
        XCTAssertEqual(frame.dropFirst(4), json)
        XCTAssertLessThan(frame.count, MemoXCaptureEnvelopeV1.maximumRequestFrame)
    }

    func testWorstCaseMultibyteRequestRemainsBelowPRDFrameLimit() throws {
        let largeText = String(repeating: "\u{0800}", count: 4_000)
        let blocks = (0..<1_024).map { _ in
            SpeechContentBlock(kind: .paragraph, text: largeText, level: nil)
        }
        let payload = try MemoXResponsePayloadV1(blocks: blocks).encodedData()
        let envelope = try MemoXCaptureEnvelopeV1.make(
            eventID: UUID(),
            sourceInstanceID: UUID(),
            slotID: UUID(),
            providerNativeEventID: nil,
            occurredAt: Date(timeIntervalSince1970: 1_798_821_300),
            payloadBytes: payload
        )
        let request = try envelope.encodedWireJSON()

        XCTAssertLessThan(request.count, MemoXCaptureEnvelopeV1.maximumRequestFrame)
        XCTAssertEqual(request.count, 16_444_740)
    }

    func testReplyParserRequiresExactKnownShapesAndPreservesBooleanFalse() throws {
        let eventID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        let observationID = "11111111-2222-4333-8444-555555555555"
        let ack = try MemoXCaptureReply.parse(json: """
        {"version":1,"status":"ack","event_id":"\(eventID)","observation_id":"\(observationID)","inserted":false,"code":null}
        """)

        XCTAssertEqual(ack, .ack(eventID: eventID, observationID: observationID, inserted: false))
        XCTAssertThrowsError(try MemoXCaptureReply.parse(json: """
        {"version":1,"status":"ack","event_id":"\(eventID)","observation_id":"\(observationID)","inserted":true,"code":null,"extra":1}
        """))
        XCTAssertThrowsError(try MemoXCaptureReply.parse(json: """
        {"version":1,"status":"ack","event_id":"\(eventID)","observation_id":null,"inserted":true,"code":null}
        """))
        XCTAssertThrowsError(try MemoXCaptureReply.parse(json: """
        {"version":1,"status":"future","event_id":"\(eventID)","observation_id":"\(observationID)","inserted":true,"code":null}
        """))
    }

    func testRetryPolicyUsesFrozenCadence() {
        XCTAssertEqual(MemoXRetryPolicy.delay(afterFailure: 1), 2)
        XCTAssertEqual(MemoXRetryPolicy.delay(afterFailure: 2), 5)
        XCTAssertEqual(MemoXRetryPolicy.delay(afterFailure: 3), 15)
        XCTAssertEqual(MemoXRetryPolicy.delay(afterFailure: 4), 60)
        XCTAssertEqual(MemoXRetryPolicy.delay(afterFailure: 20), 60)
    }
}

final class MemoXActivationStoreTests: XCTestCase {
    func testInactiveDefaultDoesNotCreatePrivateStateRoot() throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("MemoX/runtime/floattabs-v1.sock")
        let store = MemoXActivationStore(rootURL: root.appendingPathComponent("FloatTabs/MemoX"), receiverSocketURL: socketURL)

        XCTAssertFalse(try store.resolveAndMarkActive())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.rootURL.path))
    }

    func testTrustedCurrentUser0600SocketActivatesWithoutPrivateMarkerContent() throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("MemoX/runtime/floattabs-v1.sock")
        let descriptor = try MemoXTestSupport.bindUnixSocket(at: socketURL)
        defer { Darwin.close(descriptor) }
        let store = MemoXActivationStore(rootURL: root.appendingPathComponent("FloatTabs/MemoX"), receiverSocketURL: socketURL)

        XCTAssertTrue(try store.resolveAndMarkActive())
        let marker = try Data(contentsOf: store.activationURL)
        let text = String(decoding: marker, as: UTF8.self)
        var metadata = stat()
        XCTAssertEqual(lstat(store.activationURL.path, &metadata), 0)
        XCTAssertEqual(metadata.st_mode & 0o777, 0o600)
        XCTAssertFalse(text.contains("response"))
        XCTAssertFalse(text.contains("provider"))
    }

    func testRegularFileDirectorySymlinkWrongOwnerAndBroadSocketDoNotActivate() throws {
        for endpointKind in ["file", "directory", "symlink", "wrong-owner", "broad-socket"] {
            let root = try MemoXTestSupport.makeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let endpoint = root.appendingPathComponent("endpoint")
            var descriptor: Int32?
            var effectiveUID = geteuid()
            switch endpointKind {
            case "file":
                try Data("not a socket".utf8).write(to: endpoint)
            case "directory":
                try FileManager.default.createDirectory(at: endpoint, withIntermediateDirectories: false)
            case "symlink":
                let target = root.appendingPathComponent("target.sock")
                descriptor = try MemoXTestSupport.bindUnixSocket(at: target)
                try FileManager.default.createSymbolicLink(at: endpoint, withDestinationURL: target)
            case "wrong-owner":
                descriptor = try MemoXTestSupport.bindUnixSocket(at: endpoint)
                effectiveUID = geteuid() ^ 1
            case "broad-socket":
                descriptor = try MemoXTestSupport.bindUnixSocket(at: endpoint, mode: 0o660)
            default:
                XCTFail("Unexpected endpoint fixture")
            }
            defer { if let descriptor { Darwin.close(descriptor) } }
            let store = MemoXActivationStore(
                rootURL: root.appendingPathComponent("FloatTabs/MemoX"),
                receiverSocketURL: endpoint,
                effectiveUID: effectiveUID
            )

            XCTAssertFalse(try store.resolveAndMarkActive(), "accepted endpoint kind: \(endpointKind)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.activationURL.path))
        }
    }

    func testActivationSurvivesReceiverDisappearance() throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("MemoX/runtime/floattabs-v1.sock")
        let descriptor = try MemoXTestSupport.bindUnixSocket(at: socketURL)
        let store = MemoXActivationStore(rootURL: root.appendingPathComponent("FloatTabs/MemoX"), receiverSocketURL: socketURL)
        XCTAssertTrue(try store.resolveAndMarkActive())

        Darwin.close(descriptor)
        try FileManager.default.removeItem(at: socketURL)

        XCTAssertTrue(try store.resolveAndMarkActive())
    }

    func testPendingOrQuarantineEvidenceRestoresActivationWithoutMarker() throws {
        for evidenceDirectory in ["pending", "quarantine"] {
            let root = try MemoXTestSupport.makeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
            let evidence = stateRoot.appendingPathComponent("outbox/\(evidenceDirectory)")
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
            try Data("retained evidence".utf8).write(to: evidence.appendingPathComponent("retained.json"))
            let store = MemoXActivationStore(
                rootURL: stateRoot,
                receiverSocketURL: root.appendingPathComponent("missing.sock")
            )

            XCTAssertTrue(try store.resolveAndMarkActive())
            XCTAssertTrue(FileManager.default.fileExists(atPath: store.activationURL.path))
        }
    }
}

final class MemoXInstallationIdentityStoreTests: XCTestCase {
    func testFirstActivationMintsAndRestartReusesOnePersistentUUID() throws {
        let root = try MemoXTestSupport.makeRoot().appendingPathComponent("FloatTabs/MemoX")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try MemoXActivationStore.ensureStateDirectories(root)
        let store = MemoXInstallationIdentityStore(rootURL: root)

        let first = try store.resolve(durableSourceInstanceIDs: [])
        let afterRestart = try MemoXInstallationIdentityStore(rootURL: root)
            .resolve(durableSourceInstanceIDs: [])
        let persisted = try Data(contentsOf: store.installationURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: persisted) as? [String: Any])
        var metadata = stat()

        XCTAssertEqual(first, afterRestart)
        XCTAssertEqual(Set(json.keys), ["version", "source_instance_id"])
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertEqual(json["source_instance_id"] as? String, first.uuidString.lowercased())
        XCTAssertEqual(lstat(store.installationURL.path, &metadata), 0)
        XCTAssertEqual(metadata.st_mode & 0o777, 0o600)
    }

    func testMissingIdentityRecoversExactUnambiguousDurableOutboxIdentity() throws {
        let root = try MemoXTestSupport.makeRoot().appendingPathComponent("FloatTabs/MemoX")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try MemoXActivationStore.ensureStateDirectories(root)
        let expected = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!
        let store = MemoXInstallationIdentityStore(rootURL: root)

        let recovered = try store.resolve(durableSourceInstanceIDs: [expected.uuidString.lowercased()])

        XCTAssertEqual(recovered, expected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.installationURL.path))
    }

    func testInvalidIdentityRecoversOnlyWhenAllDurableRecordsAgree() throws {
        let root = try MemoXTestSupport.makeRoot().appendingPathComponent("FloatTabs/MemoX")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try MemoXActivationStore.ensureStateDirectories(root)
        let expected = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
        let store = MemoXInstallationIdentityStore(rootURL: root)
        try Data("{broken".utf8).write(to: store.installationURL)

        XCTAssertEqual(
            try store.resolve(durableSourceInstanceIDs: [expected.uuidString.lowercased()]),
            expected
        )
        XCTAssertThrowsError(try store.resolve(durableSourceInstanceIDs: [
            expected.uuidString.lowercased(),
            UUID().uuidString.lowercased()
        ]))
    }

    func testSplitBrainDoesNotMintOrOverwriteAnIdentity() throws {
        let root = try MemoXTestSupport.makeRoot().appendingPathComponent("FloatTabs/MemoX")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try MemoXActivationStore.ensureStateDirectories(root)
        let store = MemoXInstallationIdentityStore(rootURL: root)
        let first = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!.uuidString.lowercased()
        let second = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!.uuidString.lowercased()

        XCTAssertThrowsError(try store.resolve(durableSourceInstanceIDs: [first, second]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.installationURL.path))
    }
}

final class MemoXOutboxStoreTests: XCTestCase {
    func testCommitDurablyCreatesPrivatePerEventPendingRecordBeforeReturn() async throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
        let store = try makeActiveStore(root: root, stateRoot: stateRoot)

        let record = try await store.commit(
            payloadBytes: Data("{\"version\":1,\"blocks\":[{\"kind\":\"paragraph\",\"text\":\"safe fixture\",\"level\":null}]}".utf8),
            slotID: UUID(uuidString: "99999999-aaaa-4bbb-8ccc-dddddddddddd")!,
            providerNativeEventID: nil,
            occurredAt: Date(timeIntervalSince1970: 1_798_821_300)
        )
        let pending = try await store.pendingRecords()
        var fileMetadata = stat()
        var directoryMetadata = stat()

        XCTAssertEqual(pending, [record])
        XCTAssertEqual(record.attemptCount, 0)
        XCTAssertEqual(record.eventID, record.envelope.eventID)
        XCTAssertEqual(lstat(store.pendingDirectoryURL.appendingPathComponent("\(record.eventID).json").path, &fileMetadata), 0)
        XCTAssertEqual(fileMetadata.st_mode & 0o777, 0o600)
        XCTAssertEqual(lstat(store.pendingDirectoryURL.path, &directoryMetadata), 0)
        XCTAssertEqual(directoryMetadata.st_mode & 0o777, 0o700)
    }

    func testFailureRewriteIsAtomicAndPersistsSafeAttemptMetadata() async throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
        let store = try makeActiveStore(root: root, stateRoot: stateRoot)
        let record = try await store.commit(
            payloadBytes: Data("{\"version\":1,\"blocks\":[{\"kind\":\"paragraph\",\"text\":\"safe fixture\",\"level\":null}]}".utf8),
            slotID: UUID(),
            providerNativeEventID: nil,
            occurredAt: Date(timeIntervalSince1970: 1_798_821_300)
        )

        try await store.recordFailure(eventID: record.eventID, at: Date(timeIntervalSince1970: 200), safeCode: "timeout")

        let updatedRecords = try await store.pendingRecords()
        let updated = try XCTUnwrap(updatedRecords.first)
        XCTAssertEqual(updated.eventID, record.eventID)
        XCTAssertEqual(updated.envelope, record.envelope)
        XCTAssertEqual(updated.attemptCount, 1)
        XCTAssertEqual(updated.lastErrorCode, "timeout")
    }

    func testOnlyMatchingACKRetiresAndMatchingRejectQuarantines() async throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
        let store = try makeActiveStore(root: root, stateRoot: stateRoot)
        let first = try await store.commit(
            payloadBytes: Data("{\"version\":1,\"blocks\":[{\"kind\":\"paragraph\",\"text\":\"one\",\"level\":null}]}".utf8),
            slotID: UUID(), providerNativeEventID: nil, occurredAt: Date(timeIntervalSince1970: 100)
        )
        let second = try await store.commit(
            payloadBytes: Data("{\"version\":1,\"blocks\":[{\"kind\":\"paragraph\",\"text\":\"two\",\"level\":null}]}".utf8),
            slotID: UUID(), providerNativeEventID: nil, occurredAt: Date(timeIntervalSince1970: 200)
        )

        let mismatchedAckRetired = try await store.retireAfterMatchingACK(
            eventID: UUID().uuidString.lowercased(),
            expectedEnvelope: second.envelope
        )
        let firstWasQuarantined = try await store.quarantineAfterMatchingReject(
            eventID: first.eventID,
            expectedEnvelope: first.envelope
        )
        let secondWasRetired = try await store.retireAfterMatchingACK(
            eventID: second.eventID,
            expectedEnvelope: second.envelope
        )
        XCTAssertFalse(mismatchedAckRetired)
        XCTAssertTrue(firstWasQuarantined)
        XCTAssertTrue(secondWasRetired)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: store.pendingDirectoryURL.path).isEmpty)
        let quarantined = try FileManager.default.contentsOfDirectory(atPath: store.quarantineDirectoryURL.path)
        XCTAssertEqual(quarantined, ["\(first.eventID).json"])
        XCTAssertEqual(try MemoXOutboxRecordV1.decode(
            Data(contentsOf: store.quarantineDirectoryURL.appendingPathComponent(quarantined[0])),
            expectedEventID: first.eventID
        ), first)
    }

    func testACKCannotRetireARecordThatChangedWhileDeliveryWasInFlight() async throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
        let store = try makeActiveStore(root: root, stateRoot: stateRoot)
        let original = try await store.commit(
            payloadBytes: Data("{\"version\":1,\"blocks\":[{\"kind\":\"paragraph\",\"text\":\"original\",\"level\":null}]}".utf8),
            slotID: UUID(), providerNativeEventID: nil, occurredAt: Date(timeIntervalSince1970: 100)
        )
        let changedEnvelope = try MemoXCaptureEnvelopeV1.make(
            eventID: UUID(uuidString: original.eventID)!,
            sourceInstanceID: UUID(uuidString: original.sourceInstanceID)!,
            slotID: UUID(), providerNativeEventID: nil,
            occurredAt: Date(timeIntervalSince1970: 101),
            payloadBytes: Data("{\"version\":1,\"blocks\":[{\"kind\":\"paragraph\",\"text\":\"changed\",\"level\":null}]}".utf8)
        )
        let changed = MemoXOutboxRecordV1(envelope: changedEnvelope, createdAt: Date(timeIntervalSince1970: 100))
        let pendingURL = store.pendingDirectoryURL.appendingPathComponent("\(original.eventID).json")
        try MemoXDurableFile.replace(try changed.encodedData(), at: pendingURL)

        do {
            _ = try await store.retireAfterMatchingACK(
                eventID: original.eventID,
                expectedEnvelope: original.envelope
            )
            XCTFail("A stale delivery result must not retire a different durable envelope")
        } catch {
            XCTAssertEqual(error as? MemoXCaptureStoreError, .identityConflict)
        }
        XCTAssertEqual(try Data(contentsOf: pendingURL), try changed.encodedData())
    }

    func testCorruptPendingRecordIsPreservedInQuarantineAndLaterRecordSurvives() async throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
        let store = try makeActiveStore(root: root, stateRoot: stateRoot)
        let valid = try await store.commit(
            payloadBytes: Data("{\"version\":1,\"blocks\":[{\"kind\":\"paragraph\",\"text\":\"safe\",\"level\":null}]}".utf8),
            slotID: UUID(), providerNativeEventID: nil, occurredAt: Date(timeIntervalSince1970: 100)
        )
        let corruptID = UUID().uuidString.lowercased()
        let corruptBytes = Data("{truncated".utf8)
        try corruptBytes.write(to: store.pendingDirectoryURL.appendingPathComponent("\(corruptID).json"))

        let pending = try await store.pendingRecords()

        XCTAssertEqual(pending, [valid])
        XCTAssertEqual(try Data(contentsOf: store.quarantineDirectoryURL.appendingPathComponent("\(corruptID).json")), corruptBytes)
    }

    func testRestartRecoversSameInstallationAndPendingEventWithoutRecapture() async throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
        let firstStore = try makeActiveStore(root: root, stateRoot: stateRoot)
        let original = try await firstStore.commit(
            payloadBytes: Data("{\"version\":1,\"blocks\":[{\"kind\":\"paragraph\",\"text\":\"restart fixture\",\"level\":null}]}".utf8),
            slotID: UUID(), providerNativeEventID: nil,
            occurredAt: Date(timeIntervalSince1970: 100)
        )
        let restartedStore = MemoXOutboxStore(
            rootURL: stateRoot,
            receiverSocketURL: root.appendingPathComponent("missing.sock")
        )

        let recovered = try await restartedStore.pendingRecords()
        let installation = try JSONSerialization.jsonObject(
            with: Data(contentsOf: stateRoot.appendingPathComponent("installation.json"))
        ) as? [String: Any]

        XCTAssertEqual(recovered, [original])
        XCTAssertEqual(installation?["source_instance_id"] as? String, original.sourceInstanceID)
    }

    func testStartupRejectsDurableOutboxWithSplitBrainSourceIdentities() async throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
        let store = try makeActiveStore(root: root, stateRoot: stateRoot)
        let pending = store.pendingDirectoryURL
        for (eventRaw, sourceRaw) in [
            ("aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", "11111111-2222-4333-8444-555555555555"),
            ("bbbbbbbb-cccc-4ddd-8eee-ffffffffffff", "22222222-3333-4444-8555-666666666666")
        ] {
            let envelope = try MemoXCaptureEnvelopeV1.make(
                eventID: UUID(uuidString: eventRaw)!,
                sourceInstanceID: UUID(uuidString: sourceRaw)!,
                slotID: UUID(), providerNativeEventID: nil,
                occurredAt: Date(timeIntervalSince1970: 100), payloadBytes: Data("{}".utf8)
            )
            let record = MemoXOutboxRecordV1(envelope: envelope, createdAt: Date(timeIntervalSince1970: 100))
            try MemoXDurableFile.replace(
                try record.encodedData(),
                at: pending.appendingPathComponent("\(eventRaw).json")
            )
        }
        let restartedStore = MemoXOutboxStore(
            rootURL: stateRoot,
            receiverSocketURL: root.appendingPathComponent("missing.sock")
        )

        do {
            _ = try await restartedStore.pendingRecords()
            XCTFail("Split-brain identities must fail closed")
        } catch {
            XCTAssertEqual(error as? MemoXCaptureStoreError, .identityConflict)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateRoot.appendingPathComponent("installation.json").path))
    }

    func testDurableReplacementCrashBoundariesNeverExposePartialFinalRecord() throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("record.json")
        let old = Data("old complete".utf8)
        let replacement = Data("new complete".utf8)
        try old.write(to: destination)

        XCTAssertThrowsError(try MemoXDurableFile.replace(replacement, at: destination) { phase in
            if phase == .fullySynced { throw POSIXError(.EINTR) }
        })
        XCTAssertEqual(try Data(contentsOf: destination), old)

        XCTAssertThrowsError(try MemoXDurableFile.replace(replacement, at: destination) { phase in
            if phase == .renamed { throw POSIXError(.EINTR) }
        })
        XCTAssertEqual(try Data(contentsOf: destination), replacement)
    }

    private func makeActiveStore(root: URL, stateRoot: URL) throws -> MemoXOutboxStore {
        let socket = root.appendingPathComponent("MemoX/runtime/floattabs-v1.sock")
        let descriptor = try MemoXTestSupport.bindUnixSocket(at: socket)
        defer { Darwin.close(descriptor) }
        let activation = MemoXActivationStore(rootURL: stateRoot, receiverSocketURL: socket)
        XCTAssertTrue(try activation.resolveAndMarkActive())
        try FileManager.default.removeItem(at: socket)
        return MemoXOutboxStore(rootURL: stateRoot, receiverSocketURL: socket)
    }
}

final class MemoXUnixSocketClientTests: XCTestCase {
    func testNativeClientSendsOneBigEndianFrameAndReadsOneReply() throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("MemoX/runtime/floattabs-v1.sock")
        let serverDescriptor = try MemoXTestSupport.bindUnixSocket(at: socketURL)
        defer { Darwin.close(serverDescriptor) }
        XCTAssertEqual(Darwin.listen(serverDescriptor, 1), 0)

        let eventID = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!
        let envelope = try MemoXCaptureEnvelopeV1.make(
            eventID: eventID,
            sourceInstanceID: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!,
            slotID: UUID(uuidString: "99999999-aaaa-4bbb-8ccc-dddddddddddd")!,
            providerNativeEventID: nil,
            occurredAt: Date(timeIntervalSince1970: 100),
            payloadBytes: Data("{\"version\":1,\"blocks\":[]}".utf8)
        )
        let received = MemoXTestSupport.SocketCaptureBox()
        let reply = Data("{\"version\":1,\"status\":\"ack\",\"event_id\":\"\(eventID.uuidString.lowercased())\",\"observation_id\":\"22222222-3333-4444-8555-666666666666\",\"inserted\":true,\"code\":null}".utf8)
        DispatchQueue.global(qos: .utility).async {
            let clientDescriptor = Darwin.accept(serverDescriptor, nil, nil)
            guard clientDescriptor >= 0 else { received.finish(nil); return }
            defer { Darwin.close(clientDescriptor) }
            MemoXTestSupport.preventSIGPIPE(on: clientDescriptor)
            received.finish(MemoXTestSupport.readFrame(clientDescriptor))
            MemoXTestSupport.writeFrame(reply, to: clientDescriptor)
        }

        let parsed = try MemoXUnixSocketClient(socketURL: socketURL).send(envelope)
        let requestFrame = try XCTUnwrap(received.wait(timeout: 2))
        let expectedJSON = try envelope.encodedWireJSON()
        let requestLength = requestFrame.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }

        XCTAssertEqual(parsed, .ack(
            eventID: eventID.uuidString.lowercased(),
            observationID: "22222222-3333-4444-8555-666666666666",
            inserted: true
        ))
        XCTAssertEqual(requestLength, UInt32(expectedJSON.count))
        XCTAssertEqual(requestFrame.dropFirst(4), expectedJSON)
    }

    func testFragmentedReplyCannotExtendAbsoluteDeadline() throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("MemoX/runtime/floattabs-v1.sock")
        let serverDescriptor = try MemoXTestSupport.bindUnixSocket(at: socketURL)
        defer { Darwin.close(serverDescriptor) }
        XCTAssertEqual(Darwin.listen(serverDescriptor, 1), 0)

        let envelope = try MemoXCaptureEnvelopeV1.make(
            eventID: UUID(), sourceInstanceID: UUID(), slotID: UUID(),
            providerNativeEventID: nil, occurredAt: Date(timeIntervalSince1970: 100),
            payloadBytes: Data("{}".utf8)
        )
        let received = MemoXTestSupport.SocketCaptureBox()
        let json = Data("{\"version\":1,\"status\":\"retry\",\"event_id\":null,\"observation_id\":null,\"inserted\":null,\"code\":\"busy\"}".utf8)
        let fullReply = MemoXTestSupport.framed(json)
        DispatchQueue.global(qos: .utility).async {
            let clientDescriptor = Darwin.accept(serverDescriptor, nil, nil)
            guard clientDescriptor >= 0 else { received.finish(nil); return }
            defer { Darwin.close(clientDescriptor) }
            MemoXTestSupport.preventSIGPIPE(on: clientDescriptor)
            received.finish(MemoXTestSupport.readFrame(clientDescriptor))
            for byte in fullReply {
                MemoXTestSupport.writeBytes(Data([byte]), to: clientDescriptor)
                usleep(80_000)
            }
        }
        let client = MemoXUnixSocketClient(socketURL: socketURL, timeout: 0.25)
        let start = DispatchTime.now().uptimeNanoseconds

        XCTAssertThrowsError(try client.send(envelope)) { error in
            XCTAssertEqual(error as? MemoXUnixSocketError, .deadlineExceeded)
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        XCTAssertLessThan(elapsed, 0.7)
        XCTAssertNotNil(received.wait(timeout: 2))
    }
}

final class MemoXSenderServiceTests: XCTestCase {
    func testSenderRetiresOnlyAfterValidMatchingACK() async throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("MemoX/runtime/floattabs-v1.sock")
        let serverDescriptor = try MemoXTestSupport.bindUnixSocket(at: socketURL)
        defer { Darwin.close(serverDescriptor) }
        XCTAssertEqual(Darwin.listen(serverDescriptor, 2), 0)
        let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
        let store = try activeOutbox(stateRoot: stateRoot, socketURL: socketURL)
        let record = try await enqueueFixture(on: store)
        let received = MemoXTestSupport.SocketCaptureBox()
        DispatchQueue.global(qos: .utility).async {
            let clientDescriptor = Darwin.accept(serverDescriptor, nil, nil)
            guard clientDescriptor >= 0 else { received.finish(nil); return }
            defer { Darwin.close(clientDescriptor) }
            let frame = MemoXTestSupport.readFrame(clientDescriptor)
            received.finish(frame)
            guard let frame, let eventID = MemoXTestSupport.eventID(in: frame) else { return }
            MemoXTestSupport.writeFrame(MemoXTestSupport.reply(
                status: "ack", eventID: eventID,
                observationID: "22222222-3333-4444-8555-666666666666", inserted: true
            ), to: clientDescriptor)
        }

        let service = MemoXSenderService(
            outbox: store,
            client: MemoXUnixSocketClient(socketURL: socketURL, timeout: 0.5)
        )
        service.start()
        service.wake()
        try await waitUntilPendingCount(0, in: store)
        await service.stop()

        XCTAssertEqual(MemoXTestSupport.eventID(in: try XCTUnwrap(received.wait(timeout: 1))), record.eventID)
    }

    func testMatchingRejectIsQuarantinedAndLaterEventStillDelivers() async throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("MemoX/runtime/floattabs-v1.sock")
        let serverDescriptor = try MemoXTestSupport.bindUnixSocket(at: socketURL)
        defer { Darwin.close(serverDescriptor) }
        XCTAssertEqual(Darwin.listen(serverDescriptor, 2), 0)
        let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
        let store = try activeOutbox(stateRoot: stateRoot, socketURL: socketURL)
        let first = try await enqueueFixture(on: store, occurredAt: 100)
        let second = try await enqueueFixture(on: store, occurredAt: 200)
        let firstRequest = MemoXTestSupport.SocketCaptureBox()
        let secondRequest = MemoXTestSupport.SocketCaptureBox()
        DispatchQueue.global(qos: .utility).async {
            for (index, capture) in [firstRequest, secondRequest].enumerated() {
                let clientDescriptor = Darwin.accept(serverDescriptor, nil, nil)
                guard clientDescriptor >= 0 else { capture.finish(nil); return }
                defer { Darwin.close(clientDescriptor) }
                let frame = MemoXTestSupport.readFrame(clientDescriptor)
                capture.finish(frame)
                guard let frame, let eventID = MemoXTestSupport.eventID(in: frame) else { return }
                let reply: Data
                if index == 0 {
                    reply = MemoXTestSupport.reply(status: "reject", eventID: eventID, code: "invalid")
                } else {
                    reply = MemoXTestSupport.reply(
                        status: "ack", eventID: eventID,
                        observationID: "22222222-3333-4444-8555-666666666666", inserted: true
                    )
                }
                MemoXTestSupport.writeFrame(reply, to: clientDescriptor)
            }
        }

        let service = MemoXSenderService(
            outbox: store,
            client: MemoXUnixSocketClient(socketURL: socketURL, timeout: 0.5)
        )
        service.start()
        service.wake()
        try await waitUntilPendingCount(0, in: store)
        await service.stop()

        XCTAssertEqual(MemoXTestSupport.eventID(in: try XCTUnwrap(firstRequest.wait(timeout: 1))), first.eventID)
        XCTAssertEqual(MemoXTestSupport.eventID(in: try XCTUnwrap(secondRequest.wait(timeout: 1))), second.eventID)
        let quarantine = try await store.quarantineRecords()
        XCTAssertEqual(quarantine.map(\.eventID), [first.eventID])
    }

    func testLostACKRedeliversSameWireEventAfterRetryCadence() async throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("MemoX/runtime/floattabs-v1.sock")
        let serverDescriptor = try MemoXTestSupport.bindUnixSocket(at: socketURL)
        defer { Darwin.close(serverDescriptor) }
        XCTAssertEqual(Darwin.listen(serverDescriptor, 2), 0)
        let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
        let store = try activeOutbox(stateRoot: stateRoot, socketURL: socketURL)
        let record = try await enqueueFixture(on: store)
        let firstRequest = MemoXTestSupport.SocketCaptureBox()
        let secondRequest = MemoXTestSupport.SocketCaptureBox()
        DispatchQueue.global(qos: .utility).async {
            let firstDescriptor = Darwin.accept(serverDescriptor, nil, nil)
            guard firstDescriptor >= 0 else { firstRequest.finish(nil); return }
            let firstFrame = MemoXTestSupport.readFrame(firstDescriptor)
            firstRequest.finish(firstFrame)
            Darwin.close(firstDescriptor) // The receiver committed but the ACK was lost.

            let secondDescriptor = Darwin.accept(serverDescriptor, nil, nil)
            guard secondDescriptor >= 0 else { secondRequest.finish(nil); return }
            defer { Darwin.close(secondDescriptor) }
            let secondFrame = MemoXTestSupport.readFrame(secondDescriptor)
            secondRequest.finish(secondFrame)
            guard let secondFrame, let eventID = MemoXTestSupport.eventID(in: secondFrame) else { return }
            MemoXTestSupport.writeFrame(MemoXTestSupport.reply(
                status: "ack", eventID: eventID,
                observationID: "22222222-3333-4444-8555-666666666666", inserted: false
            ), to: secondDescriptor)
        }

        let service = MemoXSenderService(
            outbox: store,
            client: MemoXUnixSocketClient(socketURL: socketURL, timeout: 0.5)
        )
        service.start()
        service.wake()
        let firstFrame = try XCTUnwrap(firstRequest.wait(timeout: 2))
        try await waitUntilAttemptCount(1, eventID: record.eventID, in: store)
        let secondFrame = try XCTUnwrap(secondRequest.wait(timeout: 5))
        try await waitUntilPendingCount(0, in: store)
        await service.stop()

        XCTAssertEqual(firstFrame, secondFrame)
        XCTAssertEqual(MemoXTestSupport.eventID(in: secondFrame), record.eventID)
    }

    func testNewCaptureCommitsWhileSenderIsBlockedOnSocket() async throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("MemoX/runtime/floattabs-v1.sock")
        let serverDescriptor = try MemoXTestSupport.bindUnixSocket(at: socketURL)
        defer { Darwin.close(serverDescriptor) }
        XCTAssertEqual(Darwin.listen(serverDescriptor, 2), 0)
        let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
        let store = try activeOutbox(stateRoot: stateRoot, socketURL: socketURL)
        let first = try await enqueueFixture(on: store, occurredAt: 100)
        let firstRequest = MemoXTestSupport.SocketCaptureBox()
        let secondRequest = MemoXTestSupport.SocketCaptureBox()
        let allowFirstReply = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            for (index, capture) in [firstRequest, secondRequest].enumerated() {
                let clientDescriptor = Darwin.accept(serverDescriptor, nil, nil)
                guard clientDescriptor >= 0 else { capture.finish(nil); return }
                defer { Darwin.close(clientDescriptor) }
                MemoXTestSupport.preventSIGPIPE(on: clientDescriptor)
                let frame = MemoXTestSupport.readFrame(clientDescriptor)
                capture.finish(frame)
                guard let frame, let eventID = MemoXTestSupport.eventID(in: frame) else { return }
                if index == 0 { _ = allowFirstReply.wait(timeout: .now() + 2) }
                MemoXTestSupport.writeFrame(MemoXTestSupport.reply(
                    status: "ack", eventID: eventID,
                    observationID: "22222222-3333-4444-8555-666666666666", inserted: true
                ), to: clientDescriptor)
            }
        }

        let service = MemoXSenderService(
            outbox: store,
            client: MemoXUnixSocketClient(socketURL: socketURL, timeout: 1.5)
        )
        service.start()
        service.wake()
        let firstFrame = try XCTUnwrap(firstRequest.wait(timeout: 1))
        let enqueueStart = DispatchTime.now().uptimeNanoseconds
        _ = try await enqueueFixture(on: store, occurredAt: 200)
        service.wake()
        let mainActorResponsive = await MainActor.run { true }
        let enqueueDuration = Double(DispatchTime.now().uptimeNanoseconds - enqueueStart) / 1_000_000_000
        XCTAssertLessThan(enqueueDuration, 0.5)
        XCTAssertTrue(mainActorResponsive)
        let queuedRecords = try await store.pendingRecords()
        XCTAssertEqual(queuedRecords.count, 2)
        allowFirstReply.signal()
        try await waitUntilPendingCount(0, in: store)
        await service.stop()
        XCTAssertNotNil(secondRequest.wait(timeout: 1))
        XCTAssertEqual(first.eventID, MemoXTestSupport.eventID(in: firstFrame))
    }

    private func activeOutbox(stateRoot: URL, socketURL: URL) throws -> MemoXOutboxStore {
        XCTAssertTrue(try MemoXActivationStore(rootURL: stateRoot, receiverSocketURL: socketURL).resolveAndMarkActive())
        return MemoXOutboxStore(rootURL: stateRoot, receiverSocketURL: socketURL)
    }

    private func enqueueFixture(on store: MemoXOutboxStore, occurredAt: TimeInterval = 100) async throws -> MemoXOutboxRecordV1 {
        try await store.commit(
            payloadBytes: Data("{\"version\":1,\"blocks\":[{\"kind\":\"paragraph\",\"text\":\"sender fixture\",\"level\":null}]}".utf8),
            slotID: UUID(), providerNativeEventID: nil,
            occurredAt: Date(timeIntervalSince1970: occurredAt)
        )
    }

    private func waitUntilPendingCount(_ count: Int, in store: MemoXOutboxStore) async throws {
        for _ in 0..<200 {
            if try await store.pendingRecords().count == count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Pending count did not reach \(count)")
    }

    private func waitUntilAttemptCount(_ count: Int, eventID: String, in store: MemoXOutboxStore) async throws {
        for _ in 0..<200 {
            let records = try await store.pendingRecords()
            if records.first(where: { $0.eventID == eventID })?.attemptCount == count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Attempt count did not reach \(count)")
    }
}

@MainActor
final class MemoXCaptureCoordinatorTests: XCTestCase {
    func testMismatchedLatestResultGetsOnlyOneBoundedRetryForExactIdentity() async throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("MemoX/runtime/floattabs-v1.sock")
        let socket = try MemoXTestSupport.bindUnixSocket(at: socketURL)
        defer { Darwin.close(socket) }
        let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
        XCTAssertTrue(try MemoXActivationStore(rootURL: stateRoot, receiverSocketURL: socketURL).resolveAndMarkActive())
        let store = MemoXOutboxStore(rootURL: stateRoot, receiverSocketURL: socketURL)
        let slotID = UUID()
        let identityA = try XCTUnwrap(ChatGPTResponseIdentity(rawValue: "message:completion-a"))
        let identityB = try XCTUnwrap(ChatGPTResponseIdentity(rawValue: "message:completion-b"))
        let extractor = MemoXFakeResponseExtractor(results: [payload(identityB), payload(identityA)])
        let coordinator = MemoXCaptureCoordinator(
            outbox: store,
            sender: MemoXSenderService(outbox: store),
            responseBridgeProvider: { _ in extractor }
        )

        coordinator.handleValidCompletion(
            slotID: slotID,
            responseIdentity: identityA,
            completedAt: Date(timeIntervalSince1970: 100)
        )
        try await waitUntilPendingCount(1, in: store)

        XCTAssertEqual(extractor.extractionCount, 2)
        let pending = try await store.pendingRecords()
        XCTAssertEqual(pending.first?.envelope.providerNativeEventID, identityA.rawValue)
    }

    func testEpochChangeCancelsScheduledSecondExtractionWithoutPersistence() async throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
        let store = MemoXOutboxStore(rootURL: stateRoot, receiverSocketURL: root.appendingPathComponent("missing.sock"))
        let slotID = UUID()
        let identity = try XCTUnwrap(ChatGPTResponseIdentity(rawValue: "message:completion-a"))
        let extractor = MemoXFakeResponseExtractor(results: [nil, payload(identity)])
        let coordinator = MemoXCaptureCoordinator(
            outbox: store,
            sender: MemoXSenderService(outbox: store),
            responseBridgeProvider: { _ in extractor }
        )

        coordinator.handleValidCompletion(slotID: slotID, responseIdentity: identity, completedAt: Date())
        coordinator.observe(.generationStarted, for: slotID)
        try await Task.sleep(for: .milliseconds(350))

        XCTAssertEqual(extractor.extractionCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateRoot.path))
    }

    func testWithoutActivationValidCompletionDoesNotPersistPrivateResponse() async throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
        let store = MemoXOutboxStore(rootURL: stateRoot, receiverSocketURL: root.appendingPathComponent("missing.sock"))
        let slotID = UUID()
        let extractor = MemoXFakeResponseExtractor(results: [payload(nil)])
        let coordinator = MemoXCaptureCoordinator(
            outbox: store,
            sender: MemoXSenderService(outbox: store),
            responseBridgeProvider: { _ in extractor }
        )

        coordinator.handleValidCompletion(slotID: slotID, responseIdentity: nil, completedAt: Date())
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(extractor.extractionCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateRoot.path))
    }

    private func payload(_ identity: ChatGPTResponseIdentity?) -> ChatGPTResponsePayload {
        ChatGPTResponsePayload(
            version: ChatGPTResponsePayload.currentVersion,
            kind: .response,
            requestID: "request-memox-12345678",
            documentToken: "document-memox-12345678",
            responseID: "document-memox-12345678:response-1",
            blocks: [SpeechContentBlock(kind: .paragraph, text: "safe capture fixture", level: nil)],
            responseIdentity: identity
        )
    }

    private func waitUntilPendingCount(_ count: Int, in store: MemoXOutboxStore) async throws {
        for _ in 0..<150 {
            if try await store.pendingRecords().count == count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Pending count did not reach \(count)")
    }
}

final class MemoXPrivacyIsolationTests: XCTestCase {
    func testMemoXIdentityActivationAndResponseAreAbsentFromFloatTabsBackup() async throws {
        let root = try MemoXTestSupport.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let socketURL = root.appendingPathComponent("MemoX/runtime/floattabs-v1.sock")
        let socket = try MemoXTestSupport.bindUnixSocket(at: socketURL)
        defer { Darwin.close(socket) }
        let stateRoot = root.appendingPathComponent("FloatTabs/MemoX")
        XCTAssertTrue(try MemoXActivationStore(rootURL: stateRoot, receiverSocketURL: socketURL).resolveAndMarkActive())
        let store = MemoXOutboxStore(rootURL: stateRoot, receiverSocketURL: socketURL)
        let privateMarker = "private-memox-response-\(UUID().uuidString.lowercased())"
        let payload = try MemoXResponsePayloadV1(blocks: [
            SpeechContentBlock(kind: .paragraph, text: privateMarker, level: nil)
        ]).encodedData()
        let record = try await store.commit(
            payloadBytes: payload, slotID: UUID(), providerNativeEventID: nil,
            occurredAt: Date(timeIntervalSince1970: 100)
        )
        let document = FloatTabsBackupDocument(
            schemaVersion: FloatTabsBackupDocument.currentSchemaVersion,
            createdAt: Date(timeIntervalSince1970: 200),
            sourceAppVersion: "test",
            sourceBuild: "test",
            webAppState: .empty,
            globalPreferences: FloatTabsBackupPreferences(appearanceMode: .system, followPreferredSize: true),
            globalShowHideShortcut: nil
        )
        let backup = try FloatTabsBackupService().encode(document)
        let backupText = String(decoding: backup, as: UTF8.self)

        XCTAssertFalse(backupText.contains(privateMarker))
        XCTAssertFalse(backupText.contains(record.eventID))
        XCTAssertFalse(backupText.contains(record.sourceInstanceID))
        XCTAssertFalse(backupText.contains("activation.json"))
        XCTAssertFalse(backupText.contains("installation.json"))
        XCTAssertFalse(backupText.contains("outbox"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.pendingDirectoryURL.appendingPathComponent("\(record.eventID).json").path))
    }
}

@MainActor
final class MemoXRealReceiverEndToEndTests: XCTestCase {
    func testProductionCaptureOutboxSenderAgainstMergedReceiverWithAckLossAndRestart() async throws {
        let binaryPath = ProcessInfo.processInfo.environment["MEMOX_PR_E_MEMOX_BINARY"]
            ?? Bundle(for: MemoXRealReceiverEndToEndTests.self).object(forInfoDictionaryKey: "MEMOX_PR_E_MEMOX_BINARY") as? String
            ?? ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--memox-pr-e-binary=") })
                .map { String($0.dropFirst("--memox-pr-e-binary=".count)) }
        guard let binaryPath else {
            throw XCTSkip("Set MEMOX_PR_E_MEMOX_BINARY or the test bundle Info.plist key to the isolated MemoX main binary")
        }
        let receiver = try MemoXE2EReceiver(binaryURL: URL(fileURLWithPath: binaryPath))
        defer { try? FileManager.default.removeItem(at: receiver.rootURL) }
        defer { receiver.stop() }
        try receiver.startRuntime()

        let proxyURL = receiver.rootURL.appendingPathComponent("p/sock")
        let ackLossProxy = MemoXE2EAckProxy(
            socketURL: proxyURL,
            receiverSocketURL: receiver.socketURL,
            dropFirstReply: true
        )
        try ackLossProxy.start()
        defer { ackLossProxy.stop() }

        let stateRoot = receiver.rootURL.appendingPathComponent("FloatTabs/MemoX")
        XCTAssertTrue(try MemoXActivationStore(rootURL: stateRoot, receiverSocketURL: proxyURL).resolveAndMarkActive())
        let firstStore = MemoXOutboxStore(rootURL: stateRoot, receiverSocketURL: proxyURL)
        let firstSender = MemoXSenderService(
            outbox: firstStore,
            client: MemoXUnixSocketClient(socketURL: proxyURL, timeout: 1)
        )
        defer { firstSender.requestStop() }
        let firstSlot = UUID(uuidString: "99999999-aaaa-4bbb-8ccc-dddddddddddd")!
        let firstIdentity = try XCTUnwrap(ChatGPTResponseIdentity(stableValue: "e2e-capture-a"))
        let firstContent = "MemoX PR E synthetic response A"
        let firstPayloadBytes = try MemoXResponsePayloadV1(blocks: [
            SpeechContentBlock(kind: .paragraph, text: firstContent, level: nil)
        ]).encodedData()
        _ = makeCoordinator(
            store: firstStore,
            sender: firstSender,
            slotID: firstSlot,
            identity: firstIdentity,
            content: firstContent,
            occurredAt: Date(timeIntervalSince1970: 1_798_821_300)
        )

        let initialReply = try XCTUnwrap(ackLossProxy.waitForReplies(count: 1, timeout: 10)?.first)
        let initialRequest = try XCTUnwrap(ackLossProxy.requestFrames(count: 1, timeout: 1)?.first)
        XCTAssertEqual(initialReply.inserted, true)
        let firstEventID = try XCTUnwrap(MemoXTestSupport.eventID(in: initialRequest))
        let firstRecords = try await firstStore.pendingRecords()
        let firstRecord = try XCTUnwrap(firstRecords.first)
        XCTAssertEqual(firstRecord.eventID, firstEventID)
        XCTAssertEqual(firstRecord.envelope.payloadBase64, firstPayloadBytes.base64EncodedString())
        let wireEnvelope = try JSONDecoder().decode(
            MemoXCaptureEnvelopeV1.self,
            from: Data(initialRequest.dropFirst(4))
        )
        XCTAssertEqual(firstRecord.envelope, wireEnvelope)
        var pendingMode = stat()
        XCTAssertEqual(
            lstat(firstStore.pendingDirectoryURL.appendingPathComponent("\(firstEventID).json").path, &pendingMode),
            0
        )
        XCTAssertEqual(pendingMode.st_mode & 0o777, 0o600)

        let firstReplies = try XCTUnwrap(ackLossProxy.waitForReplies(count: 2, timeout: 8))
        let firstRequests = try XCTUnwrap(ackLossProxy.requestFrames(count: 2, timeout: 1))
        XCTAssertEqual(firstRequests[0], firstRequests[1], "ACK-loss retry must resend the exact committed wire event")
        XCTAssertEqual(firstReplies[0].inserted, true)
        XCTAssertEqual(firstReplies[1].inserted, false)
        XCTAssertEqual(firstReplies[0].eventID, firstReplies[1].eventID)
        XCTAssertEqual(firstReplies[0].observationID, firstReplies[1].observationID)
        try await waitForPendingCount(0, in: firstStore)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: firstStore.pendingDirectoryURL.appendingPathComponent("\(firstEventID).json").path
        ), "A valid later ACK must retire the pending file")
        await firstSender.stop()
        ackLossProxy.stop()

        receiver.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: receiver.socketURL.path))

        let restartedStore = MemoXOutboxStore(rootURL: stateRoot, receiverSocketURL: proxyURL)
        let outageSender = MemoXSenderService(
            outbox: restartedStore,
            client: MemoXUnixSocketClient(socketURL: receiver.socketURL, timeout: 0.5)
        )
        defer { outageSender.requestStop() }
        let secondSlot = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!
        let secondIdentity = try XCTUnwrap(ChatGPTResponseIdentity(stableValue: "e2e-capture-b"))
        let secondContent = "MemoX PR E synthetic response B after outage"
        let secondPayloadBytes = try MemoXResponsePayloadV1(blocks: [
            SpeechContentBlock(kind: .paragraph, text: secondContent, level: nil)
        ]).encodedData()
        _ = makeCoordinator(
            store: restartedStore,
            sender: outageSender,
            slotID: secondSlot,
            identity: secondIdentity,
            content: secondContent,
            occurredAt: Date(timeIntervalSince1970: 1_798_821_400)
        )

        try await waitForPendingCount(1, in: restartedStore)
        try await waitForAttemptCount(1, in: restartedStore)
        let outageRecords = try await restartedStore.pendingRecords()
        let outageRecord = try XCTUnwrap(outageRecords.first)
        XCTAssertEqual(outageRecord.sourceInstanceID, firstRecord.sourceInstanceID)
        XCTAssertNotEqual(outageRecord.eventID, firstRecord.eventID)
        XCTAssertEqual(outageRecord.envelope.payloadBase64, secondPayloadBytes.base64EncodedString())
        await outageSender.stop()

        try receiver.startRuntime()
        let deliveryProxyURL = receiver.rootURL.appendingPathComponent("p/restart.sock")
        let deliveryProxy = MemoXE2EAckProxy(
            socketURL: deliveryProxyURL,
            receiverSocketURL: receiver.socketURL,
            dropFirstReply: false
        )
        try deliveryProxy.start()
        defer { deliveryProxy.stop() }
        let recoverySender = MemoXSenderService(
            outbox: restartedStore,
            client: MemoXUnixSocketClient(socketURL: deliveryProxyURL, timeout: 1)
        )
        defer { recoverySender.requestStop() }
        recoverySender.start()
        recoverySender.wake()

        let recoveryReplies = try XCTUnwrap(deliveryProxy.waitForReplies(count: 1, timeout: 8))
        try await waitForPendingCount(0, in: restartedStore)
        await recoverySender.stop()
        XCTAssertEqual(recoveryReplies[0].eventID, outageRecord.eventID)
        XCTAssertEqual(recoveryReplies[0].inserted, true)

        let databaseCounts = try receiver.databaseCaptureCounts(matching: [firstPayloadBytes, secondPayloadBytes])
        XCTAssertEqual(databaseCounts, "1|2|2|2|2", "Expect one SourceInstance, two provider response objects, two observations, and both exact payloads")
        XCTAssertTrue(try receiver.databaseCheck().contains("integrity=ok"))
        XCTAssertTrue(try receiver.databaseCheck().contains("foreign_key_errors=0"))
    }

    private func makeCoordinator(
        store: MemoXOutboxStore,
        sender: MemoXSenderService,
        slotID: UUID,
        identity: ChatGPTResponseIdentity,
        content: String,
        occurredAt: Date
    ) -> MemoXCaptureCoordinator {
        let response = ChatGPTResponsePayload(
            version: ChatGPTResponsePayload.currentVersion,
            kind: .response,
            requestID: "request-memox-e2e",
            documentToken: "document-memox-e2e",
            responseID: "document-memox-e2e:response-1",
            blocks: [SpeechContentBlock(kind: .paragraph, text: content, level: nil)],
            responseIdentity: identity
        )
        let extractor = MemoXFakeResponseExtractor(results: [response])
        let coordinator = MemoXCaptureCoordinator(
            outbox: store,
            sender: sender,
            responseBridgeProvider: { _ in extractor }
        )
        coordinator.handleValidCompletion(slotID: slotID, responseIdentity: identity, completedAt: occurredAt)
        return coordinator
    }

    private func waitForPendingCount(_ count: Int, in store: MemoXOutboxStore) async throws {
        for _ in 0..<400 {
            if try await store.pendingRecords().count == count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Real receiver E2E pending count did not reach \(count)")
    }

    private func waitForAttemptCount(_ count: Int, in store: MemoXOutboxStore) async throws {
        for _ in 0..<400 {
            if try await store.pendingRecords().first?.attemptCount == count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Real receiver E2E attempt count did not reach \(count)")
    }
}

@MainActor
private final class MemoXFakeResponseExtractor: ChatGPTResponseExtracting {
    private var results: [ChatGPTResponsePayload?]
    private(set) var extractionCount = 0

    init(results: [ChatGPTResponsePayload?]) {
        self.results = results
    }

    func extractLatest(completion: @escaping @MainActor (ChatGPTResponsePayload?) -> Void) {
        extractionCount += 1
        let result = results.isEmpty ? nil : results.removeFirst()
        completion(result)
    }
}

private struct MemoXE2EAck: Equatable {
    let eventID: String?
    let observationID: String?
    let inserted: Bool?
}

/// Test-only bounded Unix-socket forwarder. It lets the real MemoX receiver
/// commit the first request while deliberately losing only that ACK.
private final class MemoXE2EAckProxy: @unchecked Sendable {
    private let socketURL: URL
    private let receiverSocketURL: URL
    private let dropFirstReply: Bool
    private let condition = NSCondition()
    private let queue = DispatchQueue(label: "memox.pr-e.real-receiver-proxy")
    private let finished = DispatchSemaphore(value: 0)
    private var serverDescriptor: Int32 = -1
    private var isStopped = false
    private var requests: [Data] = []
    private var replies: [MemoXE2EAck] = []

    init(socketURL: URL, receiverSocketURL: URL, dropFirstReply: Bool) {
        self.socketURL = socketURL
        self.receiverSocketURL = receiverSocketURL
        self.dropFirstReply = dropFirstReply
    }

    func start() throws {
        serverDescriptor = try MemoXTestSupport.bindUnixSocket(at: socketURL)
        guard Darwin.listen(serverDescriptor, 4) == 0 else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            Darwin.close(serverDescriptor)
            serverDescriptor = -1
            throw error
        }
        queue.async { [self] in
            defer { finished.signal() }
            acceptLoop()
        }
    }

    func stop() {
        condition.lock()
        let shouldStop = !isStopped && serverDescriptor >= 0
        isStopped = true
        let descriptor = serverDescriptor
        condition.unlock()
        guard shouldStop else { return }
        if let wakeDescriptor = try? MemoXTestSupport.connectUnixSocket(at: socketURL) {
            Darwin.close(wakeDescriptor)
        }
        _ = finished.wait(timeout: .now() + 2)
        Darwin.close(descriptor)
        serverDescriptor = -1
        _ = socketURL.path.withCString { Darwin.unlink($0) }
    }

    func requestFrames(count: Int, timeout: TimeInterval) -> [Data]? {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while requests.count < count {
            guard condition.wait(until: deadline) else { return nil }
        }
        return Array(requests.prefix(count))
    }

    func waitForReplies(count: Int, timeout: TimeInterval) -> [MemoXE2EAck]? {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while replies.count < count {
            guard condition.wait(until: deadline) else { return nil }
        }
        return Array(replies.prefix(count))
    }

    private func acceptLoop() {
        while !stopped {
            let client = Darwin.accept(serverDescriptor, nil, nil)
            guard client >= 0 else {
                if errno == EINTR { continue }
                return
            }
            if stopped {
                Darwin.close(client)
                return
            }
            handle(client)
        }
    }

    private var stopped: Bool {
        condition.lock()
        defer { condition.unlock() }
        return isStopped
    }

    private func handle(_ client: Int32) {
        defer { Darwin.close(client) }
        MemoXTestSupport.preventSIGPIPE(on: client)
        guard let request = MemoXTestSupport.readFrame(client) else { return }
        condition.lock()
        requests.append(request)
        condition.broadcast()
        condition.unlock()

        guard let receiver = try? MemoXTestSupport.connectUnixSocket(at: receiverSocketURL) else { return }
        defer { Darwin.close(receiver) }
        MemoXTestSupport.preventSIGPIPE(on: receiver)
        MemoXTestSupport.writeBytes(request, to: receiver)
        guard let replyFrame = MemoXTestSupport.readFrame(receiver),
              replyFrame.count >= 4,
              let object = try? JSONSerialization.jsonObject(with: Data(replyFrame.dropFirst(4))) as? [String: Any] else {
            return
        }
        let ack = MemoXE2EAck(
            eventID: object["event_id"] as? String,
            observationID: object["observation_id"] as? String,
            inserted: object["inserted"] as? Bool
        )
        condition.lock()
        replies.append(ack)
        let shouldDrop = dropFirstReply && replies.count == 1
        condition.broadcast()
        condition.unlock()
        if !shouldDrop {
            MemoXTestSupport.writeBytes(replyFrame, to: client)
        }
    }
}

private final class MemoXE2EReceiver {
    let binaryURL: URL
    let rootURL: URL
    let homeURL: URL
    let configURL: URL
    let storageRootURL: URL
    let socketURL: URL
    private var runtimeProcess: Process?

    init(binaryURL: URL) throws {
        self.binaryURL = binaryURL
        rootURL = try MemoXTestSupport.makeRoot()
        guard chmod(rootURL.path, mode_t(0o700)) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        homeURL = rootURL.appendingPathComponent("h", isDirectory: true)
        configURL = homeURL.appendingPathComponent("Library/Application Support/MemoX/config.json")
        storageRootURL = rootURL.appendingPathComponent("db", isDirectory: true)
        socketURL = homeURL.appendingPathComponent("Library/Application Support/MemoX/runtime/floattabs-v1.sock")
        try FileManager.default.createDirectory(at: homeURL, withIntermediateDirectories: true)

        _ = try runMemoX(["--config", configURL.path, "config", "init", "--storage-root", storageRootURL.path])
        let initialConfig = try Data(contentsOf: configURL)
        guard var config = try JSONSerialization.jsonObject(with: initialConfig) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        config["adapters"] = [[
            "adapter_id": "floattabs",
            "enabled": true,
            "source_instance_id": NSNull(),
            "source_locator": NSNull(),
            "configuration": NSNull()
        ]]
        let configured = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys, .prettyPrinted])
        try configured.write(to: configURL, options: .atomic)
        guard chmod(configURL.path, mode_t(0o600)) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
    }

    func startRuntime() throws {
        guard runtimeProcess == nil else { return }
        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["--config", configURL.path, "runtime", "run"]
        process.environment = ProcessInfo.processInfo.environment.merging(["HOME": homeURL.path]) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        runtimeProcess = process

        let activation = MemoXActivationStore(rootURL: rootURL, receiverSocketURL: socketURL)
        for _ in 0..<200 {
            if !process.isRunning {
                process.waitUntilExit()
                runtimeProcess = nil
                throw NSError(
                    domain: "MemoXE2EReceiver",
                    code: Int(process.terminationStatus),
                    userInfo: [NSLocalizedDescriptionKey: "Isolated PR D runtime exited before binding its socket"]
                )
            }
            if activation.trustedReceiverSocketExists() { return }
            Thread.sleep(forTimeInterval: 0.025)
        }
        stop()
        throw NSError(domain: "MemoXE2EReceiver", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for isolated PR D socket"])
    }

    func stop() {
        guard let process = runtimeProcess else { return }
        if process.isRunning {
            process.interrupt()
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.025)
            }
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        runtimeProcess = nil
    }

    func databaseCheck() throws -> String {
        try runMemoX(["--config", configURL.path, "db", "check"])
    }

    func databaseCaptureCounts(matching payloads: [Data]) throws -> String {
        let matches = payloads.map { "payload_bytes = X'\($0.map { String(format: "%02x", $0) }.joined())'" }
            .joined(separator: " OR ")
        let query = "SELECT (SELECT COUNT(*) FROM source_instances) || '|' || (SELECT COUNT(*) FROM source_objects) || '|' || (SELECT COUNT(*) FROM source_observations) || '|' || (SELECT COUNT(*) FROM raw_payloads) || '|' || (SELECT COUNT(*) FROM raw_payloads WHERE \(matches));"
        return try runTool(
            URL(fileURLWithPath: "/usr/bin/sqlite3"),
            arguments: ["-readonly", storageRootURL.appendingPathComponent("memox.sqlite").path, query]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runMemoX(_ arguments: [String]) throws -> String {
        try runTool(binaryURL, arguments: arguments, home: homeURL)
    }

    private func runTool(_ executableURL: URL, arguments: [String], home: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let home {
            process.environment = ProcessInfo.processInfo.environment.merging(["HOME": home.path]) { _, new in new }
        }
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "MemoXE2EReceiver",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Isolated MemoX fixture command failed: \(String(decoding: stderr + stdout, as: UTF8.self))"]
            )
        }
        return String(decoding: stdout, as: UTF8.self)
    }
}

private enum MemoXTestSupport {
    static func makeRoot() throws -> URL {
        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        let root = URL(fileURLWithPath: "/tmp/mxpe-\(shortID)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    static func bindUnixSocket(at url: URL, mode: mode_t = 0o600) throws -> Int32 {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(url.path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else {
            Darwin.close(descriptor)
            throw CocoaError(.fileWriteInvalidFileName)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            destination.copyBytes(from: pathBytes)
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            Darwin.close(descriptor)
            throw error
        }
        guard chmod(url.path, mode) == 0 else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            Darwin.close(descriptor)
            throw error
        }
        return descriptor
    }

    static func connectUnixSocket(at url: URL) throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(url.path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else {
            Darwin.close(descriptor)
            throw CocoaError(.fileWriteInvalidFileName)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            destination.initializeMemory(as: UInt8.self, repeating: 0)
            destination.copyBytes(from: pathBytes)
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let error = POSIXError(.init(rawValue: errno) ?? .EIO)
            Darwin.close(descriptor)
            throw error
        }
        return descriptor
    }

    static func framed(_ data: Data) -> Data {
        var frame = Data()
        var length = UInt32(data.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(data)
        return frame
    }

    static func eventID(in framedRequest: Data) -> String? {
        guard framedRequest.count >= 4,
              let object = try? JSONSerialization.jsonObject(with: framedRequest.dropFirst(4)) as? [String: Any] else {
            return nil
        }
        return object["event_id"] as? String
    }

    static func reply(
        status: String,
        eventID: String?,
        observationID: String? = nil,
        inserted: Bool? = nil,
        code: String? = nil
    ) -> Data {
        let fields: [String: Any] = [
            "version": 1,
            "status": status,
            "event_id": eventID as Any? ?? NSNull(),
            "observation_id": observationID as Any? ?? NSNull(),
            "inserted": inserted as Any? ?? NSNull(),
            "code": code as Any? ?? NSNull()
        ]
        return (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data()
    }

    static func readFrame(_ descriptor: Int32) -> Data? {
        guard let header = readBytes(4, from: descriptor), header.count == 4 else { return nil }
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0, length < 32 * 1024 * 1024,
              let body = readBytes(Int(length), from: descriptor), body.count == Int(length) else {
            return nil
        }
        return header + body
    }

    static func writeFrame(_ data: Data, to descriptor: Int32) {
        writeBytes(framed(data), to: descriptor)
    }

    static func preventSIGPIPE(on descriptor: Int32) {
        var noSignal: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    }

    static func writeBytes(_ data: Data, to descriptor: Int32) {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { return }
                offset += written
            }
        }
    }

    private static func readBytes(_ count: Int, from descriptor: Int32) -> Data? {
        var data = Data(count: count)
        let didRead = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return count == 0 }
            var offset = 0
            while offset < count {
                let readCount = Darwin.read(descriptor, base.advanced(by: offset), count - offset)
                if readCount < 0 && errno == EINTR { continue }
                guard readCount > 0 else { return false }
                offset += readCount
            }
            return true
        }
        return didRead ? data : nil
    }

    final class SocketCaptureBox: @unchecked Sendable {
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private var value: Data?

        func finish(_ value: Data?) {
            lock.lock()
            self.value = value
            lock.unlock()
            semaphore.signal()
        }

        func wait(timeout: TimeInterval) -> Data? {
            guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
}
