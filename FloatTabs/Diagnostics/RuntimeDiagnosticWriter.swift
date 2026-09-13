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
        header: RuntimeDiagnosticEvent,
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
    private var isDisabled = false
    private var hasReportedFailure = false

    init(
        directory: URL,
        fileManager: FileManager = .default,
        maxSegmentBytes: UInt64 = 10 * 1024 * 1024,
        maxSegments: Int = 10,
        retention: TimeInterval = 7 * 24 * 60 * 60,
        dateProvider: @escaping DateProvider = Date.init
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.maxSegmentBytes = max(1, maxSegmentBytes)
        self.maxSegments = max(1, maxSegments)
        self.retention = max(0, retention)
        self.dateProvider = dateProvider
    }

    func exportRecent(
        header: RuntimeDiagnosticEvent,
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

            self.flushBuffer()
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                var output = try encoder.encode(
                    RuntimeDiagnosticPrivacy.sanitizedEvent(header)
                )
                output.append(0x0A)

                let logFiles = (try? self.fileManager.contentsOfDirectory(
                    at: self.directory,
                    includingPropertiesForKeys: [.contentModificationDateKey]
                )) ?? []
                    .filter { $0.pathExtension == "jsonl" }
                    .sorted { lhs, rhs in
                        let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                            ?? nil
                        let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                            ?? nil
                        let lhsDateValue = lhsDate ?? .distantPast
                        let rhsDateValue = rhsDate ?? .distantPast
                        if lhsDateValue != rhsDateValue {
                            return lhsDateValue < rhsDateValue
                        }
                        return lhs.lastPathComponent < rhs.lastPathComponent
                    }

                for file in logFiles {
                    output.append(try Data(contentsOf: file))
                }

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

                if self.bufferedBytes >= 64 * 1024
                    || event.level == .warning
                    || event.level == .error
                    || event.level == .fault {
                    self.flushBuffer()
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
        } catch {
            disableAfterFailure("write", error: error)
        }
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
        let prefix = "runtime-\(dateKey)-"
        let indices = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ))?.compactMap { url -> Int? in
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix(prefix) else { return nil }
            return Int(name.dropFirst(prefix.count))
        } ?? []
        guard let latest = indices.max() else { return 1 }

        let latestURL = directory.appendingPathComponent(
            String(format: "runtime-%@-%03d.jsonl", dateKey, latest)
        )
        let latestSize = (try? fileManager.attributesOfItem(atPath: latestURL.path))?[.size]
            as? NSNumber
        return latestSize?.uint64Value ?? 0 >= maxSegmentBytes ? latest + 1 : latest
    }

    private func pruneFiles(now: Date) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey]
        ) else { return }

        let logs = files.filter { $0.pathExtension == "jsonl" }
        let cutoff = now.addingTimeInterval(-retention)
        for file in logs {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? nil
            if let date, date < cutoff, file != currentFileURL {
                try? fileManager.removeItem(at: file)
            }
        }

        let remaining = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ))?.filter { $0.pathExtension == "jsonl" }.sorted {
            let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
            let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
            let lhsDateValue = lhsDate ?? .distantPast
            let rhsDateValue = rhsDate ?? .distantPast
            if lhsDateValue != rhsDateValue {
                return lhsDateValue < rhsDateValue
            }
            return $0.lastPathComponent < $1.lastPathComponent
        } ?? []
        guard remaining.count > maxSegments else { return }
        for file in remaining.prefix(remaining.count - maxSegments) where file != currentFileURL {
            try? fileManager.removeItem(at: file)
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
        header: RuntimeDiagnosticEvent,
        to destination: URL,
        completion: @escaping @Sendable (Result<Void, RuntimeDiagnosticExportError>) -> Void
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var output = try? encoder.encode(header) else {
            completion(.failure(.encode))
            return
        }
        output.append(0x0A)
        for line in lines {
            output.append(line)
        }
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
        header: RuntimeDiagnosticEvent,
        to destination: URL,
        completion: @escaping @Sendable (Result<Void, RuntimeDiagnosticExportError>) -> Void
    ) {
        _ = (header, destination)
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
