import Foundation
import os

enum WebsiteCacheMeasurementState: Equatable {
    case calculating
    case available(Int64)
    case unavailable

    var estimatedBytes: Int64? {
        if case let .available(bytes) = self { return bytes }
        return nil
    }
}

/// Reason a cache-size measurement could not produce a trustworthy number.
/// The UI keeps showing a generic "Unavailable"; only the category below is
/// ever recorded in logs — never website origins, hashes or full paths.
enum WebsiteCacheMeasurementFailure: Equatable, Sendable {
    /// WebKit created, renamed or removed cache entries while the walk was
    /// running. Cache sizes are approximate, so a result that simply omits
    /// the vanished entries is still acceptable.
    case transientMutation
    /// The path left the trusted boundary or traversed a symbolic link.
    case unsafePath
    /// EACCES/EPERM or an equivalent permission failure.
    case permissionDenied
    /// The on-disk structure did not match the approved cache layouts.
    case unsupportedLayout
    /// Any other non-transient IO error.
    case ioFailure
}

/// Internal result of one measurement walk.
enum WebsiteCacheMeasurementOutcome: Equatable, Sendable {
    case available(Int64)
    case unavailable(WebsiteCacheMeasurementFailure)
    case cancelled
}

/// Read-only filesystem operations the measurement walk depends on. The
/// `live` factory talks to the real filesystem; tests inject deterministic
/// failures through the same closures. The seam only moves metadata: every
/// boundary, validator and symlink decision stays inside the measurer.
struct WebsiteCacheFileReading: Sendable {
    struct EntryAttributes: Sendable {
        var isDirectory: Bool?
        var isRegularFile: Bool?
        var isSymbolicLink: Bool?
        var fileAllocatedSize: Int64?
        var fileSize: Int64?
    }

    typealias EntrySink = @Sendable (URL) throws -> Void

    var entryAttributes: @Sendable (URL) throws -> EntryAttributes
    var pathAttributes: @Sendable (URL) throws -> EntryAttributes
    var directoryContents: @Sendable (URL) throws -> [URL]
    var fileExists: @Sendable (String) -> Bool
    /// Streams every descendant of `root` into `sink`. Throws when the walk
    /// itself cannot continue (vanished root, permission, unknown IO) or
    /// `CancellationError` when the surrounding task is cancelled.
    var enumerateDescendants: @Sendable (URL, EntrySink) throws -> Void

    static func live(_ fileManager: FileManager) -> WebsiteCacheFileReading {
        let box = FileManagerSenderBox(fileManager)
        let attributeKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
        ]
        let pathAttributeKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ]
        let readPathAttributes: @Sendable (URL) throws -> EntryAttributes = { url in
            let values = try url.resourceValues(forKeys: pathAttributeKeys)
            return EntryAttributes(
                isDirectory: values.isDirectory,
                isRegularFile: nil,
                isSymbolicLink: values.isSymbolicLink,
                fileAllocatedSize: nil,
                fileSize: nil
            )
        }
        return WebsiteCacheFileReading(
            entryAttributes: { url in
                let values = try url.resourceValues(forKeys: attributeKeys)
                return EntryAttributes(
                    isDirectory: values.isDirectory,
                    isRegularFile: values.isRegularFile,
                    isSymbolicLink: values.isSymbolicLink,
                    fileAllocatedSize: values.fileAllocatedSize.map(Int64.init),
                    fileSize: values.fileSize.map(Int64.init)
                )
            },
            pathAttributes: readPathAttributes,
            directoryContents: { url in
                try box.value.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                    options: []
                )
            },
            fileExists: { path in
                box.value.fileExists(atPath: path)
            },
            enumerateDescendants: { root, sink in
                var walkError: Error?
                guard let enumerator = box.value.enumerator(
                    at: root,
                    includingPropertiesForKeys: Array(attributeKeys),
                    options: [],
                    errorHandler: { _, error in
                        if Task.isCancelled { return false }
                        // A vanished entry or an evicted subdirectory is a
                        // normal WebKit cache mutation: skip it and keep
                        // walking. Anything else stops the walk.
                        if WebsiteCacheSizeMeasurer.failureReason(for: error)
                            == .transientMutation { return true }
                        walkError = error
                        return false
                    }
                ) else {
                    do {
                        _ = try box.value.contentsOfDirectory(
                            at: root,
                            includingPropertiesForKeys: [.isDirectoryKey],
                            options: []
                        )
                    } catch {
                        throw error
                    }
                    throw NSError(
                        domain: NSCocoaErrorDomain,
                        code: NSFileReadUnknownError,
                        userInfo: [
                            NSLocalizedDescriptionKey: "cache root could not be enumerated",
                        ]
                    )
                }
                for case let url as URL in enumerator {
                    if Task.isCancelled { throw CancellationError() }
                    try sink(url)
                }
                if Task.isCancelled { throw CancellationError() }
                if let walkError { throw walkError }
            }
        )
    }
}

