import Foundation
import OSLog

enum RuntimeDiagnosticExportError: Error, Equatable, Sendable {
    case writerUnavailable
    case writerDisabled
    case encode
    case write
    case io(String)

    var diagnosticCategory: String {
        switch self {
        case .writerUnavailable: return "writer_unavailable"
        case .writerDisabled: return "writer_disabled"
        case .encode: return "encode"
        case .write: return "write"
        case let .io(category): return category
        }
    }
}

protocol RuntimeDiagnosticWriting: AnyObject {
    func enqueue(_ event: RuntimeDiagnosticEvent)

    func exportRecent(
        metadata: RuntimeDiagnosticEvent,
        to destination: URL,
        completion: @escaping @Sendable (Result<Void, RuntimeDiagnosticExportError>) -> Void
    )

    func requestFinalFlush(
        timeout: TimeInterval,
        completion: @escaping @Sendable () -> Void
    )
}

final class RuntimeDiagnosticWriter: RuntimeDiagnosticWriting, @unchecked Sendable {
    typealias DateProvider = () -> Date
    typealias FlushObserver = @Sendable () -> Void

    private struct ManagedRuntimeSegment {
        let url: URL
        let dateKey: String
        let index: Int
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("FloatTabs", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
    }

    private let directory: URL
    private let fileManager: FileManager
    private let maxSegmentBytes: UInt64
    private let maxSegments: Int
    private let retention: TimeInterval
    private let dateProvider: DateProvider
    private let debounceInterval: TimeInterval
    private let flushObserver: FlushObserver?
    private let queue = DispatchQueue(
        label: "com.lost0rz.FloatTabs.runtime-diagnostics-writer",
        qos: .utility
    )
    private let fallbackLogger = Logger(
        subsystem: "com.lost0rz.FloatTabs",
        category: "RuntimeDiagnosticsWriter"
    )

    private var currentFileURL: URL?
    private var currentFileHandle: FileHandle?
    private var currentFileSize: UInt64 = 0
    private var currentSegmentIndex = 1
    private var currentDateKey: String?
    private var bufferedLines: [Data] = []
    private var bufferedBytes = 0
    private var delayedFlushGeneration: UInt64 = 0
    private var delayedFlushWorkItem: DispatchWorkItem?
    private var isDisabled = false
    private var hasReportedFailure = false

    init(
        directory: URL,
        fileManager: FileManager = .default,
        maxSegmentBytes: UInt64 = 10 * 1024 * 1024,
        maxSegments: Int = 10,
        retention: TimeInterval = 7 * 24 * 60 * 60,
        dateProvider: @escaping DateProvider = Date.init,
        debounceInterval: TimeInterval = 1.5,
        flushObserver: FlushObserver? = nil
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.maxSegmentBytes = max(1, maxSegmentBytes)
        self.maxSegments = max(1, maxSegments)
        self.retention = max(0, retention)
        self.dateProvider = dateProvider
        self.debounceInterval = max(0, debounceInterval)
        self.flushObserver = flushObserver
    }

