import Foundation

/// Main-actor facade for the Settings export action. It only assembles the
/// request; JSONL reads and writes remain owned by RuntimeDiagnosticWriter's
/// dedicated serial queue.
@MainActor
final class RuntimeDiagnosticExporter {
    private let diagnostics: RuntimeDiagnostics

    init(diagnostics: RuntimeDiagnostics) {
        self.diagnostics = diagnostics
    }

    func exportRecent(
        to destination: URL,
        completion: @escaping @Sendable (Result<Void, RuntimeDiagnosticExportError>) -> Void
    ) {
        diagnostics.exportRecent(to: destination, completion: completion)
    }

    static func defaultFilename(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "FloatTabs-Diagnostics-\(formatter.string(from: now)).jsonl"
    }
}