private final class FileManagerSenderBox: @unchecked Sendable {
    let value: FileManager

    init(_ value: FileManager) { self.value = value }
}

/// Filesystem scope captured on MainActor and consumed by the detached
/// measurement task. It contains only exact application paths and current
/// Profile UUID directories, never a broad Library root.
struct WebsiteCacheMeasurementScope: @unchecked Sendable {
    let directCacheRoots: [URL]
    let defaultProfileRoots: [URL]
    let customProfileRoots: [URL]
    let allowedCustomProfileIdentifiers: Set<UUID>
    let trustedBoundaryRoots: [URL]

    init(
        directCacheRoots: [URL],
        defaultProfileRoots: [URL],
        customProfileRoots: [URL],
        allowedCustomProfileIdentifiers: Set<UUID>,
        trustedBoundaryRoots: [URL] = []
    ) {
        self.directCacheRoots = directCacheRoots
        self.defaultProfileRoots = defaultProfileRoots
        self.customProfileRoots = customProfileRoots
        self.allowedCustomProfileIdentifiers = allowedCustomProfileIdentifiers
        self.trustedBoundaryRoots = trustedBoundaryRoots
    }

    static func direct(
        _ roots: [URL],
        trustedBoundaryRoots: [URL] = []
    ) -> WebsiteCacheMeasurementScope {
        WebsiteCacheMeasurementScope(
            directCacheRoots: roots,
            defaultProfileRoots: [],
            customProfileRoots: [],
            allowedCustomProfileIdentifiers: [],
            trustedBoundaryRoots: trustedBoundaryRoots
        )
    }
}

/// Read-only size estimator. It never removes, moves or mutates a file. The
/// walk is deliberately limited to exact NetworkCache/CacheStorage roots;
/// WebsiteData and WebsiteDataStore themselves are never measured.
final class WebsiteCacheSizeMeasurer: @unchecked Sendable {
    typealias RootURLsProvider = @MainActor @Sendable () -> [URL]
    typealias ProfileIdentifiersProvider = @MainActor @Sendable () -> Set<UUID>
    typealias ScopeProvider = @MainActor @Sendable () -> WebsiteCacheMeasurementScope
    typealias EnumerationObserver = @Sendable () -> Void

    private final class FileManagerBox: @unchecked Sendable {
        let value: FileManager

        init(_ value: FileManager) { self.value = value }
    }

    private let fileManager: FileManagerBox
    private let reading: WebsiteCacheFileReading
    private let scopeProvider: ScopeProvider
    private let estimateOverride: (@Sendable () -> Int64?)?
    private let enumerationObserver: EnumerationObserver?

    init(
        fileManager: FileManager = .default,
        profileIdentifiersProvider: @escaping ProfileIdentifiersProvider = { [] },
        reading: WebsiteCacheFileReading? = nil,
        enumerationObserver: EnumerationObserver? = nil
    ) {
        self.fileManager = FileManagerBox(fileManager)
        self.reading = reading ?? .live(fileManager)
        scopeProvider = {
            Self.defaultScope(profileIdentifiers: profileIdentifiersProvider())
        }
        estimateOverride = nil
        self.enumerationObserver = enumerationObserver
    }

    init(
        fileManager: FileManager = .default,
        rootURLsProvider: @escaping RootURLsProvider,
        reading: WebsiteCacheFileReading? = nil,
        enumerationObserver: EnumerationObserver? = nil
    ) {
        self.fileManager = FileManagerBox(fileManager)
        self.reading = reading ?? .live(fileManager)
        scopeProvider = {
            let roots = rootURLsProvider()
            return WebsiteCacheMeasurementScope.direct(
                roots,
                trustedBoundaryRoots: roots.compactMap {
                    Self.trustedBoundaryRoot(for: $0)
                }
            )
        }
        estimateOverride = nil
        self.enumerationObserver = enumerationObserver
    }

    init(
        fileManager: FileManager = .default,
        scopeProvider: @escaping ScopeProvider,
        reading: WebsiteCacheFileReading? = nil,
        enumerationObserver: EnumerationObserver? = nil
    ) {
        self.fileManager = FileManagerBox(fileManager)
        self.reading = reading ?? .live(fileManager)
        self.scopeProvider = scopeProvider
        estimateOverride = nil
        self.enumerationObserver = enumerationObserver
    }

    init(
        estimate: @escaping @Sendable () -> Int64?,
        enumerationObserver: EnumerationObserver? = nil
    ) {
        fileManager = FileManagerBox(.default)
        reading = .live(.default)
        scopeProvider = { .direct([]) }
        estimateOverride = estimate
        self.enumerationObserver = enumerationObserver
    }

