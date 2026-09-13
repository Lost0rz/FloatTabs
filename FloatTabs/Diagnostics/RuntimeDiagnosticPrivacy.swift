import Foundation
import WebKit

enum RuntimeDiagnosticPrivacy {
    private static let sensitiveKeyFragments = [
        "authorization",
        "cookie",
        "password",
        "token",
        "secret",
        "body",
        "html",
        "input",
        "value",
        "content",
        "title",
        "query",
        "fragment",
        "userinfo",
        "username",
        "homedirectory",
        "homepath",
        "serial",
        "hardwareuuid",
        "ipaddress",
        "location",
    ]

    private static let secretPatterns = [
        "bearer ",
        "basic ",
        "api_key=",
        "apikey=",
        "access_token=",
        "refresh_token=",
        "client_secret=",
        "sk-",
    ]

    static func safeURLString(
        _ url: URL,
        mode: RuntimeDiagnosticMode
    ) -> String? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty,
              !host.contains("@") else {
            return nil
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if let port = url.port, port != (scheme == "https" ? 443 : 80) {
            components.port = port
        }

        guard mode == .verbose else {
            return components.string
        }

        let base = components.string
        let sanitizedPath = sanitizedPath(url.path)
        return base.map { $0 + sanitizedPath }
    }

    static func sanitizedErrorCategory(_ error: Error) -> [String: RuntimeDiagnosticValue] {
        let nsError = error as NSError
        let domain = safeOpaqueString(nsError.domain) ?? "unknown"
        let category: String
        switch nsError.domain {
        case NSURLErrorDomain:
            category = "network"
        case WKError.errorDomain:
            category = "webkit"
        default:
            category = "runtime"
        }

        return [
            "error_domain": .string(domain),
            "error_code": .integer(Int64(nsError.code)),
            "error_category": .string(category),
        ]
    }

    static func safeErrorCategory(_ error: Error) -> String {
        guard case let .string(category) = sanitizedErrorCategory(error)["error_category"] else {
            return "runtime"
        }
        return category
    }

    static func safeErrorDomain(_ error: Error) -> String {
        guard case let .string(domain) = sanitizedErrorCategory(error)["error_domain"] else {
            return "unknown"
        }
        return domain
    }

    static func safeErrorCode(_ error: Error) -> Int64 {
        guard case let .integer(code) = sanitizedErrorCategory(error)["error_code"] else {
            return 0
        }
        return code
    }

    static func safeBundleIdentifier(_ bundleIdentifier: String?) -> RuntimeDiagnosticValue? {
        guard let bundleIdentifier,
              bundleIdentifier.range(of: #"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return .string(bundleIdentifier)
    }

    static func sanitize(
        fields: [String: RuntimeDiagnosticValue],
        mode: RuntimeDiagnosticMode
    ) -> [String: RuntimeDiagnosticValue] {
        fields.reduce(into: [:]) { result, entry in
            let (key, value) = entry
            guard !isSensitiveKey(key) else { return }

            switch value {
            case let .string(string):
                guard let sanitized = sanitizeString(string, key: key, mode: mode) else {
                    return
                }
                result[key] = .string(sanitized)
            case .bool, .integer, .double, .null:
                result[key] = value
            }
        }
    }

    /// Defense in depth at the persistence boundary. RuntimeDiagnostics calls
    /// this before OSLog and enqueue; the writer also applies it so a future
    /// caller cannot persist an unsanitized event by using the writer directly.
    static func sanitizedEvent(
        _ event: RuntimeDiagnosticEvent,
        mode: RuntimeDiagnosticMode = .verbose
    ) -> RuntimeDiagnosticEvent {
        RuntimeDiagnosticEvent(
            schemaVersion: event.schemaVersion,
            timestamp: event.timestamp,
            uptime: event.uptime,
            sequence: event.sequence,
            sessionID: event.sessionID,
            traceID: event.traceID,
            level: event.level,
            subsystem: event.subsystem,
            event: event.event,
            fields: sanitize(fields: event.fields, mode: mode)
        )
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
        return sensitiveKeyFragments.contains { normalized.contains($0) }
    }

    private static func sanitizeString(
        _ string: String,
        key: String,
        mode: RuntimeDiagnosticMode
    ) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("\0"),
              !containsSecretPattern(trimmed) else {
            return nil
        }

        if key.lowercased().contains("url") || looksLikeURL(trimmed) {
            guard let url = URL(string: trimmed) else { return nil }
            return safeURLString(url, mode: mode)
        }

        return trimmed
    }

    private static func containsSecretPattern(_ string: String) -> Bool {
        let normalized = string.lowercased()
        return secretPatterns.contains { normalized.contains($0) }
            || (string.split(separator: ".").count == 3 && string.count > 30)
    }

    private static func looksLikeURL(_ string: String) -> Bool {
        string.lowercased().hasPrefix("http://") || string.lowercased().hasPrefix("https://")
    }

    private static func sanitizedPath(_ path: String) -> String {
        let segments = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !segments.isEmpty else { return "" }

        let conversationMarkers = Set([
            "c", "chat", "chats", "conversation", "conversations", "share", "thread", "threads"
        ])
        var output: [String] = []
        var redactNext = false

        for segment in segments.prefix(8) {
            let normalized = segment.lowercased()
            if redactNext || conversationMarkers.contains(normalized) {
                output.append(redactNext ? "<redacted>" : segment)
                redactNext = conversationMarkers.contains(normalized)
                continue
            }

            if looksDynamic(segment) || containsSecretPattern(segment) {
                output.append("<redacted>")
            } else {
                output.append(segment)
            }
        }

        return "/" + output.joined(separator: "/")
    }

    private static func looksDynamic(_ segment: String) -> Bool {
        let uuidLike = segment.range(
            of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"#,
            options: .regularExpression
        ) != nil
        let longOpaque = segment.count >= 24 && segment.range(
            of: #"^[A-Za-z0-9_-]+$"#,
            options: .regularExpression
        ) != nil
        return uuidLike || longOpaque
    }

    private static func safeOpaqueString(_ string: String) -> String? {
        guard !string.isEmpty,
              !containsSecretPattern(string),
              !string.contains("\n"),
              !string.contains("\r") else {
            return nil
        }
        return String(string.prefix(80))
    }
}
