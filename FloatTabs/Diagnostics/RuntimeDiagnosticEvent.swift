import Foundation

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
