import CoreFoundation
import CryptoKit
import Foundation

struct MemoXResponsePayloadV1: Encodable, Equatable, Sendable {
    struct Block: Encodable, Equatable, Sendable {
        let kind: String
        let text: String
        let level: Int?

        private enum CodingKeys: String, CodingKey {
            case kind
            case text
            case level
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(text, forKey: .text)
            if let level {
                try container.encode(level, forKey: .level)
            } else {
                try container.encodeNil(forKey: .level)
            }
        }
    }

    static let version = 1
    static let mediaType = "application/vnd.floattabs.chatgpt-response+json"
    static let encoding = "utf-8"

    let version: Int
    let blocks: [Block]

    init(blocks: [SpeechContentBlock]) {
        version = Self.version
        self.blocks = blocks.map { block in
            Block(kind: block.kind.rawValue, text: block.text, level: block.level)
        }
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

struct MemoXCaptureMetadataV1: Codable, Equatable, Sendable {
    let slotID: String
    let payloadVersion: Int

    private enum CodingKeys: String, CodingKey {
        case slotID = "slot_id"
        case payloadVersion = "payload_version"
    }
}

struct MemoXCaptureEnvelopeV1: Codable, Equatable, Sendable {
    static let maximumRequestFrame = 32 * 1024 * 1024

    let schemaVersion: Int
    let eventID: String
    let adapterID: String
    let sourceInstanceID: String
    let provider: String
    let eventKind: String
    let providerNativeEventID: String?
    let sourceSequence: String?
    let sourceVersion: String?
    let occurredAt: String
    let sourceAssertedAt: String?
    let mediaType: String
    let encoding: String
    let payloadBase64: String
    let payloadSHA256: String
    let metadata: MemoXCaptureMetadataV1

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case eventID = "event_id"
        case adapterID = "adapter_id"
        case sourceInstanceID = "source_instance_id"
        case provider
        case eventKind = "event_kind"
        case providerNativeEventID = "provider_native_event_id"
        case sourceSequence = "source_sequence"
        case sourceVersion = "source_version"
        case occurredAt = "occurred_at"
        case sourceAssertedAt = "source_asserted_at"
        case mediaType = "media_type"
        case encoding
        case payloadBase64 = "payload_base64"
        case payloadSHA256 = "payload_sha256"
        case metadata
    }

    private init(
        schemaVersion: Int,
        eventID: String,
        adapterID: String,
        sourceInstanceID: String,
        provider: String,
        eventKind: String,
        providerNativeEventID: String?,
        sourceSequence: String?,
        sourceVersion: String?,
        occurredAt: String,
        sourceAssertedAt: String?,
        mediaType: String,
        encoding: String,
        payloadBase64: String,
        payloadSHA256: String,
        metadata: MemoXCaptureMetadataV1
    ) {
        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.adapterID = adapterID
        self.sourceInstanceID = sourceInstanceID
        self.provider = provider
        self.eventKind = eventKind
        self.providerNativeEventID = providerNativeEventID
        self.sourceSequence = sourceSequence
        self.sourceVersion = sourceVersion
        self.occurredAt = occurredAt
        self.sourceAssertedAt = sourceAssertedAt
        self.mediaType = mediaType
        self.encoding = encoding
        self.payloadBase64 = payloadBase64
        self.payloadSHA256 = payloadSHA256
        self.metadata = metadata
    }

    static func make(
        eventID: UUID,
        sourceInstanceID: UUID,
        slotID: UUID,
        providerNativeEventID: ChatGPTResponseIdentity?,
        occurredAt: Date,
        payloadBytes: Data
    ) throws -> MemoXCaptureEnvelopeV1 {
        let payload = MemoXResponsePayloadV1.mediaType
        let digest = SHA256.hash(data: payloadBytes)
            .map { String(format: "%02x", $0) }
            .joined()
        return MemoXCaptureEnvelopeV1(
            schemaVersion: 1,
            eventID: eventID.uuidString.lowercased(),
            adapterID: "floattabs",
            sourceInstanceID: sourceInstanceID.uuidString.lowercased(),
            provider: "chatgpt",
            eventKind: "assistant_response_completed",
            providerNativeEventID: providerNativeEventID?.rawValue,
            sourceSequence: nil,
            sourceVersion: nil,
            occurredAt: Self.rfc3339Timestamp(occurredAt),
            sourceAssertedAt: nil,
            mediaType: payload,
            encoding: MemoXResponsePayloadV1.encoding,
            payloadBase64: payloadBytes.base64EncodedString(),
            payloadSHA256: digest,
            metadata: MemoXCaptureMetadataV1(
                slotID: slotID.uuidString.lowercased(),
                payloadVersion: MemoXResponsePayloadV1.version
            )
        )
    }

    func encodedWireJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    func framedRequest() throws -> Data {
        let json = try encodedWireJSON()
        guard !json.isEmpty, json.count < Self.maximumRequestFrame,
              json.count <= Int(UInt32.max) else {
            throw MemoXCaptureModelError.requestTooLarge
        }
        var frame = Data()
        var length = UInt32(json.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(json)
        return frame
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(eventID, forKey: .eventID)
        try container.encode(adapterID, forKey: .adapterID)
        try container.encode(sourceInstanceID, forKey: .sourceInstanceID)
        try container.encode(provider, forKey: .provider)
        try container.encode(eventKind, forKey: .eventKind)
        try Self.encodeNullable(providerNativeEventID, in: &container, forKey: .providerNativeEventID)
        try Self.encodeNullable(sourceSequence, in: &container, forKey: .sourceSequence)
        try Self.encodeNullable(sourceVersion, in: &container, forKey: .sourceVersion)
        try container.encode(occurredAt, forKey: .occurredAt)
        try Self.encodeNullable(sourceAssertedAt, in: &container, forKey: .sourceAssertedAt)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(encoding, forKey: .encoding)
        try container.encode(payloadBase64, forKey: .payloadBase64)
        try container.encode(payloadSHA256, forKey: .payloadSHA256)
        try container.encode(metadata, forKey: .metadata)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            eventID: try container.decode(String.self, forKey: .eventID),
            adapterID: try container.decode(String.self, forKey: .adapterID),
            sourceInstanceID: try container.decode(String.self, forKey: .sourceInstanceID),
            provider: try container.decode(String.self, forKey: .provider),
            eventKind: try container.decode(String.self, forKey: .eventKind),
            providerNativeEventID: try container.decode(String?.self, forKey: .providerNativeEventID),
            sourceSequence: try container.decode(String?.self, forKey: .sourceSequence),
            sourceVersion: try container.decode(String?.self, forKey: .sourceVersion),
            occurredAt: try container.decode(String.self, forKey: .occurredAt),
            sourceAssertedAt: try container.decode(String?.self, forKey: .sourceAssertedAt),
            mediaType: try container.decode(String.self, forKey: .mediaType),
            encoding: try container.decode(String.self, forKey: .encoding),
            payloadBase64: try container.decode(String.self, forKey: .payloadBase64),
            payloadSHA256: try container.decode(String.self, forKey: .payloadSHA256),
            metadata: try container.decode(MemoXCaptureMetadataV1.self, forKey: .metadata)
        )
    }

    private static func encodeNullable(
        _ value: String?,
        in container: inout KeyedEncodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }

    private static func rfc3339Timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

struct MemoXOutboxRecordV1: Codable, Equatable, Sendable {
    let version: Int
    let eventID: String
    let sourceInstanceID: String
    let createdAt: String
    let envelope: MemoXCaptureEnvelopeV1
    let attemptCount: Int
    let lastAttemptAt: String?
    let lastErrorCode: String?

    private enum CodingKeys: String, CodingKey {
        case version
        case eventID = "event_id"
        case sourceInstanceID = "source_instance_id"
        case createdAt = "created_at"
        case envelope
        case attemptCount = "attempt_count"
        case lastAttemptAt = "last_attempt_at"
        case lastErrorCode = "last_error_code"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(eventID, forKey: .eventID)
        try container.encode(sourceInstanceID, forKey: .sourceInstanceID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(envelope, forKey: .envelope)
        try container.encode(attemptCount, forKey: .attemptCount)
        if let lastAttemptAt {
            try container.encode(lastAttemptAt, forKey: .lastAttemptAt)
        } else {
            try container.encodeNil(forKey: .lastAttemptAt)
        }
        if let lastErrorCode {
            try container.encode(lastErrorCode, forKey: .lastErrorCode)
        } else {
            try container.encodeNil(forKey: .lastErrorCode)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decode(Int.self, forKey: .version),
            eventID: try container.decode(String.self, forKey: .eventID),
            sourceInstanceID: try container.decode(String.self, forKey: .sourceInstanceID),
            createdAt: try container.decode(String.self, forKey: .createdAt),
            envelope: try container.decode(MemoXCaptureEnvelopeV1.self, forKey: .envelope),
            attemptCount: try container.decode(Int.self, forKey: .attemptCount),
            lastAttemptAt: try container.decodeIfPresent(String.self, forKey: .lastAttemptAt),
            lastErrorCode: try container.decodeIfPresent(String.self, forKey: .lastErrorCode)
        )
    }

    private init(
        version: Int,
        eventID: String,
        sourceInstanceID: String,
        createdAt: String,
        envelope: MemoXCaptureEnvelopeV1,
        attemptCount: Int,
        lastAttemptAt: String?,
        lastErrorCode: String?
    ) {
        self.version = version
        self.eventID = eventID
        self.sourceInstanceID = sourceInstanceID
        self.createdAt = createdAt
        self.envelope = envelope
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
        self.lastErrorCode = lastErrorCode
    }

    init(envelope: MemoXCaptureEnvelopeV1, createdAt: Date) {
        version = 1
        eventID = envelope.eventID
        sourceInstanceID = envelope.sourceInstanceID
        self.createdAt = Self.rfc3339Timestamp(createdAt)
        self.envelope = envelope
        attemptCount = 0
        lastAttemptAt = nil
        lastErrorCode = nil
    }

    func recordingFailure(at date: Date, safeCode: String) -> MemoXOutboxRecordV1 {
        MemoXOutboxRecordV1(
            version: version,
            eventID: eventID,
            sourceInstanceID: sourceInstanceID,
            createdAt: createdAt,
            envelope: envelope,
            attemptCount: attemptCount + 1,
            lastAttemptAt: Self.rfc3339Timestamp(date),
            lastErrorCode: safeCode
        )
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data, expectedEventID: String) throws -> MemoXOutboxRecordV1 {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == [
                "version", "event_id", "source_instance_id", "created_at", "envelope",
                "attempt_count", "last_attempt_at", "last_error_code"
              ],
              let envelopeObject = object["envelope"] as? [String: Any],
              Set(envelopeObject.keys) == [
                "schema_version", "event_id", "adapter_id", "source_instance_id", "provider",
                "event_kind", "provider_native_event_id", "source_sequence", "source_version",
                "occurred_at", "source_asserted_at", "media_type", "encoding", "payload_base64",
                "payload_sha256", "metadata"
              ],
              let metadataObject = envelopeObject["metadata"] as? [String: Any],
              Set(metadataObject.keys) == ["slot_id", "payload_version"] else {
            throw MemoXCaptureModelError.invalidOutboxRecord
        }
        let record = try JSONDecoder().decode(Self.self, from: data)
        guard record.version == 1,
              Self.isCanonicalUUID(record.eventID),
              record.eventID == expectedEventID,
              Self.isCanonicalUUID(record.sourceInstanceID),
              record.envelope.eventID == record.eventID,
              record.envelope.sourceInstanceID == record.sourceInstanceID,
              record.attemptCount >= 0,
              Self.isRFC3339(record.createdAt),
              record.lastAttemptAt.map(Self.isRFC3339) ?? true,
              record.lastErrorCode.map(Self.isSafeCode) ?? true,
              Self.isValidEnvelope(record.envelope) else {
            throw MemoXCaptureModelError.invalidOutboxRecord
        }
        return record
    }

    private static func rfc3339Timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func isCanonicalUUID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return uuid.uuidString.lowercased() == value
    }

    private static func isValidEnvelope(_ envelope: MemoXCaptureEnvelopeV1) -> Bool {
        guard envelope.schemaVersion == 1,
              Self.isCanonicalUUID(envelope.eventID),
              envelope.adapterID == "floattabs",
              Self.isCanonicalUUID(envelope.sourceInstanceID),
              envelope.provider == "chatgpt",
              envelope.eventKind == "assistant_response_completed",
              envelope.providerNativeEventID.map({ ChatGPTResponseIdentity(rawValue: $0) != nil }) ?? true,
              envelope.sourceSequence == nil,
              envelope.sourceVersion == nil,
              Self.isRFC3339(envelope.occurredAt),
              envelope.sourceAssertedAt == nil,
              envelope.mediaType == MemoXResponsePayloadV1.mediaType,
              envelope.encoding == MemoXResponsePayloadV1.encoding,
              let payload = Data(base64Encoded: envelope.payloadBase64),
              envelope.metadata.payloadVersion == MemoXResponsePayloadV1.version,
              Self.isCanonicalUUID(envelope.metadata.slotID),
              envelope.payloadSHA256.count == 64,
              envelope.payloadSHA256.allSatisfy({ $0.isNumber || "abcdef".contains($0) }) else {
            return false
        }
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return digest == envelope.payloadSHA256
    }

    private static func isRFC3339(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) != nil
    }

    private static func isSafeCode(_ value: String) -> Bool {
        (1...64).contains(value.utf8.count)
            && value.utf8.allSatisfy {
                ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95
            }
    }
}

enum MemoXCaptureReply: Equatable, Sendable {
    case ack(eventID: String, observationID: String, inserted: Bool)
    case reject(eventID: String?, code: String)
    case retry(eventID: String?, code: String)