    /// Runs all filesystem work on a utility task. `nil` means the exact
    /// FloatTabs cache scope could not be identified or inspected safely.
    /// Cancelling the caller's task stops the detached walk instead of
    /// leaving a full-directory scan running in the background.
    @MainActor
    func estimate() async -> Int64? {
        let scope = scopeProvider()
        let fileManager = self.fileManager
        let reading = self.reading
        let estimateOverride = self.estimateOverride
        let observer = enumerationObserver
        let traversal = Task.detached(priority: .utility) { () -> WebsiteCacheMeasurementOutcome in
            observer?()
            if let estimateOverride {
                return estimateOverride().map(WebsiteCacheMeasurementOutcome.available)
                    ?? .unavailable(.ioFailure)
            }
            return Self.measureOutcome(
                fileManager: fileManager.value,
                reading: reading,
                scope: scope
            )
        }
        let outcome = await withTaskCancellationHandler {
            await traversal.value
        } onCancel: {
            traversal.cancel()
        }
        switch outcome {
        case .available(let bytes):
            return bytes
        case .cancelled, .unavailable:
            return nil
        }
    }

    static func defaultRootURLs() -> [URL] {
        defaultScope(profileIdentifiers: []).directCacheRoots
    }

    static func defaultScope(
        profileIdentifiers: Set<UUID>
    ) -> WebsiteCacheMeasurementScope {
        let fileManager = FileManager.default
        guard let library = fileManager.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first,
        let caches = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            return .direct([])
        }

        let bundleID = floatTabsBundleIdentifier
        let cacheNames = ["NetworkCache", "CacheStorage"]
        var directRoots: [URL] = []
        var defaultProfileRoots: [URL] = []
        var customProfileRoots: [URL] = []

        func appendCacheRoots(_ parent: URL) {
            let webKit = parent
                .appendingPathComponent("WebKit", isDirectory: true)
            directRoots.append(contentsOf: cacheNames.map {
                webKit.appendingPathComponent($0, isDirectory: true)
            })
        }

        // Current non-sandbox layout.
        appendCacheRoots(caches.appendingPathComponent(bundleID, isDirectory: true))

        // Possible sandbox layouts. These are still exact app-identifier
        // paths; no container parent is ever enumerated as a whole.
        let containerLibrary = library
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Data/Library", isDirectory: true)
        appendCacheRoots(
            containerLibrary
                .appendingPathComponent("Caches", isDirectory: true)
                .appendingPathComponent(bundleID, isDirectory: true)
        )

