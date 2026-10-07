import Darwin
import CoreFoundation
import Foundation

/// Owns the stable source identity for this FloatTabs installation. Callers
/// must first establish that MemoX capture is active.
struct MemoXInstallationIdentityStore: Sendable {
    struct InstallationFile: Codable, Equatable, Sendable {
        let version: Int
        let sourceInstanceID: String

        private enum CodingKeys: String, CodingKey {
            case version
            case sourceInstanceID = "source_instance_id"
        }
    }

    let rootURL: URL

    var installationURL: URL {
        rootURL.appendingPathComponent("installation.json", isDirectory: false)
    }

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    func resolve(durableSourceInstanceIDs: [String]) throws -> UUID {
        let durableIDs = try Self.canonicalIDs(durableSourceInstanceIDs)
        guard durableIDs.count <= 1 else {
            throw MemoXCaptureStoreError.identityConflict
        }

        try MemoXDurableFile.ensurePrivateDirectory(rootURL)
        let persisted = try readPersistedIdentity()
        if let persisted {
            if let durableID = durableIDs.first, durableID != persisted {
                throw MemoXCaptureStoreError.identityConflict
            }
            return persisted
        }

        guard let recoveredID = durableIDs.first else {
            var status = stat()
            if lstat(installationURL.path, &status) == 0 {
                throw MemoXCaptureStoreError.invalidInstallationIdentity
            }
            guard errno == ENOENT else { throw MemoXCaptureStoreError.posix(errno) }
            let newID = UUID()
            try write(newID)
            return newID
        }

        try write(recoveredID)
        return recoveredID
    }

    private func readPersistedIdentity() throws -> UUID? {
        var status = stat()
        guard lstat(installationURL.path, &status) == 0 else {
            guard errno == ENOENT else { throw MemoXCaptureStoreError.posix(errno) }
            return nil
        }
        guard (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              status.st_uid == geteuid() else {
            throw MemoXCaptureStoreError.unsafeFilesystemPath
        }
        guard chmod(installationURL.path, mode_t(0o600)) == 0 else {
            throw MemoXCaptureStoreError.posix(errno)
        }

        do {
            let data = try Data(contentsOf: installationURL)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == ["version", "source_instance_id"],
                  let version = object["version"] as? NSNumber,
                  CFGetTypeID(version) != CFBooleanGetTypeID(),
                  version.intValue == 1,
                  let rawID = object["source_instance_id"] as? String,
                  let identity = UUID(uuidString: rawID),
                  identity.uuidString.lowercased() == rawID else {
                return nil
            }
            return identity
        } catch let error as MemoXCaptureStoreError {
            throw error
        } catch {
            return nil
        }
    }

    private func write(_ identity: UUID) throws {
        let file = InstallationFile(version: 1, sourceInstanceID: identity.uuidString.lowercased())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try MemoXDurableFile.replace(try encoder.encode(file), at: installationURL)
    }

    private static func canonicalIDs(_ values: [String]) throws -> Set<UUID> {
        try Set(values.map { rawValue in
            guard let identity = UUID(uuidString: rawValue),
                  identity.uuidString.lowercased() == rawValue else {
                throw MemoXCaptureStoreError.invalidOutboxRecord
            }
            return identity
        })
    }
}
