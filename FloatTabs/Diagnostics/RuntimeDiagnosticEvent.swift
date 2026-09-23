import Foundation
import CryptoKit

enum RuntimeDiagnosticMode: String, CaseIterable, Codable, Equatable, Sendable {
    case off
    case standard
    case verbose

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .standard: return "Standard"
        case .verbose: return "Verbose"
        }
    }

    func allows(_ level: RuntimeDiagnosticLevel) -> Bool {
        switch self {
        case .off:
            return false
        case .standard:
            return level != .debug
        case .verbose:
            return true
        }
    }
}

enum RuntimeDiagnosticLevel: String, CaseIterable, Codable, Equatable, Sendable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault
}

enum RuntimeDiagnosticValue: Codable, Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown diagnostic value"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct RuntimeDiagnosticTrace: Equatable, Sendable {
    let id: UUID
    let root: String

    init(id: UUID = UUID(), root: String) {
        self.id = id
        self.root = root
    }
}

enum RuntimeDiagnosticDismissClassification: String, Codable, Equatable, Sendable {
    case explicit
    case automatic
}

enum RuntimeDiagnosticDismissSource: String, Codable, Equatable, Sendable {
    case hotkey
    case menubar
    case externalCommand = "external_command"
    case workspaceActivation = "workspace_activation"
    case globalMouse = "global_mouse"
    case fullscreen
    case `internal`

    var classification: RuntimeDiagnosticDismissClassification {
        switch self {
        case .workspaceActivation, .globalMouse:
            return .automatic
        case .hotkey, .menubar, .externalCommand, .fullscreen, .internal:
            return .explicit
        }
    }
}

enum RuntimeDiagnosticAutoHideIgnoreReason: String, Codable, Equatable, Sendable {
    case ownApplication = "own_application"
    case suppressionGrace = "suppression_grace"
    case presentationFocusPending = "presentation_focus_pending"
    case frontmostMismatch = "frontmost_mismatch"
    case panelNotVisible = "panel_not_visible"
    case pinned
    case insidePresentation = "inside_presentation"
    case staleMouseEvent = "stale_mouse_event"
    case missingApplication = "missing_application"
}

enum RuntimeDiagnosticAutoHideObservationDecision: Equatable, Sendable {
    case hide
    case ignore(reason: RuntimeDiagnosticAutoHideIgnoreReason)

    static func workspace(
        panelVisible: Bool,
        pinned: Bool,
        suppressionActive: Bool,
        presentationFocusPending: Bool,
        frontmostMatches: Bool,
        activatedApplicationIsOwn: Bool = false
    ) -> Self {
        if activatedApplicationIsOwn {
            return .ignore(reason: .ownApplication)
        }
        if suppressionActive {
            return .ignore(reason: .suppressionGrace)
        }
        if presentationFocusPending {
            return .ignore(reason: .presentationFocusPending)
        }
        if !frontmostMatches {
            return .ignore(reason: .frontmostMismatch)
        }
        if !panelVisible {
            return .ignore(reason: .panelNotVisible)
        }
        if pinned {
            return .ignore(reason: .pinned)
        }
        return .hide
    }

    static func globalMouse(
        panelVisible: Bool,
        pinned: Bool,
        insidePresentation: Bool,
        staleEvent: Bool
    ) -> Self {
        if staleEvent {
            return .ignore(reason: .staleMouseEvent)
        }
        if insidePresentation {
            return .ignore(reason: .insidePresentation)
        }
        if !panelVisible {
            return .ignore(reason: .panelNotVisible)
        }
        if pinned {
            return .ignore(reason: .pinned)
        }
        return .hide
    }

    var result: String {
        switch self {
        case .hide:
            return "hide"
        case .ignore:
            return "ignore"
        }
    }

    var ignoreReason: RuntimeDiagnosticAutoHideIgnoreReason? {
        guard case let .ignore(reason) = self else { return nil }
        return reason
    }
}

struct RuntimeDiagnosticWindowBounds: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

enum RuntimeDiagnosticWindowObservationQuality: String, Codable, Equatable, Sendable {
    case frontmostCandidate = "frontmost_candidate"
    case orderedWindowCandidate = "ordered_window_candidate"
    case unavailable
}

enum RuntimeDiagnosticWindowMatch: String, Codable, Equatable, Sendable {
    case matched = "true"
    case mismatched = "false"
    case unknown
}

struct RuntimeDiagnosticExternalWindowObservation: Equatable, Sendable {
    let processIdentifier: Int64
    let windowNumber: Int64?
    let displayID: Int64?
    let bounds: RuntimeDiagnosticWindowBounds?
    let quality: RuntimeDiagnosticWindowObservationQuality

    static func windowMatch(
        applicationMatches: Bool,
        capturedWindowNumber: Int64?,
        observedWindowNumber: Int64?
    ) -> RuntimeDiagnosticWindowMatch {
        guard applicationMatches else {
            return .unknown
        }
        guard let capturedWindowNumber, let observedWindowNumber else {
            return .unknown
        }
        return capturedWindowNumber == observedWindowNumber ? .matched : .mismatched
    }
}

