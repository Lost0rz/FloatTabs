import Foundation
import OSLog

@MainActor
protocol RuntimeDiagnosticRecording: AnyObject {
    func beginTrace(
        root: String,
        fields: [String: RuntimeDiagnosticValue]
    ) -> RuntimeDiagnosticTrace

    @discardableResult
    func record(
        event: String,
        level: RuntimeDiagnosticLevel,
        subsystem: String,
        trace: RuntimeDiagnosticTrace?,
        fields: [String: RuntimeDiagnosticValue]
    ) -> RuntimeDiagnosticEvent?

    func requestFinalFlush(
        timeout: TimeInterval,
        completion: @escaping @Sendable () -> Void
    )

    func exportRecent(
        to destination: URL,
        completion: @escaping @Sendable (Result<Void, RuntimeDiagnosticExportError>) -> Void
    )
}

extension RuntimeDiagnosticRecording {
    func beginTrace(root: String) -> RuntimeDiagnosticTrace {
        beginTrace(root: root, fields: [:])
    }

    @discardableResult
    func record(
        event: String,
        level: RuntimeDiagnosticLevel = .info,
        subsystem: String,
        trace: RuntimeDiagnosticTrace?
    ) -> RuntimeDiagnosticEvent? {
        record(
            event: event,
            level: level,
            subsystem: subsystem,
            trace: trace,
            fields: [:]
        )
    }

    @discardableResult
    func record(
        event: String,
        level: RuntimeDiagnosticLevel = .info,
        subsystem: String,
        fields: [String: RuntimeDiagnosticValue] = [:]
    ) -> RuntimeDiagnosticEvent? {
        record(
            event: event,
            level: level,
            subsystem: subsystem,
            trace: nil,
            fields: fields
        )
    }
}

@MainActor
final class RuntimeDiagnostics: RuntimeDiagnosticRecording {
    typealias TimestampProvider = () -> Date
    typealias UptimeProvider = () -> TimeInterval
    typealias ModeProvider = @MainActor () -> RuntimeDiagnosticMode

    private let writer: any RuntimeDiagnosticWriting
    private let sessionID: UUID
    private let timestamp: TimestampProvider
    private let uptime: UptimeProvider
    private let modeProvider: ModeProvider
    private let logger = Logger(
        subsystem: "com.lost0rz.FloatTabs",
        category: "RuntimeDiagnostics"
    )
    private var nextSequence: UInt64 = 1

    var mode: RuntimeDiagnosticMode {
        modeProvider()
    }

    func environmentFields() -> [String: RuntimeDiagnosticValue] {
        [
            "app_version": .string(Self.appVersion),
            "build_number": .string(Self.buildNumber),
            "macos_version": .string(ProcessInfo.processInfo.operatingSystemVersionString),
            "architecture": .string(Self.processArchitecture),
            "session_id": .string(sessionID.uuidString),
            "schema_version": .integer(Int64(RuntimeDiagnosticEvent.schemaVersion)),
            "diagnostics_mode": .string(mode.rawValue)
        ]
    }

    init(
        mode: RuntimeDiagnosticMode = .standard,
        writer: any RuntimeDiagnosticWriting,
        sessionID: UUID = UUID(),
        timestamp: @escaping TimestampProvider = Date.init,
        uptime: @escaping UptimeProvider = { ProcessInfo.processInfo.systemUptime },
        modeProvider: ModeProvider? = nil
    ) {
        self.writer = writer
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.uptime = uptime
        self.modeProvider = modeProvider ?? { mode }
    }

    convenience init(
        mode: RuntimeDiagnosticMode = .standard,
        writer: any RuntimeDiagnosticWriting,
        sessionID: UUID = UUID(),
        timestamp: Date,
        uptime: @escaping UptimeProvider = { ProcessInfo.processInfo.systemUptime },
        modeProvider: ModeProvider? = nil
    ) {
        self.init(
            mode: mode,
            writer: writer,
            sessionID: sessionID,
            timestamp: { timestamp },
            uptime: uptime,
            modeProvider: modeProvider
        )
    }

    func beginTrace(
        root: String,
        fields: [String: RuntimeDiagnosticValue] = [:]
    ) -> RuntimeDiagnosticTrace {
        _ = fields
        return RuntimeDiagnosticTrace(root: root)
    }