    func exportRecent(
        metadata: RuntimeDiagnosticEvent,
        to destination: URL,
        completion: @escaping @Sendable (Result<Void, RuntimeDiagnosticExportError>) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else {
                completion(.failure(.writerUnavailable))
                return
            }
            guard !self.isDisabled else {
                completion(.failure(.writerDisabled))
                return
            }

            self.cancelDelayedFlush()
            self.flushBuffer()
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                var output = Data()

                let files = (try? self.fileManager.contentsOfDirectory(
                    at: self.directory,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                )) ?? []
                let destinationURL = destination.standardizedFileURL
                let logFiles = files.compactMap { file -> ManagedRuntimeSegment? in
                    guard file.standardizedFileURL != destinationURL else { return nil }
                    return Self.managedRuntimeSegment(
                        for: file,
                        fileManager: self.fileManager
                    )
                }.sorted { lhs, rhs in
                        let lhsDate = (try? lhs.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                            ?? nil
                        let rhsDate = (try? rhs.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                            ?? nil
                        let lhsDateValue = lhsDate ?? .distantPast
                        let rhsDateValue = rhsDate ?? .distantPast
                        if lhsDateValue != rhsDateValue {
                            return lhsDateValue < rhsDateValue
                        }
                        return lhs.url.lastPathComponent < rhs.url.lastPathComponent
                    }

                for segment in logFiles {
                    output.append(try Data(contentsOf: segment.url))
                }

                output.append(try encoder.encode(
                    RuntimeDiagnosticPrivacy.sanitizedEvent(metadata)
                ))
                output.append(0x0A)

                let parent = destination.deletingLastPathComponent()
                try self.fileManager.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
                )
                try output.write(to: destination, options: .atomic)
                try self.fileManager.setAttributes(
                    [.posixPermissions: NSNumber(value: Int16(0o600))],
                    ofItemAtPath: destination.path
                )
                completion(.success(()))
            } catch {
                completion(.failure(.io(Self.errorCategory(error))))
            }
        }
    }

