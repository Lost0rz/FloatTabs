import Foundation
import Network
import OSLog

@MainActor
protocol RuntimeDiagnosticRecording: AnyObject {
    var capturesDebugEvents: Bool { get }

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

    func setCorrelationContextProvider(
        _ provider: @escaping @MainActor (UUID) -> [String: RuntimeDiagnosticValue]
    )
}

extension RuntimeDiagnosticRecording {
    func setCorrelationContextProvider(
        _ provider: @escaping @MainActor (UUID) -> [String: RuntimeDiagnosticValue]
    ) {
        _ = provider
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
    private var correlationContextProvider: (@MainActor (UUID) -> [String: RuntimeDiagnosticValue])?
    private let logger = Logger(
        subsystem: "com.lost0rz.FloatTabs",
        category: "RuntimeDiagnostics"
    )
    private var nextSequence: UInt64 = 1

    var mode: RuntimeDiagnosticMode {
        modeProvider()
    }

    var capturesDebugEvents: Bool {
        mode.allows(.debug)
    }

    func environmentFields() -> [String: RuntimeDiagnosticValue] {
        let bundle = Bundle.main
        return [
            "app_version": .string(Self.appVersion),
            "build_number": .string(Self.buildNumber),
            "source_revision": .string(
                bundle.object(forInfoDictionaryKey: "FloatTabsSourceRevision") as? String ?? "unknown"
            ),
            "build_channel": .string(
                bundle.object(forInfoDictionaryKey: "FloatTabsBuildChannel") as? String ?? "unknown"
            ),
            "qa_label": .string(
                bundle.object(forInfoDictionaryKey: "FloatTabsQALabel") as? String ?? "unlabeled"
            ),
            "host_pid": .integer(Int64(ProcessInfo.processInfo.processIdentifier)),
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

        var sanitizedFields = RuntimeDiagnosticPrivacy.sanitize(
            fields: fields,
            mode: currentMode
        )
        if case let .string(rawSlotID)? = fields["slot_id"],
           let slotID = UUID(uuidString: rawSlotID),
           let correlationContextProvider {
            let context = correlationContextProvider(slotID)
            for (key, value) in context {
                if sanitizedFields[key] == nil {
                    sanitizedFields[key] = value
                }
            }
            if !context.isEmpty {
                sanitizedFields["session_id"] = sanitizedFields["session_id"]
                    ?? .string(sessionID.uuidString)
            }
        }
        sanitizedFields = RuntimeDiagnosticPrivacy.sanitize(
            fields: sanitizedFields,
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

    func setCorrelationContextProvider(
        _ provider: @escaping @MainActor (UUID) -> [String: RuntimeDiagnosticValue]
    ) {
        correlationContextProvider = provider
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

enum RuntimePreviousExit: String, Equatable, Sendable {
    case clean
    case uncleanSuspected = "unclean_suspected"
    case unknown
}

enum RuntimeDiagnosticURLClass {
    static func classify(_ url: URL) -> String {
        let path = url.path
        let host = url.host?.lowercased() ?? ""
        if ChatGPTSitePolicy.isSupportedHost(host),
           let first = path.split(separator: "/").first,
           first == "c",
           path.split(separator: "/").count >= 2 {
            return "conversation"
        }
        return path.isEmpty || path == "/" ? "root" : "other"
    }
}

/// A tiny durable sentinel independent of the JSONL writer's final flush.
/// `active` means the prior process did not reach its termination callback; it
/// is intentionally called unclean_suspected rather than a crash.
struct RuntimeSessionLifecycleMarker {
    private let markerURL: URL

    init(directoryURL: URL = RuntimeDiagnosticWriter.defaultDirectory) {
        markerURL = directoryURL.appendingPathComponent("runtime-session-state", isDirectory: false)
    }

    @discardableResult
    func beginSession(fileManager: FileManager = .default) -> RuntimePreviousExit {
        let previous: RuntimePreviousExit
        if let data = try? Data(contentsOf: markerURL),
           let value = String(data: data, encoding: .utf8) {
            switch value {
            case "clean": previous = .clean
            case "active": previous = .uncleanSuspected
            default: previous = .unknown
            }
        } else {
            previous = .unknown
        }
        write("active", fileManager: fileManager)
        return previous
    }

    @discardableResult
    func markCleanExit(fileManager: FileManager = .default) -> Bool {
        write("clean", fileManager: fileManager)
    }

    @discardableResult
    private func write(_ value: String, fileManager: FileManager) -> Bool {
        do {
            try fileManager.createDirectory(
                at: markerURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(value.utf8).write(to: markerURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

@MainActor
final class RuntimeNetworkPathMonitor {
    private let monitor = NWPathMonitor()
    private let diagnostics: any RuntimeDiagnosticRecording
    private var transitionTracker = RuntimeNetworkPathTransitionTracker()
    private(set) var currentGeneration: UInt64?

    init(diagnostics: any RuntimeDiagnosticRecording) {
        self.diagnostics = diagnostics
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let status: String
            switch path.status {
            case .satisfied: status = "satisfied"
            case .unsatisfied: status = "unsatisfied"
            case .requiresConnection: status = "requires_connection"
            @unknown default: status = "unknown"
            }
            let snapshot = RuntimeNetworkPathSnapshot(
                status: status,
                interfaceClass: Self.interfaceClass(for: path),
                expensive: path.isExpensive,
                constrained: path.isConstrained
            )
            Task { @MainActor [weak self] in
                self?.accept(snapshot)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.lost0rz.FloatTabs.NetworkPath"))
    }

    func stop() {
        monitor.cancel()
    }

    private func accept(_ snapshot: RuntimeNetworkPathSnapshot) {
        guard let generation = transitionTracker.record(snapshot) else { return }
        currentGeneration = generation
        diagnostics.record(
            event: "network.path.changed",
            level: .notice,
            subsystem: "network",
            fields: [
                "generation": .integer(Int64(generation)),
                "status": .string(snapshot.status),
                "interface_class": .string(snapshot.interfaceClass),
                "expensive": .bool(snapshot.expensive),
                "constrained": .bool(snapshot.constrained)
            ]
        )
    }

    nonisolated private static func interfaceClass(for path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.wiredEthernet) { return "wired" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        if path.usesInterfaceType(.loopback) { return "loopback" }
        if path.usesInterfaceType(.other) { return "other" }
        return "none"
    }
}

struct RuntimeNetworkPathSnapshot: Equatable, Sendable {
    let status: String
    let interfaceClass: String
    let expensive: Bool
    let constrained: Bool
}

struct RuntimeNetworkPathTransitionTracker {
    private(set) var generation: UInt64 = 0
    private var previous: RuntimeNetworkPathSnapshot?

    mutating func record(_ snapshot: RuntimeNetworkPathSnapshot) -> UInt64? {
        guard previous != snapshot else { return nil }
        previous = snapshot
        generation &+= 1
        return generation
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

/// Observation-only correlation ownership. No navigation or runtime actions.
@MainActor
final class DiagnosticIncidentLifecycle {
    struct Incident {
        let id: UUID
        let slotID: UUID
        let openedUptime: TimeInterval
        var phase = "captured"
        var recoveryRuntimeGeneration: UInt64?
    }
    private(set) var current: Incident?
    private let diagnostics: any RuntimeDiagnosticRecording
    private let uptime: () -> TimeInterval
    private let timeout: TimeInterval
    private let schedule: (TimeInterval, @escaping @MainActor () -> Void) -> Void

    init(
        diagnostics: any RuntimeDiagnosticRecording,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        timeout: TimeInterval = 60 * 60,
        schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Task { @MainActor in action() }
            }
        }
    ) {
        self.diagnostics = diagnostics
        self.uptime = uptime
        self.timeout = timeout
        self.schedule = schedule
    }

    @discardableResult
    func open(slotID: UUID) -> UUID {
        close(reason: "superseded_by_new_capture")
        let incident = Incident(id: UUID(), slotID: slotID, openedUptime: uptime())
        current = incident
        record("diagnostic.incident.opened", incident: incident, reason: "capture")
        schedule(timeout) { [weak self] in self?.expire(token: incident.id) }
        return incident.id
    }

    func expire(token: UUID) {
        guard let incident = current, incident.id == token else { return }
        let remaining = timeout - (uptime() - incident.openedUptime)
        guard remaining <= 0 else {
            schedule(remaining) { [weak self] in self?.expire(token: token) }
            return
        }
        close(reason: "timeout")
    }

    func recoveryStarted(slotID: UUID) {
        guard var incident = current, incident.slotID == slotID else { return }
        incident.phase = "recovery_in_progress"
        incident.recoveryRuntimeGeneration = nil
        current = incident
        record("diagnostic.incident.recovery_started", incident: incident, reason: "manual_runtime_reset")
    }

    func recoveryCompleted(slotID: UUID, runtimeGeneration: UInt64) {
        guard var incident = current, incident.slotID == slotID,
              incident.phase == "recovery_in_progress" else { return }
        incident.phase = "post_recovery_observation"
        incident.recoveryRuntimeGeneration = runtimeGeneration
        current = incident
    }

    func observeHealth(slotID: UUID, fields: [String: RuntimeDiagnosticValue]) {
        guard let incident = current, incident.slotID == slotID,
              incident.phase == "post_recovery_observation",
              let generation = incident.recoveryRuntimeGeneration,
              fields["runtime_generation"] == .integer(Int64(generation)),
              fields["probe_trigger"] == .string("navigation_finish"),
              fields["health_probe_available"] == .bool(true) else { return }
        close(reason: "post_recovery_evidence_complete")
    }

    func runtimeReleased(slotID: UUID) {
        guard current?.slotID == slotID else { return }
        close(reason: "runtime_released")
    }

    func close(reason: String) {
        guard let incident = current else { return }
        // Record while correlation is still installed, then detach it.
        record("diagnostic.incident.closed", incident: incident, reason: reason)
        current = nil
    }

    private func record(_ event: String, incident: Incident, reason: String) {
        diagnostics.record(event: event, level: .notice, subsystem: "diagnostics", fields: [
            "incident_id": .string(incident.id.uuidString),
            "slot_id": .string(incident.slotID.uuidString),
            "phase": .string(incident.phase),
            "opened_uptime": .double(incident.openedUptime),
            "reason": .string(reason)
        ])
    }
}
