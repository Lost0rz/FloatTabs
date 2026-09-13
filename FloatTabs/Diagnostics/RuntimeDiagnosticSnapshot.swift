import Foundation

/// A one-shot projection of live owner state for a diagnostic record/export.
///
/// This value is intentionally ephemeral. It is never consulted to make a
/// presentation, lifecycle, attention, or fullscreen decision and it never
/// survives the owner that produced it.
struct RuntimeDiagnosticSnapshot: Equatable, Sendable {
    let fields: [String: RuntimeDiagnosticValue]

    init(fields: [String: RuntimeDiagnosticValue]) {
        self.fields = fields
    }
}