struct RuntimeDiagnosticRestoreObservationTicket: Equatable, Sendable {
    let generation: UInt64
    let trace: RuntimeDiagnosticTrace
}

struct RuntimeDiagnosticRestoreObservationTracker: Sendable {
    private var nextGeneration: UInt64 = 0
    private var pendingTicket: RuntimeDiagnosticRestoreObservationTicket?

    mutating func begin(trace: RuntimeDiagnosticTrace) -> RuntimeDiagnosticRestoreObservationTicket {
        nextGeneration &+= 1
        let ticket = RuntimeDiagnosticRestoreObservationTicket(
            generation: nextGeneration,
            trace: trace
        )
        pendingTicket = ticket
        return ticket
    }

    mutating func invalidate() {
        nextGeneration &+= 1
        pendingTicket = nil
    }

    func accepts(_ ticket: RuntimeDiagnosticRestoreObservationTicket) -> Bool {
        pendingTicket == ticket
    }

    func trace(for ticket: RuntimeDiagnosticRestoreObservationTicket) -> RuntimeDiagnosticTrace? {
        accepts(ticket) ? ticket.trace : nil
    }

    mutating func consume(
        _ ticket: RuntimeDiagnosticRestoreObservationTicket
    ) -> RuntimeDiagnosticRestoreObservationTicket? {
        guard accepts(ticket) else { return nil }
        pendingTicket = nil
        return ticket
    }
}

struct RuntimeDiagnosticPresentationFocusRequest: Equatable, Sendable {
    let generation: UInt64
    let trace: RuntimeDiagnosticTrace?
}

struct RuntimeDiagnosticEvent: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let timestamp: Date
    let uptime: TimeInterval
    let sequence: UInt64
    let sessionID: UUID
    let traceID: UUID?
    let level: RuntimeDiagnosticLevel
    let subsystem: String
    let event: String
    let fields: [String: RuntimeDiagnosticValue]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case timestamp
        case uptime
        case sequence
        case sessionID = "session_id"
        case traceID = "trace_id"
        case level
        case subsystem
        case event
        case fields
    }

    init(
        schemaVersion: Int = RuntimeDiagnosticEvent.schemaVersion,
        timestamp: Date,
        uptime: TimeInterval,
        sequence: UInt64,
        sessionID: UUID,
        traceID: UUID?,
        level: RuntimeDiagnosticLevel,
        subsystem: String,
        event: String,
        fields: [String: RuntimeDiagnosticValue]
    ) {
        self.schemaVersion = schemaVersion
        self.timestamp = timestamp
        self.uptime = uptime
        self.sequence = sequence
        self.sessionID = sessionID
        self.traceID = traceID
        self.level = level
        self.subsystem = subsystem
        self.event = event
        self.fields = fields
    }
}

enum UnreadRuntimeDiagnosticIdentitySource: String, Equatable, Sendable {
    case stableAttribute = "stable_attribute"
    case unavailable

    init(identity: ChatGPTResponseIdentity?) {
        self = identity == nil ? .unavailable : .stableAttribute
    }
}

enum UnreadRuntimeDiagnosticCompletionProducer: String, Equatable, Sendable {
    case mutationObserver = "mutation_observer"
    case livenessProbe = "liveness_probe"
    case resync
    case snapshot
    case unknown
}

enum UnreadRuntimeDiagnosticHandledLookup: String, Equatable, Sendable {
    case hit
    case miss
    case unavailable
}

/// Process-local privacy-safe metadata for tracing unread response ownership.
/// The nonce is intentionally never serialized or exposed to diagnostics.
@MainActor
final class UnreadRuntimeDiagnosticContext {
    static let shared = UnreadRuntimeDiagnosticContext()

    let sessionID: UUID
    private let processNonce: Data
    private var nextSequence: UInt64 = 1

    init(sessionID: UUID = UUID(), processNonce: Data? = nil) {
        self.sessionID = sessionID
        self.processNonce = processNonce ?? Data((0..<32).map { _ in
            UInt8.random(in: UInt8.min...UInt8.max)
        })
    }

    func fields(
        _ fields: [String: RuntimeDiagnosticValue] = [:]
    ) -> [String: RuntimeDiagnosticValue] {
        var enriched = fields
        enriched["diagnostic_session_id"] = .string(sessionID.uuidString)
        enriched["diagnostic_sequence"] = .integer(Int64(nextSequence))
        nextSequence &+= 1
        return enriched
    }

    func identityTag(
        _ identity: ChatGPTResponseIdentity?
    ) -> RuntimeDiagnosticValue {
        tag(identity?.rawValue)
    }

    func documentTokenTag(
        _ token: String?
    ) -> RuntimeDiagnosticValue {
        tag(token)
    }

    func tag(_ rawValue: String?) -> RuntimeDiagnosticValue {
        guard let rawValue else { return .null }
        let digest = SHA256.hash(data: processNonce + Data(rawValue.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return .string(String(hex.prefix(16)))
    }
}