        // WebKit has used app-scoped WebKit roots in both sandboxed and
        // non-sandboxed installations. Only their exact cache descendants are
        // eligible, including when they sit below WebsiteData/WebsiteDataStore.
        let webKitAppRoot = library
            .appendingPathComponent("WebKit", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
        directRoots.append(contentsOf: cacheNames.map {
            webKitAppRoot.appendingPathComponent($0, isDirectory: true)
        })
        for dataDirectory in ["WebsiteData", "WebsiteDataStore"] {
            directRoots.append(contentsOf: cacheNames.map {
                webKitAppRoot
                    .appendingPathComponent(dataDirectory, isDirectory: true)
                    .appendingPathComponent($0, isDirectory: true)
            })
        }
        defaultProfileRoots.append(
            webKitAppRoot
                .appendingPathComponent("WebsiteData", isDirectory: true)
                .appendingPathComponent("Default", isDirectory: true)
        )
        customProfileRoots.append(contentsOf: profileIdentifiers.sorted {
            $0.uuidString < $1.uuidString
        }.map { identifier in
            webKitAppRoot
                .appendingPathComponent("WebsiteDataStore", isDirectory: true)
                .appendingPathComponent(identifier.uuidString, isDirectory: true)
        })

        let sandboxWebKitAppRoot = containerLibrary
            .appendingPathComponent("WebKit", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
        directRoots.append(contentsOf: cacheNames.map {
            sandboxWebKitAppRoot.appendingPathComponent($0, isDirectory: true)
        })
        for dataDirectory in ["WebsiteData", "WebsiteDataStore"] {
            directRoots.append(contentsOf: cacheNames.map {
                sandboxWebKitAppRoot
                    .appendingPathComponent(dataDirectory, isDirectory: true)
                    .appendingPathComponent($0, isDirectory: true)
            })
        }
        defaultProfileRoots.append(
            sandboxWebKitAppRoot
                .appendingPathComponent("WebsiteData", isDirectory: true)
                .appendingPathComponent("Default", isDirectory: true)
        )
        customProfileRoots.append(contentsOf: profileIdentifiers.sorted {
            $0.uuidString < $1.uuidString
        }.map { identifier in
            sandboxWebKitAppRoot
                .appendingPathComponent("WebsiteDataStore", isDirectory: true)
                .appendingPathComponent(identifier.uuidString, isDirectory: true)
        })
        return WebsiteCacheMeasurementScope(
            directCacheRoots: directRoots,
            defaultProfileRoots: defaultProfileRoots,
            customProfileRoots: customProfileRoots,
            allowedCustomProfileIdentifiers: profileIdentifiers,
            trustedBoundaryRoots: [library, caches]
        )
    }

    static let floatTabsBundleIdentifier = "com.lost0rz.FloatTabs"

    /// Maps a filesystem error onto the measurement failure taxonomy. Only
    /// errors that WebKit's own cache churn reliably produces (a vanished
    /// entry or an evicted directory) count as transient; everything else
    /// keeps the measurement unavailable so real problems stay visible.
    static func failureReason(
        for error: Error
    ) -> WebsiteCacheMeasurementFailure {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            switch Int32(nsError.code) {
            case ENOENT: return .transientMutation
            case EACCES, EPERM: return .permissionDenied
            default: return .ioFailure
            }
        }
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            // NSFileNoSuchFile (Cocoa code 4) is not exposed to Swift by name.
            case NSFileReadNoSuchFileError, 4:
                return .transientMutation
            case NSFileReadNoPermissionError:
                return .permissionDenied
            default:
                return .ioFailure
            }
        }
        return .ioFailure
    }

    private static let logger = Logger(
        subsystem: floatTabsBundleIdentifier,
        category: "WebsiteCacheSize"
    )

    /// Logs only the failure category and the cache-root category. Never
    /// website origins, hash directory names or full paths.
    private static func logFailure(
        _ failure: WebsiteCacheMeasurementFailure,
        rootKind: String
    ) {
        let reason: String
        switch failure {
        case .transientMutation: reason = "transientMutation"
        case .unsafePath: reason = "unsafePath"
        case .permissionDenied: reason = "permissionDenied"
        case .unsupportedLayout: reason = "unsupportedLayout"
        case .ioFailure: reason = "ioFailure"
        }
        logger.notice(
            "cache size measurement unavailable; root=\(rootKind, privacy: .public); reason=\(reason, privacy: .public)"
        )
    }

    /// Deterministic entry point used by tests to exercise one walk with an
    /// injected filesystem reading. Production reaches this through
    /// `estimate()` on a detached utility task.
    static func measureOutcome(
        fileManager: FileManager,
        reading: WebsiteCacheFileReading,
        scope: WebsiteCacheMeasurementScope
    ) -> WebsiteCacheMeasurementOutcome {
        _ = fileManager
        let allRootsPresent = !scope.directCacheRoots.isEmpty
            || !scope.defaultProfileRoots.isEmpty
            || !scope.customProfileRoots.isEmpty
        guard allRootsPresent, !scope.trustedBoundaryRoots.isEmpty else {
            logFailure(.unsafePath, rootKind: "scope")
            return .unavailable(.unsafePath)
        }

        var total: Int64 = 0
        var seenRoots = Set<String>()

        for root in scope.directCacheRoots {
            if Task.isCancelled { return .cancelled }
            guard let trustedBoundary = trustedBoundary(
                for: root,
                in: scope.trustedBoundaryRoots
            ) else {
                logFailure(.unsafePath, rootKind: "direct")
                return .unavailable(.unsafePath)
            }
            switch measureCacheDirectory(
                reading: reading,
                root: root,
                trustedBoundary: trustedBoundary,
                seenRoots: &seenRoots,
                validator: isApprovedDirectCacheRoot,
                rootKind: "direct"
            ) {
            case .available(let bytes):
                guard add(bytes, to: &total) else {
                    logFailure(.ioFailure, rootKind: "direct")
                    return .unavailable(.ioFailure)
                }
            case .cancelled:
                return .cancelled
            case .unavailable(let failure):
                logFailure(failure, rootKind: "direct")
                return .unavailable(failure)
            }
        }

        for parent in scope.defaultProfileRoots {
            if Task.isCancelled { return .cancelled }
            guard let trustedBoundary = trustedBoundary(
                for: parent,
                in: scope.trustedBoundaryRoots
            ) else {
                logFailure(.unsafePath, rootKind: "defaultProfile")
                return .unavailable(.unsafePath)
            }
            switch discoverDefaultCacheRoots(
                reading: reading,
                parent: parent,
                trustedBoundary: trustedBoundary
            ) {
            case .roots(let nestedRoots):
                for root in nestedRoots {
                    if Task.isCancelled { return .cancelled }
                    switch measureCacheDirectory(
                        reading: reading,
                        root: root,
                        trustedBoundary: trustedBoundary,
                        seenRoots: &seenRoots,
                        validator: { root in
                            isApprovedNestedCacheRoot(root, under: parent)
                        },
                        rootKind: "defaultProfile"
                    ) {
                    case .available(let bytes):
                        guard add(bytes, to: &total) else {
                            logFailure(.ioFailure, rootKind: "defaultProfile")
                            return .unavailable(.ioFailure)
                        }
                    case .cancelled:
                        return .cancelled
                    case .unavailable(let failure):
                        logFailure(failure, rootKind: "defaultProfile")
                        return .unavailable(failure)
                    }
                }
            case .unavailable(let failure):
                logFailure(failure, rootKind: "defaultProfile")
                return .unavailable(failure)
            case .cancelled:
                return .cancelled
            }
        }

        for profileRoot in scope.customProfileRoots {
            if Task.isCancelled { return .cancelled }
            guard let identifier = UUID(uuidString: profileRoot.lastPathComponent),
                  scope.allowedCustomProfileIdentifiers.contains(identifier) else {
                continue
            }
            guard let trustedBoundary = trustedBoundary(
                for: profileRoot,
                in: scope.trustedBoundaryRoots
            ) else {
                logFailure(.unsafePath, rootKind: "customProfile")
                return .unavailable(.unsafePath)
            }
            switch discoverCustomCacheRoots(
                reading: reading,
                profileRoot: profileRoot,
                trustedBoundary: trustedBoundary
            ) {
            case .roots(let nestedRoots):
                for root in nestedRoots {
                    if Task.isCancelled { return .cancelled }
                    switch measureCacheDirectory(
                        reading: reading,
                        root: root,
                        trustedBoundary: trustedBoundary,
                        seenRoots: &seenRoots,
                        validator: { root in
                            isApprovedCustomCacheRoot(root, under: profileRoot)
                        },
                        rootKind: "customProfile"
                    ) {
                    case .available(let bytes):
                        guard add(bytes, to: &total) else {
                            logFailure(.ioFailure, rootKind: "customProfile")
                            return .unavailable(.ioFailure)
                        }
                    case .cancelled:
                        return .cancelled
                    case .unavailable(let failure):
                        logFailure(failure, rootKind: "customProfile")
                        return .unavailable(failure)
                    }
                }
            case .unavailable(let failure):
                logFailure(failure, rootKind: "customProfile")
                return .unavailable(failure)
            case .cancelled:
                return .cancelled
            }
        }
        return .available(total)
    }

    private static let cacheDirectoryNames = ["NetworkCache", "CacheStorage"]

    private enum PathInspection {
        case safe
        case missing
        case unsafe
        case failure(WebsiteCacheMeasurementFailure)
    }

    /// A hard, classifiable failure raised from inside the entry-walk sink.
    private struct TraversalViolation: Error {
        let failure: WebsiteCacheMeasurementFailure

        init(_ failure: WebsiteCacheMeasurementFailure) {
            self.failure = failure
        }
    }

    private static func measureCacheDirectory(
        reading: WebsiteCacheFileReading,
        root: URL,
        trustedBoundary: URL,
        seenRoots: inout Set<String>,
        validator: (URL) -> Bool,
        rootKind: String
    ) -> WebsiteCacheMeasurementOutcome {
        let rawRoot = root.standardizedFileURL
        guard validator(rawRoot) else { return .unavailable(.unsupportedLayout) }
        switch inspectPath(
            reading: reading,
            candidate: rawRoot,
            trustedBoundary: trustedBoundary
        ) {
        case .safe:
            break
        case .missing:
            // A cache root that does not exist contributes zero bytes — a
            // fresh installation simply has nothing on disk yet.
            return .available(0)
        case .unsafe:
            return .unavailable(.unsafePath)
        case .failure(let failure):
            return .unavailable(failure)
        }

        let resolvedRoot = rawRoot.resolvingSymlinksInPath().standardizedFileURL
        guard validator(resolvedRoot) else { return .unavailable(.unsupportedLayout) }
        guard seenRoots.insert(resolvedRoot.path).inserted else { return .available(0) }

        do {
            let rootAttributes = try reading.entryAttributes(resolvedRoot)
            guard rootAttributes.isDirectory == true else {
                return .unavailable(.unsupportedLayout)
            }
        } catch {
            switch failureReason(for: error) {
            case .transientMutation:
                // The discovered root vanished between inspection and the
                // walk. It contributes zero bytes this round.
                return .available(0)
            case .permissionDenied:
                return .unavailable(.permissionDenied)
            default:
                return .unavailable(.ioFailure)
            }
        }

        // WebKit keeps mutating NetworkCache while we walk it. One bounded
        // retry absorbs a walk aborted by directory-level churn; a second
        // abort keeps whatever the retry saw. Cache sizes are approximate —
        // vanished entries may be omitted, never invented.
        final class RunningTotal: @unchecked Sendable {
            private let lock = NSLock()
            private var value: Int64 = 0

            func add(_ size: Int64) -> Bool {
                lock.lock()
                defer { lock.unlock() }
                let (updated, overflowed) = value.addingReportingOverflow(size)
                guard !overflowed else { return false }
                value = updated
                return true
            }

            var current: Int64 {
                lock.lock()
                defer { lock.unlock() }
                return value
            }
        }

        var partialTotal: Int64 = 0
        for _ in 0...1 {
            if Task.isCancelled { return .cancelled }
            let runningTotal = RunningTotal()
            do {
                try reading.enumerateDescendants(resolvedRoot) { url in
                    if Task.isCancelled { throw CancellationError() }
                    let attributes: WebsiteCacheFileReading.EntryAttributes
                    do {
                        attributes = try reading.entryAttributes(url)
                    } catch {
                        // An entry that vanished between enumeration and its
                        // attribute read is skipped; the walk goes on.
                        switch failureReason(for: error) {
                        case .transientMutation:
                            return
                        case .permissionDenied:
                            throw TraversalViolation(.permissionDenied)
                        default:
                            throw TraversalViolation(.ioFailure)
                        }
                    }
                    guard attributes.isSymbolicLink != true else {
                        throw TraversalViolation(.unsafePath)
                    }
                    if attributes.isDirectory == true { return }
                    guard attributes.isRegularFile == true else {
                        throw TraversalViolation(.unsupportedLayout)
                    }
                    guard let size = attributes.fileAllocatedSize ?? attributes.fileSize else {
                        // A racing removal can leave the sizes unreadable on
                        // an otherwise intact entry. Skip, do not fail.
                        return
                    }
                    guard runningTotal.add(size) else {
                        throw TraversalViolation(.ioFailure)
                    }
                }
                return .available(runningTotal.current)
            } catch let violation as TraversalViolation {
                return .unavailable(violation.failure)
            } catch is CancellationError {
                return .cancelled
            } catch {
                switch failureReason(for: error) {
                case .transientMutation:
                    partialTotal = runningTotal.current
                    continue
                case .permissionDenied:
                    return .unavailable(.permissionDenied)
                default:
                    return .unavailable(.ioFailure)
                }
            }
        }
        return .available(partialTotal)
    }

    private static func add(_ value: Int64, to total: inout Int64) -> Bool {
        let (updated, overflowed) = total.addingReportingOverflow(value)
        guard !overflowed else { return false }
        total = updated
        return true
    }

    private enum DiscoveryOutcome {
        case roots([URL])
        case unavailable(WebsiteCacheMeasurementFailure)
        case cancelled
    }

    private enum SafeListingOutcome {
        case directories([URL])
        case unavailable(WebsiteCacheMeasurementFailure)
    }

    private static func discoverDefaultCacheRoots(
        reading: WebsiteCacheFileReading,
        parent: URL,
        trustedBoundary: URL
    ) -> DiscoveryOutcome {
        let rawParent = parent.standardizedFileURL
        guard isApprovedDefaultProfileRoot(rawParent) else {
            return .unavailable(.unsupportedLayout)
        }
        switch inspectPath(
            reading: reading,
            candidate: rawParent,
            trustedBoundary: trustedBoundary
        ) {
        case .missing:
            return .roots([])
        case .unsafe:
            return .unavailable(.unsafePath)
        case .failure(let failure):
            return .unavailable(failure)
        case .safe:
            break
        }
        let resolvedParent = rawParent.resolvingSymlinksInPath().standardizedFileURL
        do {
            let parentAttributes = try reading.entryAttributes(resolvedParent)
            guard parentAttributes.isDirectory == true else {
                return .unavailable(.unsupportedLayout)
            }
        } catch {
            switch failureReason(for: error) {
            case .transientMutation:
                return .roots([])
            case .permissionDenied:
                return .unavailable(.permissionDenied)
            default:
                return .unavailable(.ioFailure)
            }
        }

        switch safeDirectories(
            reading: reading,
            directory: resolvedParent,
            boundary: resolvedParent
        ) {
        case .unavailable(let failure):
            return .unavailable(failure)
        case .directories(let firstLevel):
            var roots: [URL] = []
            for first in firstLevel {
                if Task.isCancelled { return .cancelled }
                switch safeDirectories(
                    reading: reading,
                    directory: first,
                    boundary: resolvedParent
                ) {
                case .unavailable(let failure):
                    return .unavailable(failure)
                case .directories(let secondLevel):
                    for second in secondLevel {
                        for name in cacheDirectoryNames {
                            let candidate = second
                                .appendingPathComponent(name, isDirectory: true)
                            guard isWithin(candidate, resolvedParent) else {
                                return .unavailable(.unsafePath)
                            }
                            roots.append(candidate)
                        }
                    }
                }
            }
            return .roots(roots)
        }
    }

    private static func discoverCustomCacheRoots(
        reading: WebsiteCacheFileReading,
        profileRoot: URL,
        trustedBoundary: URL
    ) -> DiscoveryOutcome {
        let rawProfileRoot = profileRoot.standardizedFileURL
        guard isApprovedCustomProfileRoot(rawProfileRoot) else {
            return .unavailable(.unsupportedLayout)
        }
        switch inspectPath(
            reading: reading,
            candidate: rawProfileRoot,
            trustedBoundary: trustedBoundary
        ) {
        case .missing:
            return .roots([])
        case .unsafe:
            return .unavailable(.unsafePath)
        case .failure(let failure):
            return .unavailable(failure)
        case .safe:
            break
        }
        let resolvedProfileRoot = rawProfileRoot.resolvingSymlinksInPath().standardizedFileURL
        do {
            let profileAttributes = try reading.entryAttributes(resolvedProfileRoot)
            guard profileAttributes.isDirectory == true else {
                return .unavailable(.unsupportedLayout)
            }
        } catch {
            switch failureReason(for: error) {
            case .transientMutation:
                return .roots([])
            case .permissionDenied:
                return .unavailable(.permissionDenied)
            default:
                return .unavailable(.ioFailure)
            }
        }
        return .roots(cacheDirectoryNames.map {
            resolvedProfileRoot.appendingPathComponent($0, isDirectory: true)
        })
    }

    private static func safeDirectories(
        reading: WebsiteCacheFileReading,
        directory: URL,
        boundary: URL
    ) -> SafeListingOutcome {
        let entries: [URL]
        do {
            entries = try reading.directoryContents(directory)
        } catch {
            switch failureReason(for: error) {
            case .transientMutation:
                // The listed directory (or a profile parent) disappeared
                // mid-measurement; this branch contributes nothing.
                return .directories([])
            case .permissionDenied:
                return .unavailable(.permissionDenied)
            default:
                return .unavailable(.ioFailure)
            }
        }

        var result: [URL] = []
        for entry in entries {
            do {
                let values = try reading.entryAttributes(entry)
                guard values.isSymbolicLink != true else {
                    return .unavailable(.unsafePath)
                }
                guard values.isDirectory == true else { continue }
            } catch {
                switch failureReason(for: error) {
                case .transientMutation:
                    continue
                case .permissionDenied:
                    return .unavailable(.permissionDenied)
                default:
                    return .unavailable(.ioFailure)
                }
            }
            let rawEntry = entry.standardizedFileURL
            guard isWithin(rawEntry, boundary) else { return .unavailable(.unsafePath) }
            let resolved = rawEntry.resolvingSymlinksInPath().standardizedFileURL
            guard isWithin(resolved, boundary) else { return .unavailable(.unsafePath) }
            result.append(resolved)
        }
        return .directories(result)
    }

    private static func trustedBoundary(
        for candidate: URL,
        in boundaries: [URL]
    ) -> URL? {
        let candidate = candidate.standardizedFileURL
        return boundaries
            .map { $0.standardizedFileURL }
            .filter { isWithin(candidate, $0) }
            .min { lhs, rhs in
                lhs.pathComponents.count < rhs.pathComponents.count
            }
    }

    private static func trustedBoundaryRoot(for root: URL) -> URL? {
        let components = root.standardizedFileURL.pathComponents
        guard let libraryIndex = components.firstIndex(of: "Library") else {
            return root.deletingLastPathComponent().standardizedFileURL
        }

        var boundary = URL(fileURLWithPath: "/", isDirectory: true)
        for component in components.dropFirst().prefix(max(0, libraryIndex - 1)) {
            boundary.appendPathComponent(component, isDirectory: true)
        }
        boundary.appendPathComponent("Library", isDirectory: true)
        return boundary.standardizedFileURL
    }

    /// Inspects only the known raw path components. It never enumerates a
    /// parent directory and therefore cannot widen the measurement scope.
    private static func inspectPath(
        reading: WebsiteCacheFileReading,
        candidate: URL,
        trustedBoundary: URL
    ) -> PathInspection {
        let rawCandidate = candidate.standardizedFileURL
        let rawBoundary = trustedBoundary.standardizedFileURL
        guard isWithin(rawCandidate, rawBoundary) else { return .unsafe }

        let boundaryComponents = rawBoundary.pathComponents
        let candidateComponents = rawCandidate.pathComponents
        guard boundaryComponents.first == "/",
              candidateComponents.first == "/",
              candidateComponents.count >= boundaryComponents.count,
              Array(candidateComponents.prefix(boundaryComponents.count)) == boundaryComponents
        else { return .unsafe }

        var current = rawBoundary
        var componentsToInspect = [rawBoundary]
        for component in candidateComponents.dropFirst(boundaryComponents.count) {
            current.appendPathComponent(component, isDirectory: true)
            componentsToInspect.append(current)
        }
        for componentURL in componentsToInspect {
            do {
                let values = try reading.pathAttributes(componentURL)
                guard values.isSymbolicLink != true else { return .unsafe }
                guard values.isDirectory == true else {
                    return .failure(.unsupportedLayout)
                }
            } catch {
                switch failureReason(for: error) {
                case .transientMutation:
                    return .missing
                case .permissionDenied:
                    return .failure(.permissionDenied)
                default:
                    return .failure(.ioFailure)
                }
            }
            current = componentURL
        }
        return .safe
    }

    private static func isApprovedDirectCacheRoot(_ root: URL) -> Bool {
        let path = root.path
        let bundleID = "/\(floatTabsBundleIdentifier)/"
        guard path.contains(bundleID),
              cacheDirectoryNames.contains(root.lastPathComponent) else {
            return false
        }

        let approvedSuffixes = [
            "/Library/Caches/\(floatTabsBundleIdentifier)/WebKit/NetworkCache",
            "/Library/Caches/\(floatTabsBundleIdentifier)/WebKit/CacheStorage",
            "/Library/WebKit/\(floatTabsBundleIdentifier)/NetworkCache",
            "/Library/WebKit/\(floatTabsBundleIdentifier)/CacheStorage",
            "/Library/WebKit/\(floatTabsBundleIdentifier)/WebsiteData/NetworkCache",
            "/Library/WebKit/\(floatTabsBundleIdentifier)/WebsiteData/CacheStorage",
            "/Library/WebKit/\(floatTabsBundleIdentifier)/WebsiteDataStore/NetworkCache",
            "/Library/WebKit/\(floatTabsBundleIdentifier)/WebsiteDataStore/CacheStorage",
            "/Library/Containers/\(floatTabsBundleIdentifier)/Data/Library/Caches/\(floatTabsBundleIdentifier)/WebKit/NetworkCache",
            "/Library/Containers/\(floatTabsBundleIdentifier)/Data/Library/Caches/\(floatTabsBundleIdentifier)/WebKit/CacheStorage",
            "/Library/Containers/\(floatTabsBundleIdentifier)/Data/Library/WebKit/\(floatTabsBundleIdentifier)/NetworkCache",
            "/Library/Containers/\(floatTabsBundleIdentifier)/Data/Library/WebKit/\(floatTabsBundleIdentifier)/CacheStorage",
            "/Library/Containers/\(floatTabsBundleIdentifier)/Data/Library/WebKit/\(floatTabsBundleIdentifier)/WebsiteData/NetworkCache",
            "/Library/Containers/\(floatTabsBundleIdentifier)/Data/Library/WebKit/\(floatTabsBundleIdentifier)/WebsiteData/CacheStorage",
            "/Library/Containers/\(floatTabsBundleIdentifier)/Data/Library/WebKit/\(floatTabsBundleIdentifier)/WebsiteDataStore/NetworkCache",
            "/Library/Containers/\(floatTabsBundleIdentifier)/Data/Library/WebKit/\(floatTabsBundleIdentifier)/WebsiteDataStore/CacheStorage",
        ]
        return approvedSuffixes.contains { path.hasSuffix($0) }
    }

    private static func isApprovedDefaultProfileRoot(_ root: URL) -> Bool {
        let path = root.path
        let suffixes = [
            "/Library/WebKit/\(floatTabsBundleIdentifier)/WebsiteData/Default",
            "/Library/Containers/\(floatTabsBundleIdentifier)/Data/Library/WebKit/\(floatTabsBundleIdentifier)/WebsiteData/Default",
        ]
        return suffixes.contains { path.hasSuffix($0) }
    }

    private static func isApprovedNestedCacheRoot(_ root: URL, under parent: URL) -> Bool {
        guard cacheDirectoryNames.contains(root.lastPathComponent),
              isWithin(root, parent) else { return false }
        let parentComponents = parent.standardizedFileURL.pathComponents
        let rootComponents = root.standardizedFileURL.pathComponents
        guard rootComponents.count == parentComponents.count + 3 else { return false }
        return Array(rootComponents.dropLast(1).dropFirst(parentComponents.count))
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func isApprovedCustomProfileRoot(_ root: URL) -> Bool {
        let path = root.path.lowercased()
        let identifier = root.lastPathComponent.lowercased()
        let suffixes = [
            "/library/webkit/\(floatTabsBundleIdentifier.lowercased())/websitedatastore/",
            "/library/containers/\(floatTabsBundleIdentifier.lowercased())/data/library/webkit/\(floatTabsBundleIdentifier.lowercased())/websitedatastore/",
        ]
        return suffixes.contains { path.hasSuffix("\($0)\(identifier)") }
            && UUID(uuidString: identifier) != nil
    }

    private static func isApprovedCustomCacheRoot(_ root: URL, under profileRoot: URL) -> Bool {
        cacheDirectoryNames.contains(root.lastPathComponent)
            && isWithin(root, profileRoot)
            && root.standardizedFileURL.pathComponents.count
                == profileRoot.standardizedFileURL.pathComponents.count + 1
    }

    private static func isWithin(_ candidate: URL, _ boundary: URL) -> Bool {
        let candidateComponents = candidate.standardizedFileURL.pathComponents
        let boundaryComponents = boundary.standardizedFileURL.pathComponents
        guard candidateComponents.count >= boundaryComponents.count else { return false }
        return Array(candidateComponents.prefix(boundaryComponents.count)) == boundaryComponents
    }
}
