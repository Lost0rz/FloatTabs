import Darwin
import Foundation

/// Serializes local MemoX outbox mutations. Socket work is owned by a separate
/// service and must never run while this actor is occupied.
actor MemoXOutboxStore {
    nonisolated let rootURL: URL
    nonisolated let pendingDirectoryURL: URL
    nonisolated let quarantineDirectoryURL: URL

    private let activationStore: MemoXActivationStore
    private let identityStore: MemoXInstallationIdentityStore

    init(
        rootURL: URL = MemoXActivationStore.defaultRootURL,
        receiverSocketURL: URL = MemoXActivationStore.defaultReceiverSocketURL
    ) {
        let standardizedRoot = rootURL.standardizedFileURL
        self.rootURL = standardizedRoot
        pendingDirectoryURL = standardizedRoot.appendingPathComponent("outbox/pending", isDirectory: true)
        quarantineDirectoryURL = standardizedRoot.appendingPathComponent("outbox/quarantine", isDirectory: true)
        activationStore = MemoXActivationStore(rootURL: standardizedRoot, receiverSocketURL: receiverSocketURL)
        identityStore = MemoXInstallationIdentityStore(rootURL: standardizedRoot)
    }

    /// Returning means the complete record has been written and its directory
    /// synced. Delivery may begin only after this method returns.
    func commit(
        payloadBytes: Data,
        slotID: UUID,
        providerNativeEventID: ChatGPTResponseIdentity?,
        occurredAt: Date
    ) throws -> MemoXOutboxRecordV1 {
        try prepareActiveStore()
        let identity = try identityStore.resolve(durableSourceInstanceIDs: durableSourceInstanceIDHints())
        let envelope = try MemoXCaptureEnvelopeV1.make(
            eventID: UUID(),
            sourceInstanceID: identity,
            slotID: slotID,
            providerNativeEventID: providerNativeEventID,
            occurredAt: occurredAt,
            payloadBytes: payloadBytes
        )
        _ = try envelope.framedRequest()
        let record = MemoXOutboxRecordV1(envelope: envelope, createdAt: Date())
        let pendingURL = recordURL(eventID: record.eventID, in: pendingDirectoryURL)
        let quarantineURL = recordURL(eventID: record.eventID, in: quarantineDirectoryURL)
        guard !Self.pathExists(pendingURL), !Self.pathExists(quarantineURL) else {
            throw MemoXCaptureStoreError.identityConflict
        }
        try MemoXDurableFile.replace(try record.encodedData(), at: pendingURL)
        return record
    }

    func pendingRecords() throws -> [MemoXOutboxRecordV1] {
        try prepareActiveStore()
        try cleanupAbandonedTemporaryFiles(in: pendingDirectoryURL)
        let names = try FileManager.default.contentsOfDirectory(atPath: pendingDirectoryURL.path).sorted()
        var records: [MemoXOutboxRecordV1] = []
        for name in names where name.hasSuffix(".json") {
            let url = pendingDirectoryURL.appendingPathComponent(name, isDirectory: false)
            do {
                let eventID = try Self.eventID(fromFilename: name)
                let data = try readPrivateRegularFile(at: url)
                records.append(try MemoXOutboxRecordV1.decode(data, expectedEventID: eventID))
            } catch {
                try isolateCorruptPendingFile(at: url, originalName: name)
            }
        }
        return records.sorted {
            if $0.createdAt == $1.createdAt { return $0.eventID < $1.eventID }
            return $0.createdAt < $1.createdAt
        }
    }

    func quarantineRecords() throws -> [MemoXOutboxRecordV1] {
        try prepareActiveStore()
        let names = try FileManager.default.contentsOfDirectory(atPath: quarantineDirectoryURL.path).sorted()
        return names.compactMap { name in
            guard name.hasSuffix(".json"),
                  let eventID = try? Self.eventID(fromFilename: name) else { return nil }
            let url = quarantineDirectoryURL.appendingPathComponent(name, isDirectory: false)
            guard let data = try? readPrivateRegularFile(at: url) else { return nil }
            return try? MemoXOutboxRecordV1.decode(data, expectedEventID: eventID)
        }.sorted { $0.eventID < $1.eventID }
    }

    func recordFailure(eventID: String, at date: Date, safeCode: String) throws {
        try prepareActiveStore()
        guard Self.isCanonicalUUID(eventID), Self.isSafeCode(safeCode) else {
            throw MemoXCaptureStoreError.invalidOutboxRecord
        }
        let url = recordURL(eventID: eventID, in: pendingDirectoryURL)
        let data = try readPrivateRegularFile(at: url)
        let current = try MemoXOutboxRecordV1.decode(data, expectedEventID: eventID)
        try MemoXDurableFile.replace(
            try current.recordingFailure(at: date, safeCode: safeCode).encodedData(),
            at: url
        )
    }

    func retireAfterMatchingACK(
        eventID: String,
        expectedEnvelope: MemoXCaptureEnvelopeV1
    ) throws -> Bool {
        try prepareActiveStore()
        guard Self.isCanonicalUUID(eventID) else { return false }
        let url = recordURL(eventID: eventID, in: pendingDirectoryURL)
        guard Self.pathExists(url) else { return false }
        let current = try MemoXOutboxRecordV1.decode(
            readPrivateRegularFile(at: url),
            expectedEventID: eventID
        )
        guard current.envelope == expectedEnvelope else {
            throw MemoXCaptureStoreError.identityConflict
        }
        guard Darwin.unlink(url.path) == 0 else { throw MemoXCaptureStoreError.posix(errno) }
        try MemoXDurableFile.syncDirectory(pendingDirectoryURL)
        return true
    }

    func quarantineAfterMatchingReject(
        eventID: String,
        expectedEnvelope: MemoXCaptureEnvelopeV1
    ) throws -> Bool {
        try prepareActiveStore()
        guard Self.isCanonicalUUID(eventID) else { return false }
        let sourceURL = recordURL(eventID: eventID, in: pendingDirectoryURL)
        let destinationURL = recordURL(eventID: eventID, in: quarantineDirectoryURL)
        guard Self.pathExists(sourceURL) else { return false }
        let current = try MemoXOutboxRecordV1.decode(
            readPrivateRegularFile(at: sourceURL),
            expectedEventID: eventID
        )
        guard current.envelope == expectedEnvelope else {
            throw MemoXCaptureStoreError.identityConflict
        }
        guard !Self.pathExists(destinationURL) else { throw MemoXCaptureStoreError.identityConflict }
        try Self.rename(sourceURL, destinationURL)
        try MemoXDurableFile.syncDirectory(pendingDirectoryURL)
        try MemoXDurableFile.syncDirectory(quarantineDirectoryURL)
        return true
    }

    private func prepareActiveStore() throws {
        guard try activationStore.resolveAndMarkActive() else {
            throw MemoXCaptureStoreError.integrationInactive
        }
        _ = try identityStore.resolve(durableSourceInstanceIDs: durableSourceInstanceIDHints())
    }

    private func durableSourceInstanceIDHints() throws -> [String] {
        var identifiers: [String] = []
        for directory in [pendingDirectoryURL, quarantineDirectoryURL] {
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            for name in names where name.hasSuffix(".json") {
                let url = directory.appendingPathComponent(name, isDirectory: false)
                guard let data = try? readPrivateRegularFile(at: url),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                if let topLevel = object["source_instance_id"] as? String,
                   Self.isCanonicalUUID(topLevel) {
                    identifiers.append(topLevel)
                }
                if let envelope = object["envelope"] as? [String: Any],
                   let nested = envelope["source_instance_id"] as? String,
                   Self.isCanonicalUUID(nested) {
                    identifiers.append(nested)
                }
            }
        }
        return identifiers
    }

    private func readPrivateRegularFile(at url: URL) throws -> Data {
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0 else {
            throw MemoXCaptureStoreError.posix(errno)
        }
        guard (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              metadata.st_uid == geteuid() else {
            throw MemoXCaptureStoreError.unsafeFilesystemPath
        }
        guard chmod(url.path, mode_t(0o600)) == 0 else {
            throw MemoXCaptureStoreError.posix(errno)
        }
        return try Data(contentsOf: url)
    }

    private func isolateCorruptPendingFile(at sourceURL: URL, originalName: String) throws {
        guard Self.pathExists(sourceURL) else { return }
        var metadata = stat()
        guard lstat(sourceURL.path, &metadata) == 0 else {
            throw MemoXCaptureStoreError.unsafeFilesystemPath
        }
        if (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
           metadata.st_uid == geteuid(),
           chmod(sourceURL.path, mode_t(0o600)) != 0 {
            throw MemoXCaptureStoreError.posix(errno)
        }

        let stem = String(originalName.dropLast(".json".count))
        var destinationURL = quarantineDirectoryURL.appendingPathComponent("\(stem).json")
        if Self.pathExists(destinationURL) {
            destinationURL = quarantineDirectoryURL.appendingPathComponent(
                "corrupt-\(UUID().uuidString.lowercased()).json"
            )
        }
        try Self.rename(sourceURL, destinationURL)
        try MemoXDurableFile.syncDirectory(pendingDirectoryURL)
        try MemoXDurableFile.syncDirectory(quarantineDirectoryURL)
    }

    private func cleanupAbandonedTemporaryFiles(in directory: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        var didRemove = false
        for name in names where name.hasPrefix(".memox-tmp-") && name.hasSuffix(".tmp") {
            let url = directory.appendingPathComponent(name, isDirectory: false)
            var metadata = stat()
            guard lstat(url.path, &metadata) == 0 else { continue }
            guard (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
                  metadata.st_uid == geteuid() else { continue }
            guard Darwin.unlink(url.path) == 0 else {
                throw MemoXCaptureStoreError.posix(errno)
            }
            didRemove = true
        }
        if didRemove { try MemoXDurableFile.syncDirectory(directory) }
    }

    private func recordURL(eventID: String, in directory: URL) -> URL {
        directory.appendingPathComponent("\(eventID).json", isDirectory: false)
    }

    private static func eventID(fromFilename name: String) throws -> String {
        guard name.hasSuffix(".json") else { throw MemoXCaptureStoreError.invalidOutboxRecord }
        let eventID = String(name.dropLast(".json".count))
        guard isCanonicalUUID(eventID) else { throw MemoXCaptureStoreError.invalidOutboxRecord }
        return eventID
    }

    private static func isCanonicalUUID(_ value: String) -> Bool {
        guard let uuid = UUID(uuidString: value) else { return false }
        return uuid.uuidString.lowercased() == value
    }

    private static func isSafeCode(_ value: String) -> Bool {
        (1...64).contains(value.utf8.count)
            && value.utf8.allSatisfy {
                ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 95
            }
    }

    private static func pathExists(_ url: URL) -> Bool {
        var metadata = stat()
        return lstat(url.path, &metadata) == 0
    }

    private static func rename(_ sourceURL: URL, _ destinationURL: URL) throws {
        let result = sourceURL.path.withCString { source in
            destinationURL.path.withCString { destination in
                Darwin.rename(source, destination)
            }
        }
        guard result == 0 else { throw MemoXCaptureStoreError.posix(errno) }
    }
}