    private static let exactKeys: Set<String> = [
        "version", "status", "event_id", "observation_id", "inserted", "code"
    ]

    static func parse(json: String) throws -> MemoXCaptureReply {
        try parse(data: Data(json.utf8))
    }

    static func parse(data: Data) throws -> MemoXCaptureReply {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == exactKeys,
              let version = object["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),
              version.intValue == 1,
              let status = object["status"] as? String,
              let rawEventID = nullableString(object["event_id"]),
              let observationID = nullableString(object["observation_id"]),
              let inserted = nullableBool(object["inserted"]),
              let code = nullableString(object["code"]) else {
            throw MemoXCaptureModelError.invalidReply
        }

        switch status {
        case "ack":
            guard let rawEventID,
                  Self.isCanonicalUUID(rawEventID),
                  let observationID,
                  Self.isCanonicalUUID(observationID),
                  let inserted,
                  code == nil else {
                throw MemoXCaptureModelError.invalidReply
            }
            return .ack(eventID: rawEventID, observationID: observationID, inserted: inserted)
        case "reject", "retry":
            guard observationID == nil,
                  inserted == nil,
                  let code,
                  Self.isSafeReplyCode(code),
                  rawEventID == nil || Self.isCanonicalUUID(rawEventID ?? "") else {
                throw MemoXCaptureModelError.invalidReply
            }
            if status == "reject" {
                return .reject(eventID: rawEventID, code: code)
            }
            return .retry(eventID: rawEventID, code: code)
        default:
            throw MemoXCaptureModelError.invalidReply
        }
    }

    private static func nullableString(_ value: Any?) -> String?? {
        guard let value else { return nil }
        if value is NSNull { return .some(nil) }
        guard let string = value as? String else { return nil }
        return .some(string)
    }

    private static func nullableBool(_ value: Any?) -> Bool?? {
        guard let value else { return nil }
        if value is NSNull { return .some(nil) }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return .some(number.boolValue)
    }

    private static func isCanonicalUUID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return uuid.uuidString.lowercased() == value
    }

    private static func isSafeReplyCode(_ value: String) -> Bool {
        (1...64).contains(value.utf8.count)
            && value.utf8.allSatisfy {
                ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95
            }
    }
}

enum MemoXRetryPolicy {
    static func delay(afterFailure attemptCount: Int) -> TimeInterval {
        switch attemptCount {
        case ...1: 2
        case 2: 5
        case 3: 15
        default: 60
        }
    }
}

enum MemoXCaptureModelError: Error {
    case requestTooLarge
    case invalidOutboxRecord
    case invalidReply
}
