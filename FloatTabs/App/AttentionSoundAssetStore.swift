import AppKit
import Foundation

enum AttentionSoundSourceKind: String, CaseIterable, Equatable, Sendable {
    case system
    case custom
}

struct CustomAttentionSoundAsset: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let managedFileName: String
    let displayName: String

    init(
        id: UUID = UUID(),
        managedFileName: String,
        displayName: String
    ) {
        self.id = id
        self.managedFileName = managedFileName
        self.displayName = displayName
    }
}

enum AttentionSoundPlaybackSource: Equatable, Sendable {
    case system(name: String)
    case custom(url: URL)
}

enum AttentionSoundAssetError: LocalizedError, Equatable, Sendable {
    case notARegularFile
    case fileTooLarge(maxBytes: Int64)
    case cannotDecode
    case invalidDuration
    case durationTooLong(maxSeconds: TimeInterval)
    case importFailed

    var errorDescription: String? {
        switch self {
        case .notARegularFile:
            return "Choose a regular audio file."
        case let .fileTooLarge(maxBytes):
            return "The audio file is too large. Choose a file no larger than \(maxBytes / 1_048_576) MiB."
        case .cannotDecode:
            return "FloatTabs could not decode that audio file. Choose a WAV, AIFF, MP3, or M4A file that macOS can play."
        case .invalidDuration:
            return "The audio file must have a duration greater than zero."
        case let .durationTooLong(maxSeconds):
            return "The audio file is too long. Choose a file no longer than \(Int(maxSeconds)) seconds."
        case .importFailed:
            return "FloatTabs could not copy the audio file into its managed sound library."
        }
    }
}

struct AttentionSoundImportFailure: Equatable, Sendable {
    let displayName: String
    let error: AttentionSoundAssetError
}

struct AttentionSoundBatchImportError: LocalizedError, Equatable, Sendable {
    let failures: [AttentionSoundImportFailure]

    var errorDescription: String? {
        let count = failures.count
        let names = failures.map(\.displayName).joined(separator: ", ")
        return "\(count) file\(count == 1 ? "" : "s") failed to import: \(names)."
    }

    var failureReason: String? {
        failures.map { "\($0.displayName): \($0.error.localizedDescription)" }
            .joined(separator: "\n")
    }
}

/// Owns user-imported Ready alert audio without persisting source URLs. The
/// store is deliberately independent of Preferences and UI so every file
/// operation can be tested against an injected temporary directory.
@MainActor
final class AttentionSoundAssetStore {
    static let maxFileSizeBytes: Int64 = 20 * 1_048_576
    static let maxDuration: TimeInterval = 30

    typealias AudioDurationProbe = @MainActor (URL) -> TimeInterval?

    let managedDirectoryURL: URL

    private let fileManager: FileManager
    private let audioDurationProbe: AudioDurationProbe

    init(
        fileManager: FileManager = .default,
        managedDirectoryURL: URL? = nil,
        audioDurationProbe: @escaping AudioDurationProbe = {
            NSSound(contentsOf: $0, byReference: false)?.duration
        }
    ) {
        self.fileManager = fileManager
        self.managedDirectoryURL = managedDirectoryURL
            ?? Self.defaultManagedDirectory(fileManager: fileManager)
        self.audioDurationProbe = audioDurationProbe
    }

    func importAudio(from sourceURL: URL) throws -> CustomAttentionSoundAsset {
        try validateFile(at: sourceURL)
        try validateAudio(at: sourceURL)

        do {
            try fileManager.createDirectory(
                at: managedDirectoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw AttentionSoundAssetError.importFailed
        }

        var asset: CustomAttentionSoundAsset?
        var managedURL: URL?
        repeat {
            let id = UUID()
            let managedFileName = Self.generatedManagedFileName(
                for: sourceURL,
                id: id
            )
            let candidateURL = managedDirectoryURL.appendingPathComponent(
                managedFileName,
                isDirectory: false
            )
            guard !fileManager.fileExists(atPath: candidateURL.path) else { continue }
            asset = CustomAttentionSoundAsset(
                id: id,
                managedFileName: managedFileName,
                displayName: sourceURL.lastPathComponent
            )
            managedURL = candidateURL
        } while asset == nil
        guard let asset, let managedURL else {
            throw AttentionSoundAssetError.importFailed
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: managedURL)
            do {
                try validateFile(at: managedURL)
                try validateAudio(at: managedURL)
            } catch {
                try? fileManager.removeItem(at: managedURL)
                throw error
            }
        } catch let error as AttentionSoundAssetError {
            throw error
        } catch {
            throw AttentionSoundAssetError.importFailed
        }

        return asset
    }