    @discardableResult
    func record(
        event: String,
        level: RuntimeDiagnosticLevel = .info,
        subsystem: String,
        trace: RuntimeDiagnosticTrace? = nil,
        fields: [String: RuntimeDiagnosticValue] = [:]
    ) -> RuntimeDiagnosticEvent? {
        let currentMode = mode
        guard currentMode.allows(level) else { return nil }

        let sanitizedFields = RuntimeDiagnosticPrivacy.sanitize(
            fields: fields,
            mode: currentMode
        )
        var eventFields = sanitizedFields
        if let trace {
            eventFields["trace_root"] = .string(trace.root)
        }
        let diagnosticEvent = RuntimeDiagnosticEvent(
            timestamp: timestamp(),
            uptime: uptime(),
            sequence: nextSequence,
            sessionID: sessionID,
            traceID: trace?.id,
            level: level,
            subsystem: subsystem,
            event: event,
            fields: eventFields
        )
        nextSequence += 1
        log(diagnosticEvent)
        writer.enqueue(diagnosticEvent)
        return diagnosticEvent
    }

    func requestFinalFlush(
        timeout: TimeInterval,
        completion: @escaping @Sendable () -> Void
    ) {
        writer.requestFinalFlush(timeout: timeout, completion: completion)
    }

    func exportRecent(
        to destination: URL,
        completion: @escaping @Sendable (Result<Void, RuntimeDiagnosticExportError>) -> Void
    ) {
        let headerFields = RuntimeDiagnosticPrivacy.sanitize(
            fields: environmentFields(),
            mode: mode
        )
        let header = RuntimeDiagnosticEvent(
            timestamp: timestamp(),
            uptime: uptime(),
            sequence: nextSequence,
            sessionID: sessionID,
            traceID: nil,
            level: .notice,
            subsystem: "diagnostics",
            event: "diagnostics.export.header",
            fields: headerFields
        )
        writer.exportRecent(header: header, to: destination, completion: completion)
    }

    private func log(_ event: RuntimeDiagnosticEvent) {
        let summary = "event=\(event.event) subsystem=\(event.subsystem) sequence=\(event.sequence)"
        switch event.level {
        case .debug:
            logger.debug("\(summary, privacy: .public)")
        case .info:
            logger.info("\(summary, privacy: .public)")
        case .notice:
            logger.notice("\(summary, privacy: .public)")
        case .warning:
            logger.warning("\(summary, privacy: .public)")
        case .error:
            logger.error("\(summary, privacy: .public)")
        case .fault:
            logger.fault("\(summary, privacy: .public)")
        }
    }

    private static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "unknown"
    }

    private static var buildNumber: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? "unknown"
    }

    private static var processArchitecture: String {
#if arch(arm64)
        return "arm64"
#elseif arch(x86_64)
        return "x86_64"
#else
        return "unknown"
#endif
    }
}

@MainActor
final class RuntimeDiagnosticNoopRecorder: RuntimeDiagnosticRecording {
    func beginTrace(
        root: String,
        fields: [String: RuntimeDiagnosticValue] = [:]
    ) -> RuntimeDiagnosticTrace {
        _ = fields
        return RuntimeDiagnosticTrace(root: root)
    }

    @discardableResult
    func record(
        event: String,
        level: RuntimeDiagnosticLevel = .info,
        subsystem: String,
        trace: RuntimeDiagnosticTrace? = nil,
        fields: [String: RuntimeDiagnosticValue] = [:]
    ) -> RuntimeDiagnosticEvent? {
        _ = (event, level, subsystem, trace, fields)
        return nil
    }

    func requestFinalFlush(
        timeout: TimeInterval,
        completion: @escaping @Sendable () -> Void
    ) {
        _ = timeout
        DispatchQueue.global(qos: .utility).async(execute: completion)
    }

    func exportRecent(
        to destination: URL,
        completion: @escaping @Sendable (Result<Void, RuntimeDiagnosticExportError>) -> Void
    ) {
        _ = destination
        DispatchQueue.global(qos: .utility).async {
            completion(.failure(.writerDisabled))
        }
    }
}
