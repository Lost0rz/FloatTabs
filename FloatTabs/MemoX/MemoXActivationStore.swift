import Darwin
import CoreFoundation
import Foundation

struct MemoXActivationStore: Sendable {
    struct Marker: Codable, Equatable, Sendable {
        let version: Int
        let active: Bool

        static let current = Marker(version: 1, active: true)
    }

    let rootURL: URL
    let receiverSocketURL: URL
    let effectiveUID: uid_t

    var activationURL: URL {
        rootURL.appendingPathComponent("activation.json", isDirectory: false)
    }

    init(
        rootURL: URL,
        receiverSocketURL: URL,
        effectiveUID: uid_t = geteuid()
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.receiverSocketURL = receiverSocketURL.standardizedFileURL
        self.effectiveUID = effectiveUID
    }

    static var defaultRootURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/FloatTabs/MemoX", isDirectory: true)
    }

    static var defaultReceiverSocketURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/MemoX/runtime/floattabs-v1.sock")
    }

    /// Resolves opt-in evidence and durably records first activation. It does
    /// not create the state root when no activation evidence exists.
    func resolveAndMarkActive() throws -> Bool {
        let marked = try hasValidActivationMarker()
        let outboxEvidence = try hasOutboxEvidence()
        let socketTrusted = trustedReceiverSocketExists()
        guard marked || outboxEvidence || socketTrusted else { return false }

        try Self.ensureStateDirectories(rootURL)
        if !marked {
            try MemoXDurableFile.replace(
                Data(Self.encodeMarker().utf8),
                at: activationURL
            )
        }
        return true
    }

    func trustedReceiverSocketExists() -> Bool {
        var status = stat()
        guard lstat(receiverSocketURL.path, &status) == 0,
              (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFSOCK),
              status.st_uid == effectiveUID,
              status.st_mode & 0o077 == 0 else {
            return false
        }
        return true
    }

    static func ensureStateDirectories(_ rootURL: URL) throws {
        let root = rootURL.standardizedFileURL
        let floatTabsDirectory = root.deletingLastPathComponent()
        let outboxDirectory = root.appendingPathComponent("outbox", isDirectory: true)
        let pendingDirectory = outboxDirectory.appendingPathComponent("pending", isDirectory: true)
        let quarantineDirectory = outboxDirectory.appendingPathComponent("quarantine", isDirectory: true)
        for directory in [floatTabsDirectory, root, outboxDirectory, pendingDirectory, quarantineDirectory] {
            try MemoXDurableFile.ensurePrivateDirectory(directory)
        }
    }

    private func hasValidActivationMarker() throws -> Bool {
        guard let metadata = Self.lstatIfPresent(activationURL) else { return false }
        guard (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              metadata.st_uid == effectiveUID else {
            return false
        }
        do {
            let data = try Data(contentsOf: activationURL)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == ["active", "version"],
                  let version = object["version"] as? NSNumber,
                  CFGetTypeID(version) != CFBooleanGetTypeID(),
                  version.intValue == 1,
                  let active = object["active"] as? NSNumber,
                  CFGetTypeID(active) == CFBooleanGetTypeID(),
                  active.boolValue else {
                return false
            }
            let marker = try JSONDecoder().decode(Marker.self, from: data)
            return marker == .current
        } catch {
            return false
        }
    }

    private func hasOutboxEvidence() throws -> Bool {
        let outbox = rootURL.appendingPathComponent("outbox", isDirectory: true)
        for name in ["pending", "quarantine"] {
            let directory = outbox.appendingPathComponent(name, isDirectory: true)
            guard let metadata = Self.lstatIfPresent(directory) else { continue }
            guard (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  metadata.st_uid == effectiveUID else {
                continue
            }
            let children = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            if !children.isEmpty { return true }
        }
        return false
    }

    private static func encodeMarker() -> String {
        "{\"active\":true,\"version\":1}"
    }

    private static func lstatIfPresent(_ url: URL) -> stat? {
        var status = stat()
        guard lstat(url.path, &status) == 0 else { return nil }
        return status
    }
}

enum MemoXDurableFile {
    enum Phase: Equatable, Sendable {
        case temporaryCreated
        case dataWritten
        case fileSynced
        case fullySynced
        case renamed
        case directorySynced
    }

    static func replace(
        _ data: Data,
        at destinationURL: URL,
        phaseObserver: (@Sendable (Phase) throws -> Void)? = nil
    ) throws {
        let directoryURL = destinationURL.deletingLastPathComponent().standardizedFileURL
        try ensurePrivateDirectory(directoryURL)
        let temporaryURL = directoryURL.appendingPathComponent(
            ".memox-tmp-\(UUID().uuidString.lowercased()).tmp",
            isDirectory: false
        )
        let descriptor = temporaryURL.path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, mode_t(0o600))
        }
        guard descriptor >= 0 else { throw MemoXCaptureStoreError.posix(errno) }
        var fileIsOpen = true
        var temporaryIsPresent = true
        defer {
            if fileIsOpen { Darwin.close(descriptor) }
            if temporaryIsPresent { _ = temporaryURL.path.withCString { Darwin.unlink($0) } }
        }

        try phaseObserver?(.temporaryCreated)
        try writeAll(data, to: descriptor)
        guard fchmod(descriptor, mode_t(0o600)) == 0 else {
            throw MemoXCaptureStoreError.posix(errno)
        }
        try phaseObserver?(.dataWritten)
        guard fsync(descriptor) == 0 else { throw MemoXCaptureStoreError.posix(errno) }
        try phaseObserver?(.fileSynced)
        guard fcntl(descriptor, F_FULLFSYNC) == 0 else {
            throw MemoXCaptureStoreError.posix(errno)
        }
        try phaseObserver?(.fullySynced)
        guard Darwin.close(descriptor) == 0 else { throw MemoXCaptureStoreError.posix(errno) }
        fileIsOpen = false

        let renameResult = temporaryURL.path.withCString { source in
            destinationURL.path.withCString { destination in
                Darwin.rename(source, destination)
            }
        }
        guard renameResult == 0 else { throw MemoXCaptureStoreError.posix(errno) }
        temporaryIsPresent = false
        try phaseObserver?(.renamed)
        try syncDirectory(directoryURL)
        try phaseObserver?(.directorySynced)
    }

    static func ensurePrivateDirectory(_ url: URL) throws {
        let path = url.standardizedFileURL.path
        var status = stat()
        if lstat(path, &status) == 0 {
            guard (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
                  status.st_uid == geteuid() else {
                throw MemoXCaptureStoreError.unsafeFilesystemPath
            }
            guard chmod(path, mode_t(0o700)) == 0 else {
                throw MemoXCaptureStoreError.posix(errno)
            }
            return
        }
        guard errno == ENOENT else { throw MemoXCaptureStoreError.posix(errno) }
        guard mkdir(path, mode_t(0o700)) == 0 else { throw MemoXCaptureStoreError.posix(errno) }
        var createdStatus = stat()
        guard lstat(path, &createdStatus) == 0,
              (createdStatus.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              createdStatus.st_uid == geteuid(),
              chmod(path, mode_t(0o700)) == 0 else {
            throw MemoXCaptureStoreError.unsafeFilesystemPath
        }
        try syncDirectory(url.deletingLastPathComponent())
    }

    static func syncDirectory(_ url: URL) throws {
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC) }
        guard descriptor >= 0 else { throw MemoXCaptureStoreError.posix(errno) }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw MemoXCaptureStoreError.posix(errno) }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if written < 0 {
                    if errno == EINTR { continue }
                    throw MemoXCaptureStoreError.posix(errno)
                }
                guard written > 0 else { throw MemoXCaptureStoreError.posix(EIO) }
                offset += written
            }
        }
    }
}

enum MemoXCaptureStoreError: Error, Equatable {
    case posix(Int32)
    case unsafeFilesystemPath
    case invalidActivationState
    case identityConflict
    case invalidInstallationIdentity
    case invalidOutboxRecord
    case integrationInactive
}