    func importAudio(
        from sourceURLs: [URL]
    ) -> (assets: [CustomAttentionSoundAsset], failures: [AttentionSoundImportFailure]) {
        var assets: [CustomAttentionSoundAsset] = []
        var failures: [AttentionSoundImportFailure] = []
        for sourceURL in sourceURLs {
            do {
                assets.append(try importAudio(from: sourceURL))
            } catch let error as AttentionSoundAssetError {
                failures.append(
                    AttentionSoundImportFailure(
                        displayName: sourceURL.lastPathComponent,
                        error: error
                    )
                )
            } catch {
                failures.append(
                    AttentionSoundImportFailure(
                        displayName: sourceURL.lastPathComponent,
                        error: .importFailed
                    )
                )
            }
        }
        return (assets, failures)
    }

    /// Returns a safe path inside the managed directory even when the file is
    /// missing, allowing the UI to show Missing and playback to use fallback.
    func url(for asset: CustomAttentionSoundAsset) -> URL? {
        guard Self.isValidManagedFileName(asset.managedFileName) else {
            return nil
        }

        let directory = managedDirectoryURL.standardizedFileURL
        let candidate = directory.appendingPathComponent(
            asset.managedFileName,
            isDirectory: false
        ).standardizedFileURL
        guard candidate.deletingLastPathComponent() == directory else {
            return nil
        }

        let resolved = candidate.resolvingSymlinksInPath()
        guard Self.isInside(directory: directory, url: resolved) else {
            return nil
        }
        return candidate
    }

    func existingURL(for asset: CustomAttentionSoundAsset) -> URL? {
        guard let url = url(for: asset),
              fileManager.fileExists(atPath: url.path),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            return nil
        }
        return url
    }

    func remove(_ asset: CustomAttentionSoundAsset) throws {
        guard let url = url(for: asset),
              fileManager.fileExists(atPath: url.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw AttentionSoundAssetError.importFailed
        }
    }

    private func validateFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw AttentionSoundAssetError.notARegularFile
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch {
            throw AttentionSoundAssetError.notARegularFile
        }
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        guard byteCount >= 0 else {
            throw AttentionSoundAssetError.notARegularFile
        }
        guard byteCount <= Self.maxFileSizeBytes else {
            throw AttentionSoundAssetError.fileTooLarge(maxBytes: Self.maxFileSizeBytes)
        }
    }

    private func validateAudio(at url: URL) throws {
        guard let duration = audioDurationProbe(url) else {
            throw AttentionSoundAssetError.cannotDecode
        }
        guard duration.isFinite, duration > 0 else {
            throw AttentionSoundAssetError.invalidDuration
        }
        guard duration <= Self.maxDuration else {
            throw AttentionSoundAssetError.durationTooLong(maxSeconds: Self.maxDuration)
        }
    }

    private static func defaultManagedDirectory(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("FloatTabs", isDirectory: true)
            .appendingPathComponent("AttentionSounds", isDirectory: true)
    }

    private static func generatedManagedFileName(
        for sourceURL: URL,
        id: UUID
    ) -> String {
        let extensionName = sourceURL.pathExtension.lowercased()
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
        let sanitizedExtension = String(extensionName.map(Character.init))
        guard !sanitizedExtension.isEmpty else {
            return id.uuidString
        }
        return "\(id.uuidString).\(sanitizedExtension)"
    }

    private static func isValidManagedFileName(_ name: String) -> Bool {
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains(".."),
              name == URL(fileURLWithPath: name).lastPathComponent else {
            return false
        }
        return true
    }

    private static func isInside(directory: URL, url: URL) -> Bool {
        let directoryPath = directory.path.hasSuffix("/")
            ? directory.path
            : directory.path + "/"
        return url.path == directory.path || url.path.hasPrefix(directoryPath)
    }
}