    func enqueue(_ event: RuntimeDiagnosticEvent) {
        let event = RuntimeDiagnosticPrivacy.sanitizedEvent(event)
        queue.async { [weak self] in
            guard let self, !self.isDisabled else { return }
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                var line = try encoder.encode(event)
                line.append(0x0A)
                self.bufferedLines.append(line)
                self.bufferedBytes += line.count

                let requiresImmediateFlush = self.bufferedBytes >= 64 * 1024
                    || event.level == .warning
                    || event.level == .error
                    || event.level == .fault
                if requiresImmediateFlush {
                    self.cancelDelayedFlush()
                    self.flushBuffer()
                } else {
                    self.scheduleDelayedFlushIfNeeded()
                }
            } catch {
                self.disableAfterFailure("encode", error: error)
            }
        }
    }

    func requestFinalFlush(
        timeout: TimeInterval,
        completion: @escaping @Sendable () -> Void
    ) {
        let gate = CompletionGate(completion: completion)
        queue.async { [weak self] in
            guard let self else {
                gate.finish()
                return
            }
            self.cancelDelayedFlush()
            if !self.isDisabled {
                self.flushBuffer()
                self.pruneFiles(now: self.dateProvider())
            }
            self.closeCurrentFile()
            gate.finish()
        }

        let boundedTimeout = max(0, timeout)
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + boundedTimeout
        ) {
            gate.finish()
        }
    }

    private func flushBuffer() {
        guard !bufferedLines.isEmpty, !isDisabled else { return }
        do {
            for line in bufferedLines {
                try appendLine(line)
            }
            try currentFileHandle?.synchronize()
            bufferedLines.removeAll(keepingCapacity: true)
            bufferedBytes = 0
            pruneFiles(now: dateProvider())
            flushObserver?()
        } catch {
            disableAfterFailure("write", error: error)
        }
    }

    private func scheduleDelayedFlushIfNeeded() {
        guard !isDisabled,
              !bufferedLines.isEmpty,
              delayedFlushWorkItem == nil else { return }

        delayedFlushGeneration &+= 1
        let generation = delayedFlushGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.delayedFlushGeneration == generation else { return }
            self.delayedFlushWorkItem = nil
            guard !self.isDisabled else { return }
            self.flushBuffer()
        }
        delayedFlushWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func cancelDelayedFlush() {
        delayedFlushGeneration &+= 1
        delayedFlushWorkItem?.cancel()
        delayedFlushWorkItem = nil
    }

    private func appendLine(_ line: Data) throws {
        try ensureCurrentFile()
        if currentFileSize > 0,
           currentFileSize + UInt64(line.count) > maxSegmentBytes {
            closeCurrentFile()
            currentSegmentIndex += 1
            try ensureCurrentFile()
        }

        guard let currentFileHandle else {
            throw CocoaError(.fileNoSuchFile)
        }
        try currentFileHandle.seekToEnd()
        try currentFileHandle.write(contentsOf: line)
        currentFileSize += UInt64(line.count)
    }

    private func ensureCurrentFile() throws {
        let dateKey = Self.dateKey(dateProvider())
        if currentDateKey != dateKey {
            closeCurrentFile()
            currentDateKey = dateKey
            currentSegmentIndex = nextSegmentIndex(for: dateKey)
        }

        if currentFileHandle != nil { return }

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        let filename = String(
            format: "runtime-%@-%03d.jsonl",
            dateKey,
            currentSegmentIndex
        )
        let url = directory.appendingPathComponent(filename)
        if !fileManager.fileExists(atPath: url.path) {
            guard fileManager.createFile(
                atPath: url.path,
                contents: nil,
                attributes: [.posixPermissions: NSNumber(value: Int16(0o600))]
            ) else {
                throw CocoaError(.fileNoSuchFile)
            }
        }
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try handle.seekToEnd()
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        currentFileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        currentFileURL = url
        currentFileHandle = handle
    }

    private func nextSegmentIndex(for dateKey: String) -> Int {
        let segments = ((try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []).compactMap { url in
            Self.managedRuntimeSegment(for: url, fileManager: fileManager)
        }.filter { $0.dateKey == dateKey }
        guard let latest = segments.sorted(by: { lhs, rhs in
            if lhs.index != rhs.index {
                return lhs.index > rhs.index
            }
            return lhs.url.lastPathComponent < rhs.url.lastPathComponent
        }).first else { return 1 }

        let latestSize = (try? fileManager.attributesOfItem(atPath: latest.url.path))?[.size]
            as? NSNumber
        return latestSize?.uint64Value ?? 0 >= maxSegmentBytes ? latest.index + 1 : latest.index
    }

    private func pruneFiles(now: Date) {
        let files = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        )) ?? []
        let managedFiles = files.compactMap { file in
            Self.managedRuntimeSegment(for: file, fileManager: fileManager)
        }
        let currentURL = currentFileURL?.standardizedFileURL

        let cutoff = now.addingTimeInterval(-retention)
        for segment in managedFiles {
            let date = (try? segment.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? nil
            if let date, date < cutoff, segment.url.standardizedFileURL != currentURL {
                try? fileManager.removeItem(at: segment.url)
            }
        }

        let remaining = ((try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []).compactMap { file in
            Self.managedRuntimeSegment(for: file, fileManager: fileManager)
        }.sorted {
            let lhsDate = (try? $0.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
            let rhsDate = (try? $1.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
            let lhsDateValue = lhsDate ?? .distantPast
            let rhsDateValue = rhsDate ?? .distantPast
            if lhsDateValue != rhsDateValue {
                return lhsDateValue < rhsDateValue
            }
            return $0.url.lastPathComponent < $1.url.lastPathComponent
        }
        guard remaining.count > maxSegments else { return }
        let deleteCount = remaining.count - maxSegments
        let deletable = remaining.filter({ $0.url.standardizedFileURL != currentURL })
        for segment in deletable.prefix(deleteCount) {
            try? fileManager.removeItem(at: segment.url)
        }
    }

    private func closeCurrentFile() {
        try? currentFileHandle?.synchronize()
        try? currentFileHandle?.close()
        currentFileHandle = nil
        currentFileURL = nil
        currentFileSize = 0
    }

    private func disableAfterFailure(_ operation: String, error: Error) {
        isDisabled = true
        cancelDelayedFlush()
        closeCurrentFile()
        guard !hasReportedFailure else { return }
        hasReportedFailure = true
        fallbackLogger.error(
            "diagnostics writer disabled operation=\(operation, privacy: .public) category=\(Self.errorCategory(error), privacy: .public)"
        )
    }

    private static func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    static func isManagedRuntimeSegment(
        _ url: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        managedRuntimeSegment(for: url, fileManager: fileManager) != nil
    }

    private static func managedRuntimeSegment(
        for url: URL,
        fileManager: FileManager
    ) -> ManagedRuntimeSegment? {
        let filename = url.lastPathComponent
        let extensionLength = ".jsonl".count
        guard filename.hasPrefix("runtime-"),
              filename.hasSuffix(".jsonl"),
              filename.count > extensionLength else {
            return nil
        }

        let stem = String(filename.dropLast(extensionLength))
        let components = stem.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0] == "runtime",
              components[1].count == 8,
              isASCIIDigits(String(components[1])),
              components[2].count >= 3,
              isASCIIDigits(String(components[2])),
              let index = Int(components[2]) else {
            return nil
        }

        let dateComponent = String(components[1])
        guard let date = dateFromKey(dateComponent), Self.dateKey(date) == dateComponent,
              fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true else {
            return nil
        }

        return ManagedRuntimeSegment(url: url, dateKey: dateComponent, index: index)
    }

    private static func dateFromKey(_ key: String) -> Date? {
        guard key.count == 8,
              let year = Int(String(key.prefix(4))),
              let month = Int(String(key.dropFirst(4).prefix(2))),
              let day = Int(String(key.dropFirst(6))) else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func isASCIIDigits(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            (48...57).contains(scalar.value)
        }
    }

    private static func errorCategory(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.domain {
        case NSCocoaErrorDomain:
            return "cocoa"
        case NSPOSIXErrorDomain:
            return "posix"
        default:
            return "io"
        }
    }
}

final class RuntimeDiagnosticInMemoryWriter: RuntimeDiagnosticWriting {
    private let lock = NSLock()
    private var storedEvents: [RuntimeDiagnosticEvent] = []
    private var storedLines: [Data] = []

    var events: [RuntimeDiagnosticEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storedEvents
    }

    var lines: [Data] {
        lock.lock()
        defer { lock.unlock() }
        return storedLines
    }

    func enqueue(_ event: RuntimeDiagnosticEvent) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var line = try? encoder.encode(event) else { return }
        line.append(0x0A)
        lock.lock()
        storedEvents.append(event)
        storedLines.append(line)
        lock.unlock()
    }

    func exportRecent(
        metadata: RuntimeDiagnosticEvent,
        to destination: URL,
        completion: @escaping @Sendable (Result<Void, RuntimeDiagnosticExportError>) -> Void
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var output = Data()
        for line in lines {
            output.append(line)
        }
        guard let metadataLine = try? encoder.encode(metadata) else {
            completion(.failure(.encode))
            return
        }
        output.append(metadataLine)
        output.append(0x0A)
        do {
            try output.write(to: destination, options: .atomic)
            completion(.success(()))
        } catch {
            completion(.failure(.write))
        }
    }

    func requestFinalFlush(
        timeout: TimeInterval,
        completion: @escaping @Sendable () -> Void
    ) {
        _ = timeout
        DispatchQueue.global(qos: .utility).async(execute: completion)
    }
}

final class RuntimeDiagnosticNoopWriter: RuntimeDiagnosticWriting {
    func enqueue(_ event: RuntimeDiagnosticEvent) {
        _ = event
    }

    func exportRecent(
        metadata: RuntimeDiagnosticEvent,
        to destination: URL,
        completion: @escaping @Sendable (Result<Void, RuntimeDiagnosticExportError>) -> Void
    ) {
        _ = (metadata, destination)
        DispatchQueue.global(qos: .utility).async {
            completion(.failure(.writerDisabled))
        }
    }

    func requestFinalFlush(
        timeout: TimeInterval,
        completion: @escaping @Sendable () -> Void
    ) {
        _ = timeout
        DispatchQueue.global(qos: .utility).async(execute: completion)
    }
}

private final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private let completion: @Sendable () -> Void
    private var didComplete = false

    init(completion: @escaping @Sendable () -> Void) {
        self.completion = completion
    }

    func finish() {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        lock.unlock()
        completion()
    }
}
