import Foundation
import OSLog

@MainActor
protocol RuntimeDiagnosticRecording: AnyObject {
    var capturesDebugEvents: Bool { get }

    func environmentFields() -> [String: RuntimeDiagnosticValue]

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
    func environmentFields() -> [String: RuntimeDiagnosticValue] {
        [:]
    }

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

struct RuntimeDiagnosticSourceProvenance: Equatable {
    enum TreeState: String, Equatable {
        case clean
        case dirty
        case unknown
    }

    let sourceRevision: String
    let sourceTreeState: TreeState
    let sourceRevisionExact: Bool

    static func fromBuildMetadata(
        sourceRevision: String?,
        sourceTreeState: String?,
        sourceRevisionExact: String?
    ) -> Self {
        let revisionIsValid = sourceRevision?.range(
            of: #"^[0-9a-f]{40}$"#,
            options: .regularExpression
        ) != nil
        let boundedRevision = revisionIsValid ? sourceRevision! : "unknown"
        guard revisionIsValid,
              let sourceTreeState,
              let treeState = TreeState(rawValue: sourceTreeState) else {
            return Self(
                sourceRevision: boundedRevision,
                sourceTreeState: .unknown,
                sourceRevisionExact: false
            )
        }

        return Self(
            sourceRevision: boundedRevision,
            sourceTreeState: treeState,
            sourceRevisionExact: treeState == .clean && sourceRevisionExact == "true"
        )
    }
}

/// Adds long-run page-app trend evidence to an existing periodic checkpoint.
/// The baseline is deliberately kept in the native diagnostics recorder so a
/// page-provided counter can never be compared across a different physical
/// runtime or document epoch.
struct RuntimeDiagnosticCheckpointDeltaTracker: Sendable {
    private struct Identity: Equatable, Sendable {
        let slotID: String
        let runtimeGeneration: Int64
        let webViewInstanceID: String
        let documentEpoch: Int64
    }

    private struct Baseline: Sendable {
        let identity: Identity
        let uptime: TimeInterval
        let counters: [String: Int64]
    }

    private static let counterFields = [
        "page_app_javascript_error_count",
        "page_app_unhandled_rejection_count",
        "page_app_resource_load_failure_count",
        "page_app_resource_http_error_count",
        "page_app_slow_resource_count",
        "page_app_dropped_event_count",
        "page_app_lifecycle_event_count"
    ]

    private var baseline: Baseline?

    mutating func decorate(
        fields: [String: RuntimeDiagnosticValue],
        uptime: TimeInterval
    ) -> [String: RuntimeDiagnosticValue] {
        var result = fields
        let prefix = "page_app_"
        let deltaKeys = Self.counterFields.map {
            $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : $0
        }.map { suffix in
            suffix.replacingOccurrences(of: "_count", with: "_delta")
        }
        let rateKeys = deltaKeys.map { $0.replacingOccurrences(of: "_delta", with: "_rate_per_minute") }

        func setUnavailable(_ state: String) {
            result["page_app_delta_baseline"] = .string(state)
            result["page_app_delta_identity_available"] = .bool(false)
            for key in deltaKeys { result["page_app_\(key)"] = .null }
            for key in rateKeys { result["page_app_\(key)"] = .null }
        }

        guard let identity = Self.identity(from: fields),
              let counters = Self.counters(from: fields) else {
            setUnavailable("unavailable_identity_or_counters")
            return result
        }

        result["page_app_delta_identity_available"] = .bool(true)
        guard let previous = baseline else {
            baseline = Baseline(identity: identity, uptime: uptime, counters: counters)
            result["page_app_delta_baseline"] = .string("established")
            for key in deltaKeys { result["page_app_\(key)"] = .null }
            for key in rateKeys { result["page_app_\(key)"] = .null }
            return result
        }

        guard previous.identity == identity else {
            baseline = Baseline(identity: identity, uptime: uptime, counters: counters)
            result["page_app_delta_baseline"] = .string("reset_identity_change")
            for key in deltaKeys { result["page_app_\(key)"] = .null }
            for key in rateKeys { result["page_app_\(key)"] = .null }
            return result
        }

        guard Self.countersAreMonotonic(counters, comparedTo: previous.counters) else {
            baseline = Baseline(identity: identity, uptime: uptime, counters: counters)
            result["page_app_delta_baseline"] = .string("reset_counter_regression")
            for key in deltaKeys { result["page_app_\(key)"] = .null }
            for key in rateKeys { result["page_app_\(key)"] = .null }
            return result
        }

        let interval = uptime - previous.uptime
        result["page_app_delta_baseline"] = .string("continuing")
        result["page_app_delta_interval_s"] = interval.isFinite && interval >= 0
            ? .double(interval)
            : .null
        for (index, field) in Self.counterFields.enumerated() {
            guard let current = counters[field], let old = previous.counters[field] else {
                continue
            }
            let delta = current - old
            result["page_app_\(deltaKeys[index])"] = .integer(delta)
            if interval.isFinite, interval > 0 {
                result["page_app_\(rateKeys[index])"] = .double(
                    Double(delta) / (interval / 60)
                )
            } else {
                result["page_app_\(rateKeys[index])"] = .null
            }
        }
        baseline = Baseline(identity: identity, uptime: uptime, counters: counters)
        return result
    }

    private static func identity(
        from fields: [String: RuntimeDiagnosticValue]
    ) -> Identity? {
        guard case let .string(slotID) = fields["slot_id"],
              case let .integer(runtimeGeneration) = fields["runtime_generation"],
              case let .string(webViewInstanceID) = fields["webview_instance_id"],
              case let .integer(documentEpoch) = fields["chatgpt_document_epoch"],
              runtimeGeneration >= 0,
              documentEpoch >= 0 else {
            return nil
        }
        return Identity(
            slotID: slotID,
            runtimeGeneration: runtimeGeneration,
            webViewInstanceID: webViewInstanceID,
            documentEpoch: documentEpoch
        )
    }

    private static func counters(
        from fields: [String: RuntimeDiagnosticValue]
    ) -> [String: Int64]? {
        var counters: [String: Int64] = [:]
        for field in counterFields {
            guard case let .integer(value) = fields[field], value >= 0 else {
                return nil
            }
            counters[field] = value
        }
        return counters
    }

    private static func countersAreMonotonic(
        _ current: [String: Int64],
        comparedTo previous: [String: Int64]
    ) -> Bool {
        counterFields.allSatisfy { field in
            guard let currentValue = current[field], let previousValue = previous[field] else {
                return false
            }
            return currentValue >= previousValue
        }
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
    private var checkpointDeltaTracker = RuntimeDiagnosticCheckpointDeltaTracker()

    private static let staticEnvironmentFieldNames: Set<String> = [
        "app_version",
        "build_number",
        "source_revision",
        "source_tree_state",
        "source_revision_exact",
        "build_channel",
        "qa_label",
        "macos_version",
        "architecture",
        "session_id",
        "schema_version",
        "diagnostics_mode"
    ]

    var mode: RuntimeDiagnosticMode {
        modeProvider()
    }

    var capturesDebugEvents: Bool {
        mode.allows(.debug)
    }

    func environmentFields() -> [String: RuntimeDiagnosticValue] {
        let sourceProvenance = RuntimeDiagnosticSourceProvenance.fromBuildMetadata(
            sourceRevision: Self.sourceRevision,
            sourceTreeState: Self.sourceTreeState,
            sourceRevisionExact: Self.sourceRevisionExact
        )
        return [
            "app_version": .string(Self.appVersion),
            "build_number": .string(Self.buildNumber),
            "source_revision": .string(sourceProvenance.sourceRevision),
            "source_tree_state": .string(sourceProvenance.sourceTreeState.rawValue),
            "source_revision_exact": .bool(sourceProvenance.sourceRevisionExact),
            "build_channel": .string(Self.buildChannel),
            "qa_label": .string(Self.qaLabel),
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
        if Self.isPeriodicSample(event) {
            eventFields = eventFields.filter { key, _ in
                !Self.staticEnvironmentFieldNames.contains(key)
            }
        }
        let eventUptime = uptime()
        if event == "diagnostics.performance_checkpoint" {
            eventFields = checkpointDeltaTracker.decorate(
                fields: eventFields,
                uptime: eventUptime
            )
        }
        if let trace {
            eventFields["trace_root"] = .string(trace.root)
        }
        let diagnosticEvent = RuntimeDiagnosticEvent(
            timestamp: timestamp(),
            uptime: eventUptime,
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

    private static func isPeriodicSample(_ event: String) -> Bool {
        event == "diagnostics.performance_checkpoint"
            || event == "web_runtime.cross_world_liveness"
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
        let metadataFields = RuntimeDiagnosticPrivacy.sanitize(
            fields: environmentFields(),
            mode: mode
        )
        let metadata = RuntimeDiagnosticEvent(
            timestamp: timestamp(),
            uptime: uptime(),
            sequence: nextSequence,
            sessionID: sessionID,
            traceID: nil,
            level: .notice,
            subsystem: "diagnostics",
            event: "diagnostics.export.metadata",
            fields: metadataFields
        )
        nextSequence += 1
        writer.exportRecent(metadata: metadata, to: destination, completion: completion)
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

    private static var sourceRevision: String {
        Bundle.main.object(forInfoDictionaryKey: "FloatTabsSourceRevision") as? String ?? "unknown"
    }

    private static var sourceTreeState: String? {
        Bundle.main.object(forInfoDictionaryKey: "FloatTabsSourceTreeState") as? String
    }

    private static var sourceRevisionExact: String? {
        Bundle.main.object(forInfoDictionaryKey: "FloatTabsSourceRevisionExact") as? String
    }

    private static var buildChannel: String {
        Bundle.main.object(forInfoDictionaryKey: "FloatTabsBuildChannel") as? String ?? "unknown"
    }

    private static var qaLabel: String {
        Bundle.main.object(forInfoDictionaryKey: "FloatTabsQALabel") as? String ?? "unknown"
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
    let capturesDebugEvents = false

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
