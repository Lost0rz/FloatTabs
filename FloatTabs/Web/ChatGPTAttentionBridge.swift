import Foundation
import WebKit

/// The one shared ChatGPT host-family predicate. `SiteCompatibilityPolicy`
/// (rendering) and attention observation validation both route through this
/// type so the two host lists can never drift.
enum ChatGPTSitePolicy {
    static let chatGPTHost = "chatgpt.com"
    static let legacyChatHost = "chat.openai.com"

    static func isSupportedHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return normalized == chatGPTHost
            || normalized.hasSuffix(".\(chatGPTHost)")
            || normalized == legacyChatHost
    }

    static func isSupportedChatGPTURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host else {
            return false
        }
        return isSupportedHost(host)
    }
}

/// Normalized bridge observations. These are sensor facts about the current
/// ChatGPT document, not attention state: `WebAttentionCoordinator` stays the
/// sole authority and is not connected to the bridge until Stage C.
enum ChatGPTAttentionObservation: Equatable, Sendable {
    case generationStarted
    case generationFinished
    case runtimeReset
}

struct ChatGPTAttentionEvent: Equatable, Sendable {
    let observation: ChatGPTAttentionObservation
    let responseIdentity: ChatGPTResponseIdentity?
}

/// Minimal bridge payload. Metadata only: prompt text, response text, and any
/// other page content must never appear in this protocol.
struct ChatGPTBridgePayload: Equatable {
    static let currentVersion = 1
    static let baselineKind = "baseline"
    static let stateKind = "state"

    private static let tokenLengthRange = 8...128

    let version: Int
    let kind: String
    /// Opaque per-document identity created by the injected script. Carries no
    /// page content.
    let token: String
    let generating: Bool
    let responseIdentity: ChatGPTResponseIdentity?

    init(
        version: Int,
        kind: String,
        token: String,
        generating: Bool,
        responseIdentity: ChatGPTResponseIdentity? = nil
    ) {
        self.version = version
        self.kind = kind
        self.token = token
        self.generating = generating
        self.responseIdentity = responseIdentity
    }

    static func parse(_ body: [String: Any]) -> ChatGPTBridgePayload? {
        guard let version = body["version"] as? Int,
              version == currentVersion,
              let kind = body["kind"] as? String,
              kind == baselineKind || kind == stateKind,
              let token = body["token"] as? String,
              tokenLengthRange.contains(token.count),
              let generating = body["generating"] as? Bool else {
            return nil
        }
        let responseIdentity: ChatGPTResponseIdentity?
        if let rawIdentity = body["responseIdentity"] as? String {
            guard let parsedIdentity = ChatGPTResponseIdentity(rawValue: rawIdentity) else {
                return nil
            }
            responseIdentity = parsedIdentity
        } else if body["responseIdentity"] == nil || body["responseIdentity"] is NSNull {
            responseIdentity = nil
        } else {
            return nil
        }
        return ChatGPTBridgePayload(
            version: version,
            kind: kind,
            token: token,
            generating: generating,
            responseIdentity: responseIdentity
        )
    }
}

enum ChatGPTIncidentHealthProbeOutcome: String, Equatable, Sendable {
    case success
    case unsupportedDocument = "unsupported_document"
    case bridgeUnavailable = "bridge_unavailable"
    case evaluationFailed = "evaluation_failed"
    case timeout
    case stale
}

struct ChatGPTIncidentHealthProbeValues: Equatable, Sendable {
    let documentReadyState: String
    let visibilityState: String
    let conversationShellPresent: Bool
    let composerPresent: Bool
    let loadingIndicatorPresent: Bool
    let loadingIndicatorVisible: Bool
    let conversationLoadErrorPresent: Bool

    static func parse(_ value: Any) -> ChatGPTIncidentHealthProbeValues? {
        guard let fields = value as? [String: Any],
              fields["version"] as? Int == 1,
              let documentReadyState = fields["document_ready_state"] as? String,
              ["loading", "interactive", "complete", "other"].contains(documentReadyState),
              let visibilityState = fields["visibility_state"] as? String,
              ["visible", "hidden", "prerender", "unloaded", "other"].contains(visibilityState),
              let conversationShellPresent = fields["conversation_shell_present"] as? Bool,
              let composerPresent = fields["composer_present"] as? Bool,
              let loadingIndicatorPresent = fields["loading_indicator_present"] as? Bool,
              let loadingIndicatorVisible = fields["loading_indicator_visible"] as? Bool,
              let conversationLoadErrorPresent = fields["conversation_load_error_present"] as? Bool else {
            return nil
        }
        return ChatGPTIncidentHealthProbeValues(
            documentReadyState: documentReadyState,
            visibilityState: visibilityState,
            conversationShellPresent: conversationShellPresent,
            composerPresent: composerPresent,
            loadingIndicatorPresent: loadingIndicatorPresent,
            loadingIndicatorVisible: loadingIndicatorVisible,
            conversationLoadErrorPresent: conversationLoadErrorPresent
        )
    }

    var diagnosticFields: [String: RuntimeDiagnosticValue] {
        [
            "document_ready_state": .string(documentReadyState),
            "visibility_state": .string(visibilityState),
            "conversation_shell_present": .bool(conversationShellPresent),
            "composer_present": .bool(composerPresent),
            "loading_indicator_present": .bool(loadingIndicatorPresent),
            "loading_indicator_visible": .bool(loadingIndicatorVisible),
            "conversation_load_error_present": .bool(conversationLoadErrorPresent)
        ]
    }
}

struct ChatGPTIncidentHealthProbeResult: Equatable, Sendable {
    let outcome: ChatGPTIncidentHealthProbeOutcome
    let values: ChatGPTIncidentHealthProbeValues?
    let documentEpoch: UInt64?
    let generating: Bool?
    let latencyMilliseconds: Double

    var diagnosticFields: [String: RuntimeDiagnosticValue] {
        var fields: [String: RuntimeDiagnosticValue] = [
            "health_probe_outcome": .string(outcome.rawValue),
            "health_probe_latency_ms": .double(min(max(latencyMilliseconds, 0), 5_000)),
            "attention_document_admitted": outcome == .success ? .bool(true) : .null,
            "chatgpt_document_epoch": documentEpoch.map { .integer(Int64($0)) } ?? .null,
            "chatgpt_generating": generating.map(RuntimeDiagnosticValue.bool) ?? .null
        ]
        let healthFields = values?.diagnosticFields ?? [
            "document_ready_state": .null,
            "visibility_state": .null,
            "conversation_shell_present": .null,
            "composer_present": .null,
            "loading_indicator_present": .null,
            "loading_indicator_visible": .null,
            "conversation_load_error_present": .null
        ]
        fields.merge(healthFields) { _, new in new }
        return fields
    }
}

typealias ChatGPTIncidentHealthProbeEvaluator = @MainActor (
    WKWebView,
    String
) async throws -> Any

typealias ChatGPTIncidentPageAppProbeEvaluator = @MainActor (
    WKWebView,
    String,
    String
) async throws -> Any

typealias ChatGPTBenchmarkProbeEvaluator = @MainActor (
    WKWebView,
    String
) async throws -> Any

struct ChatGPTAttentionBenchmarkCounters: Equatable, Sendable {
    /// JS counters are carried as exact integers through Number.MAX_SAFE_INTEGER.
    /// This is far above the old 255 cap while remaining representable in JSON
    /// and Int64 without introducing an unbounded collection.
    static let maximumCounter: Int64 = 9_007_199_254_740_991
    static let maximumDurationMilliseconds = 3_600_000.0
    static let maximumTotalDurationMilliseconds = 9_007_199_254_740_991.0

#if DEBUG
    private(set) var isEnabled = false
#else
    private(set) var isEnabled = true
#endif
    private(set) var livenessProbeCount: Int64 = 0
    private(set) var confirmationProbeCount: Int64 = 0
    private(set) var livenessProbeTotalMilliseconds = 0.0
    private(set) var livenessProbeMaximumMilliseconds = 0.0
    private(set) var livenessFailureCount: Int64 = 0
    private(set) var recoveredCompletionCount: Int64 = 0
    /// These health counters are bridge-lifetime evidence. They are separate
    /// from the opt-in Debug benchmark measurement and must survive ordinary
    /// document and physical WebContent runtime replacement boundaries.
    private(set) var livenessTimeoutCount: Int64 = 0
    private(set) var livenessSuppressionCount: Int64 = 0
    private(set) var currentDocumentResyncTimeoutCount: Int64 = 0
    private(set) var currentDocumentResyncSuppressionCount: Int64 = 0

    mutating func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    mutating func resetValues() {
        livenessProbeCount = 0
        confirmationProbeCount = 0
        livenessProbeTotalMilliseconds = 0
        livenessProbeMaximumMilliseconds = 0
        livenessFailureCount = 0
        recoveredCompletionCount = 0
    }

    mutating func recordLivenessProbe(
        durationMilliseconds: Double,
        isConfirmation: Bool
    ) {
        guard isEnabled else { return }
        livenessProbeCount = Self.saturatedIncrement(livenessProbeCount)
        if isConfirmation {
            confirmationProbeCount = Self.saturatedIncrement(confirmationProbeCount)
        }
        let duration = Self.boundedDuration(durationMilliseconds)
        livenessProbeTotalMilliseconds = Self.boundedTotalDuration(
            livenessProbeTotalMilliseconds + duration
        )
        livenessProbeMaximumMilliseconds = max(
            livenessProbeMaximumMilliseconds,
            duration
        )
    }

    mutating func recordLivenessFailure() {
        guard isEnabled else { return }
        livenessFailureCount = Self.saturatedIncrement(livenessFailureCount)
    }

    mutating func recordRecoveredCompletion() {
        guard isEnabled else { return }
        recoveredCompletionCount = Self.saturatedIncrement(recoveredCompletionCount)
    }

    mutating func recordLivenessTimeout() {
        livenessTimeoutCount = Self.saturatedIncrement(livenessTimeoutCount)
    }

    mutating func recordLivenessSuppression() {
        livenessSuppressionCount = Self.saturatedIncrement(livenessSuppressionCount)
    }

    mutating func recordCurrentDocumentResyncTimeout() {
        currentDocumentResyncTimeoutCount = Self.saturatedIncrement(
            currentDocumentResyncTimeoutCount
        )
    }

    mutating func recordCurrentDocumentResyncSuppression() {
        currentDocumentResyncSuppressionCount = Self.saturatedIncrement(
            currentDocumentResyncSuppressionCount
        )
    }

    var fields: [String: Any] {
        [
            "liveness_probe_count": livenessProbeCount,
            "confirmation_probe_count": confirmationProbeCount,
            "liveness_probe_total_ms": livenessProbeTotalMilliseconds,
            "liveness_probe_max_ms": livenessProbeMaximumMilliseconds,
            "liveness_failure_count": livenessFailureCount,
            "recovered_completion_count": recoveredCompletionCount,
            "liveness_timeout_count": livenessTimeoutCount,
            "liveness_suppression_count": livenessSuppressionCount,
            "current_document_resync_timeout_count": currentDocumentResyncTimeoutCount,
            "current_document_resync_suppression_count": currentDocumentResyncSuppressionCount
        ]
    }

    static func saturatedIncrement(_ value: Int64) -> Int64 {
        value >= maximumCounter ? maximumCounter : max(value, 0) + 1
    }

    static func boundedDuration(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), maximumDurationMilliseconds)
    }

    static func boundedTotalDuration(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), maximumTotalDurationMilliseconds)
    }
}

private struct ChatGPTAttentionBenchmarkDocumentValues {
    let token: String
    let enabled: Bool
    let visibilityState: String
    let generating: Bool
    let mutationCallbackBatchCount: Int64
    let detectorScheduleCount: Int64
    let detectorEvaluateCount: Int64
    let detectorEvaluateTotalMilliseconds: Double
    let detectorEvaluateMaximumMilliseconds: Double
    let responseIdentityResolutionCount: Int64
    let responseIdentityResolutionTotalMilliseconds: Double
    let responseIdentityResolutionMaximumMilliseconds: Double

    static func parse(_ value: Any) -> ChatGPTAttentionBenchmarkDocumentValues? {
        guard let fields = value as? [String: Any],
              fields["version"] as? Int == 1,
              let token = fields["token"] as? String,
              (8...128).contains(token.count),
              let enabled = fields["enabled"] as? Bool,
              let visibilityState = fields["visibility_state"] as? String,
              ["visible", "hidden", "prerender", "unloaded", "other"].contains(visibilityState),
              let generating = fields["generating"] as? Bool,
              let mutationCallbackBatchCount = boundedCount(fields["mutation_callback_batch_count"]),
              let detectorScheduleCount = boundedCount(fields["detector_schedule_count"]),
              let detectorEvaluateCount = boundedCount(fields["detector_evaluate_count"]),
              let detectorEvaluateTotalMilliseconds = boundedTotalDuration(fields["detector_evaluate_total_ms"]),
              let detectorEvaluateMaximumMilliseconds = boundedDuration(fields["detector_evaluate_max_ms"]),
              let responseIdentityResolutionCount = boundedCount(fields["response_identity_resolution_count"]),
              let responseIdentityResolutionTotalMilliseconds = boundedTotalDuration(fields["response_identity_resolution_total_ms"]),
              let responseIdentityResolutionMaximumMilliseconds = boundedDuration(fields["response_identity_resolution_max_ms"]) else {
            return nil
        }
        return ChatGPTAttentionBenchmarkDocumentValues(
            token: token,
            enabled: enabled,
            visibilityState: visibilityState,
            generating: generating,
            mutationCallbackBatchCount: mutationCallbackBatchCount,
            detectorScheduleCount: detectorScheduleCount,
            detectorEvaluateCount: detectorEvaluateCount,
            detectorEvaluateTotalMilliseconds: detectorEvaluateTotalMilliseconds,
            detectorEvaluateMaximumMilliseconds: detectorEvaluateMaximumMilliseconds,
            responseIdentityResolutionCount: responseIdentityResolutionCount,
            responseIdentityResolutionTotalMilliseconds: responseIdentityResolutionTotalMilliseconds,
            responseIdentityResolutionMaximumMilliseconds: responseIdentityResolutionMaximumMilliseconds
        )
    }

    var fields: [String: Any] {
        [
            "measurement_enabled": enabled,
            "document_visibility_state": visibilityState,
            "generating": generating,
            "mutation_callback_batch_count": mutationCallbackBatchCount,
            "detector_schedule_count": detectorScheduleCount,
            "detector_evaluate_count": detectorEvaluateCount,
            "detector_evaluate_total_ms": detectorEvaluateTotalMilliseconds,
            "detector_evaluate_max_ms": detectorEvaluateMaximumMilliseconds,
            "response_identity_resolution_count": responseIdentityResolutionCount,
            "response_identity_resolution_total_ms": responseIdentityResolutionTotalMilliseconds,
            "response_identity_resolution_max_ms": responseIdentityResolutionMaximumMilliseconds
        ]
    }

    private static func boundedCount(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber else { return nil }
        let result = number.int64Value
        guard result >= 0,
              result <= ChatGPTAttentionBenchmarkCounters.maximumCounter else { return nil }
        return result
    }

    private static func boundedDuration(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let result = number.doubleValue
        guard result.isFinite,
              result >= 0,
              result <= ChatGPTAttentionBenchmarkCounters.maximumDurationMilliseconds else { return nil }
        return result
    }

    private static func boundedTotalDuration(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let result = number.doubleValue
        guard result.isFinite,
              result >= 0,
              result <= ChatGPTAttentionBenchmarkCounters.maximumTotalDurationMilliseconds else {
            return nil
        }
        return result
    }
}

enum ChatGPTIncidentPageAppProbeOutcome: String, Equatable, Sendable {
    case success
    case unsupportedDocument = "unsupported_document"
    case bridgeUnavailable = "bridge_unavailable"
    case evaluationFailed = "evaluation_failed"
    case timeout
    case stale
}

struct ChatGPTIncidentPageAppEvent: Equatable, Sendable {
    let kind: String
    let category: String
    let errorCategory: String?
    let resourceType: String
    let httpStatus: Int?
    let durationBucket: String?
    let ageMilliseconds: Int

    func diagnosticFields(prefix: String) -> [String: RuntimeDiagnosticValue] {
        [
            "\(prefix)_kind": .string(kind),
            "\(prefix)_category": .string(category),
            "\(prefix)_error_category": errorCategory.map(RuntimeDiagnosticValue.string) ?? .null,
            "\(prefix)_resource_type": .string(resourceType),
            "\(prefix)_http_status": httpStatus.map { .integer(Int64($0)) } ?? .null,
            "\(prefix)_duration_bucket": durationBucket.map(RuntimeDiagnosticValue.string) ?? .null,
            "\(prefix)_age_ms": .integer(Int64(ageMilliseconds))
        ]
    }
}

struct ChatGPTIncidentPageAppProbeValues: Equatable, Sendable {
    static let maximumEvents = 16

    let events: [ChatGPTIncidentPageAppEvent]
    let droppedEvents: Int64
    let droppedEventsByKind: [String: Int64]
    let javascriptErrorCount: Int64
    let unhandledRejectionCount: Int64
    let resourceLoadFailureCount: Int64
    let resourceHTTPErrorCount: Int64
    let slowResourceCount: Int64
    let lifecycleEventCount: Int64
    let resourceTimingAvailable: Bool
    let responseStatusAvailable: Bool

    static func parse(_ value: Any, expectedDocumentToken: String) -> Self? {
        guard let fields = value as? [String: Any],
              fields["version"] as? Int == 1,
              fields["document_identity"] as? String == expectedDocumentToken,
              let rawEvents = fields["events"] as? [[String: Any]],
              rawEvents.count <= maximumEvents,
              let droppedEvents = boundedCounter(fields["dropped_events"]),
              let javascriptErrorCount = boundedCounter(fields["javascript_error_count"]),
              let unhandledRejectionCount = boundedCounter(fields["unhandled_rejection_count"]),
              let resourceLoadFailureCount = boundedCounter(fields["resource_load_failure_count"]),
              let resourceHTTPErrorCount = boundedCounter(fields["resource_http_error_count"]),
              let slowResourceCount = boundedCounter(fields["slow_resource_count"]),
              let lifecycleEventCount = boundedCounter(fields["lifecycle_event_count"]),
              let resourceTimingAvailable = fields["resource_timing_available"] as? Bool,
              let responseStatusAvailable = fields["response_status_available"] as? Bool else {
            return nil
        }

        let eventKinds = [
            "javascript_error", "unhandled_rejection", "resource_load_failure",
            "resource_http_error", "resource_timing", "lifecycle"
        ]
        var droppedEventsByKind: [String: Int64] = [:]
        for kind in eventKinds {
            let key = "dropped_\(kind)_events"
            if let rawCount = fields[key] {
                guard let count = boundedCounter(rawCount) else { return nil }
                droppedEventsByKind[kind] = count
            } else {
                droppedEventsByKind[kind] = 0
            }
        }

        let events = rawEvents.compactMap(parseEvent)
        guard events.count == rawEvents.count else { return nil }
        return Self(
            events: events,
            droppedEvents: droppedEvents,
            droppedEventsByKind: droppedEventsByKind,
            javascriptErrorCount: javascriptErrorCount,
            unhandledRejectionCount: unhandledRejectionCount,
            resourceLoadFailureCount: resourceLoadFailureCount,
            resourceHTTPErrorCount: resourceHTTPErrorCount,
            slowResourceCount: slowResourceCount,
            lifecycleEventCount: lifecycleEventCount,
            resourceTimingAvailable: resourceTimingAvailable,
            responseStatusAvailable: responseStatusAvailable
        )
    }

    var aggregateDiagnosticFields: [String: RuntimeDiagnosticValue] {
        var fields: [String: RuntimeDiagnosticValue] = [
            "page_app_event_count": .integer(Int64(events.count)),
            "page_app_dropped_event_count": .integer(Int64(droppedEvents)),
            "page_app_javascript_error_count": .integer(Int64(javascriptErrorCount)),
            "page_app_unhandled_rejection_count": .integer(Int64(unhandledRejectionCount)),
            "page_app_resource_load_failure_count": .integer(Int64(resourceLoadFailureCount)),
            "page_app_resource_http_error_count": .integer(Int64(resourceHTTPErrorCount)),
            "page_app_slow_resource_count": .integer(Int64(slowResourceCount)),
            "page_app_lifecycle_event_count": .integer(Int64(lifecycleEventCount)),
            "page_app_resource_timing_available": .bool(resourceTimingAvailable),
            "page_app_response_status_available": .bool(responseStatusAvailable),
            "page_app_handled_fetch_xhr_failure_observable": .bool(false),
            "page_app_capture_ring_capacity": .integer(Int64(Self.maximumEvents))
        ]
        for kind in [
            "javascript_error", "unhandled_rejection", "resource_load_failure",
            "resource_http_error", "resource_timing", "lifecycle"
        ] {
            fields["page_app_dropped_\(kind)_event_count"] = .integer(
                droppedEventsByKind[kind] ?? 0
            )
        }
        return fields
    }

    var diagnosticFields: [String: RuntimeDiagnosticValue] {
        var fields = aggregateDiagnosticFields
        for (index, event) in events.enumerated() {
            fields.merge(event.diagnosticFields(prefix: String(format: "page_app_event_%02d", index))) {
                _, new in new
            }
        }
        return fields
    }

    static let maximumCounter: Int64 = 9_007_199_254_740_991

    private static func boundedCounter(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber else { return nil }
        let result = number.int64Value
        guard result >= 0,
              result <= maximumCounter,
              number.doubleValue.isFinite,
              number.doubleValue == Double(result) else {
            return nil
        }
        return result
    }

    private static func parseEvent(_ raw: [String: Any]) -> ChatGPTIncidentPageAppEvent? {
        let kinds = ["javascript_error", "unhandled_rejection", "resource_load_failure", "resource_http_error", "resource_timing", "lifecycle"]
        let categories = [
            "global_error", "unhandled_rejection", "script_load", "style_load", "image_load", "frame_load", "other_resource_load",
            "http_error", "slow_resource", "visibility_visible", "visibility_hidden", "visibility_other",
            "page_show", "page_show_bfcache", "page_hide", "page_hide_bfcache", "online", "offline"
        ]
        let resourceTypes = ["none", "script", "style", "image", "iframe", "fetch", "xhr", "other"]
        let durationBuckets = ["1s_to_3s", "3s_to_10s", "10s_or_more"]
        let errorCategories = [
            "unknown", "syntax_error", "type_error", "reference_error", "range_error",
            "uri_error", "eval_error", "aggregate_error"
        ]
        guard let kind = raw["kind"] as? String, kinds.contains(kind),
              let category = raw["category"] as? String, categories.contains(category),
              let resourceType = raw["resource_type"] as? String, resourceTypes.contains(resourceType),
              let age = raw["age_ms"] as? Int, (0...86_400_000).contains(age) else {
            return nil
        }
        let errorCategory: String?
        if let value = raw["error_category"] as? String {
            guard errorCategories.contains(value) else { return nil }
            errorCategory = value
        } else if raw["error_category"] == nil || raw["error_category"] is NSNull {
            errorCategory = nil
        } else {
            return nil
        }
        let status: Int?
        if let value = raw["http_status"] as? Int {
            guard (400...599).contains(value) else { return nil }
            status = value
        } else if raw["http_status"] == nil || raw["http_status"] is NSNull {
            status = nil
        } else {
            return nil
        }
        let duration: String?
        if let value = raw["duration_bucket"] as? String {
            guard durationBuckets.contains(value) else { return nil }
            duration = value
        } else if raw["duration_bucket"] == nil || raw["duration_bucket"] is NSNull {
            duration = nil
        } else {
            return nil
        }
        return ChatGPTIncidentPageAppEvent(
            kind: kind,
            category: category,
            errorCategory: errorCategory,
            resourceType: resourceType,
            httpStatus: status,
            durationBucket: duration,
            ageMilliseconds: age
        )
    }
}

struct ChatGPTIncidentPageAppProbeResult: Equatable, Sendable {
    let outcome: ChatGPTIncidentPageAppProbeOutcome
    let values: ChatGPTIncidentPageAppProbeValues?
    let documentEpoch: UInt64?
    let latencyMilliseconds: Double
    let captureUptimeMilliseconds: Int64

    var longTermObservationDiagnosticFields: [String: RuntimeDiagnosticValue] {
        var fields: [String: RuntimeDiagnosticValue] = [
            "page_app_probe_outcome": .string(outcome.rawValue),
            "page_app_probe_latency_ms": .double(min(max(latencyMilliseconds, 0), 5_000)),
            "page_app_capture_uptime_ms": .integer(captureUptimeMilliseconds),
            "chatgpt_document_epoch": documentEpoch.map { .integer(Int64($0)) } ?? .null
        ]
        let aggregateFields = values?.aggregateDiagnosticFields ?? [
            "page_app_event_count": .null,
            "page_app_dropped_event_count": .null,
            "page_app_javascript_error_count": .null,
            "page_app_unhandled_rejection_count": .null,
            "page_app_resource_load_failure_count": .null,
            "page_app_resource_http_error_count": .null,
            "page_app_slow_resource_count": .null,
            "page_app_lifecycle_event_count": .null,
            "page_app_resource_timing_available": .null,
            "page_app_response_status_available": .null,
            "page_app_handled_fetch_xhr_failure_observable": .bool(false),
            "page_app_capture_ring_capacity": .integer(Int64(ChatGPTIncidentPageAppProbeValues.maximumEvents)),
            "page_app_dropped_javascript_error_event_count": .null,
            "page_app_dropped_unhandled_rejection_event_count": .null,
            "page_app_dropped_resource_load_failure_event_count": .null,
            "page_app_dropped_resource_http_error_event_count": .null,
            "page_app_dropped_resource_timing_event_count": .null,
            "page_app_dropped_lifecycle_event_count": .null
        ]
        fields.merge(aggregateFields) { _, new in new }
        return fields
    }

    var diagnosticFields: [String: RuntimeDiagnosticValue] {
        var fields = longTermObservationDiagnosticFields
        if let events = values?.events {
            for (index, event) in events.enumerated() {
                fields.merge(event.diagnosticFields(prefix: String(format: "page_app_event_%02d", index))) {
                    _, new in new
                }
            }
        }
        return fields
    }
}

/// Pure per-document baseline/transition reducer. The first observation for a
/// document establishes its baseline — an idle baseline can never synthesize a
/// finish — and duplicate states never re-emit, so noisy injected JS cannot
/// produce duplicate native observations even before the native-side checks.
struct ChatGPTDocumentGenerationTracker {
    private var hasBaseline = false
    private var isGenerating = false

    var diagnosticGeneratingState: Bool? {
        hasBaseline ? isGenerating : nil
    }

    mutating func observe(_ generating: Bool) -> ChatGPTAttentionObservation? {
        observeEvent(generating, responseIdentity: nil)?.observation
    }

    mutating func observeEvent(
        _ generating: Bool,
        responseIdentity: ChatGPTResponseIdentity?
    ) -> ChatGPTAttentionEvent? {
        guard hasBaseline else {
            hasBaseline = true
            isGenerating = generating
            return generating
                ? ChatGPTAttentionEvent(
                    observation: .generationStarted,
                    responseIdentity: nil
                )
                : nil
        }
        guard generating != isGenerating else { return nil }
        isGenerating = generating
        return ChatGPTAttentionEvent(
            observation: generating ? .generationStarted : .generationFinished,
            responseIdentity: generating ? nil : responseIdentity
        )
    }
}

/// Per-WKWebView ChatGPT generation sensor.
///
/// The bridge owns no business state. It validates incoming script messages,
/// reduces them to the document's generation baseline/transitions, and forwards
/// normalized observations only. Its lifetime follows the WKWebView it was
/// installed on: `WebViewPool` creates it before the WKWebView exists, the
/// Factory invokes `install(into:)` on the pre-creation user content
/// controller, and invalidation removes only this bridge's own message
/// handler so Factory scripts stay intact.
@MainActor
final class ChatGPTAttentionBridge: NSObject, WKScriptMessageHandler {
    static let contentWorldName = "FloatTabsChatGPTAttention"
    static let messageHandlerName = "floatTabsChatGPTAttention"
    static let defaultIncidentHealthProbeTimeout: TimeInterval = 5
    static let defaultLongTermWorkloadTimeout: TimeInterval = 5
    static let defaultLivenessProbeTimeout: TimeInterval = 2
    static let defaultCurrentDocumentResyncTimeout: TimeInterval = 2
    static let livenessWatchdogIntervalNanoseconds: UInt64 = 2_000_000_000
    static let livenessConfirmationDelayNanoseconds: UInt64 = 250_000_000
    static let livenessProbeScript = "globalThis.__floatTabsAttentionProbeV1?.()"
    static let benchmarkSnapshotScript = "globalThis.__floatTabsAttentionBenchmarkSnapshotV1?.()"

    typealias LivenessProbeProvider = @MainActor (WKWebView) async -> Any?
    typealias LivenessSleeper = @MainActor (UInt64) async -> Bool
    typealias CurrentDocumentResyncEvaluator = ChatGPTBenchmarkProbeEvaluator

    private static let productionIncidentHealthProbeEvaluator: ChatGPTIncidentHealthProbeEvaluator = {
        webView, script in
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(
                script,
                in: nil,
                in: ChatGPTAttentionBridge.contentWorld
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    private static let productionIncidentPageAppProbeEvaluator: ChatGPTIncidentPageAppProbeEvaluator = {
        webView, script, _ in
        try await ChatGPTAttentionBridge.productionIncidentHealthProbeEvaluator(webView, script)
    }

    private static let productionLivenessSleeper: LivenessSleeper = { nanoseconds in
        guard !Task.isCancelled else { return false }
        do {
            try await Task.sleep(nanoseconds: nanoseconds)
            return !Task.isCancelled
        } catch {
            return false
        }
    }

    private static let productionLivenessProbe: LivenessProbeProvider = { webView in
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(
                ChatGPTAttentionBridge.livenessProbeScript,
                in: nil,
                in: ChatGPTAttentionBridge.contentWorld
            ) { result in
                switch result {
                case let .success(value):
                    continuation.resume(returning: value)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static let productionBenchmarkProbeEvaluator: ChatGPTBenchmarkProbeEvaluator = {
        webView, script in
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(
                script,
                in: nil,
                in: ChatGPTAttentionBridge.contentWorld
            ) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// The single shared world instance used for both the injected script and
    /// the message handler. One instance is required: worlds with equal names
    /// are still distinct objects.
    static let contentWorld = WKContentWorld.world(name: contentWorldName)

    /// Test/diagnostic seam: the exact script injected into supported
    /// documents, generated by `makeScriptSource()` from Swift-owned
    /// constants.
    static let scriptSource = makeScriptSource()

    /// The explicit incident probe reads only fixed booleans and bounded
    /// document-state enums. It never serializes DOM text or page identity.
    static let incidentHealthProbeScript = """
    (() => {
      const ready = ["loading", "interactive", "complete"].includes(document.readyState)
        ? document.readyState : "other";
      const visibility = ["visible", "hidden", "prerender", "unloaded"].includes(document.visibilityState)
        ? document.visibilityState : "other";
      const shell = document.querySelector(
        'main, [data-testid="conversation-turn-list"], article[data-testid*="conversation-turn"]'
      );
      const composer = document.querySelector(
        '#prompt-textarea, textarea[aria-label="Message ChatGPT"], ' +
        '[contenteditable="true"][data-testid*="composer"], main [role="textbox"]'
      );
      const loading = document.querySelector(
        '[data-testid="stop-button"], [data-testid="fruitjuice-stop-button"], [aria-busy="true"]'
      );
      const pageError = document.querySelector(
        '[data-testid="conversation-error"], [data-testid="conversation-error-banner"], main [role="alert"]'
      );
      const isVisible = (element) => {
        if (!element || !element.isConnected || element.hidden ||
            element.getAttribute("aria-hidden") === "true" ||
            element.getClientRects().length === 0) return false;
        const style = getComputedStyle(element);
        return style.display !== "none" &&
          style.visibility !== "hidden" && style.visibility !== "collapse";
      };
      return {
        version: 1,
        document_ready_state: ready,
        visibility_state: visibility,
        conversation_shell_present: Boolean(shell),
        composer_present: Boolean(composer),
        loading_indicator_present: Boolean(loading),
        loading_indicator_visible: isVisible(loading),
        conversation_load_error_present: Boolean(pageError)
      };
    })()
    """

    /// Reads the fixed-size recorder installed in the isolated content world.
    /// Its result contains only allowlisted categories and coarse timing/status
    /// metadata; the opaque identity is consumed by the native stale guard.
    static let incidentPageAppProbeScript = """
    globalThis.__floatTabsPageAppDiagnosticSnapshotV1?.()
    """

    /// The injected script's early host gate, generated from the same
    /// `ChatGPTSitePolicy` constants used by native message validation and
    /// `SiteCompatibilityPolicy`. The script must never carry an
    /// independently maintained host list.
    static func hostGateExpression() -> String {
        let mainHost = ChatGPTSitePolicy.chatGPTHost
        return "host === \"\(mainHost)\""
            + " || host.endsWith(\".\(mainHost)\")"
            + " || host === \"\(ChatGPTSitePolicy.legacyChatHost)\""
    }

    private static func makeScriptSource() -> String {
        let hostGate = hostGateExpression()
#if DEBUG
        let defaultBenchmarkMeasurementEnabled = "false"
        let benchmarkConfigurationExport = """
          globalThis.__floatTabsAttentionBenchmarkConfigureV1 = (enabled, reset) => {
            if (reset === true) { resetBenchmarkCounters(); }
            if (typeof enabled === "boolean") {
              benchmarkMeasurementEnabled = enabled;
            }
            return {
              version: 1,
              token: TOKEN,
              enabled: benchmarkMeasurementEnabled
            };
          };
        """
#else
        let defaultBenchmarkMeasurementEnabled = "true"
        let benchmarkConfigurationExport = ""
#endif
        let benchmarkInitialization = """
          // These counters instrument existing attention work only. Release
          // enables them by default; Debug keeps its explicit benchmark
          // switch so tests and local experiments remain opt-in.
          const BENCHMARK_COUNTER_LIMIT = Number.MAX_SAFE_INTEGER;
          const BENCHMARK_DURATION_LIMIT_MS = 3600000;
          const BENCHMARK_TOTAL_DURATION_LIMIT_MS = Number.MAX_SAFE_INTEGER;
          let benchmarkMeasurementEnabled = \(defaultBenchmarkMeasurementEnabled);
          const benchmarkCounters = {
            mutation_callback_batch_count: 0,
            detector_schedule_count: 0,
            detector_evaluate_count: 0,
            detector_evaluate_total_ms: 0,
            detector_evaluate_max_ms: 0,
            response_identity_resolution_count: 0,
            response_identity_resolution_total_ms: 0,
            response_identity_resolution_max_ms: 0
          };
          const incrementBenchmarkCounter = (key) => {
            if (benchmarkCounters[key] < BENCHMARK_COUNTER_LIMIT) {
              benchmarkCounters[key] += 1;
            }
          };
          const boundedBenchmarkDuration = (duration) => {
            if (!Number.isFinite(duration)) { return 0; }
            return Math.min(Math.max(duration, 0), BENCHMARK_DURATION_LIMIT_MS);
          };
          const boundedBenchmarkTotal = (duration) => {
            if (!Number.isFinite(duration)) { return 0; }
            return Math.min(Math.max(duration, 0), BENCHMARK_TOTAL_DURATION_LIMIT_MS);
          };
          const recordBenchmarkDuration = (totalKey, maximumKey, duration) => {
            const bounded = boundedBenchmarkDuration(duration);
            benchmarkCounters[totalKey] = boundedBenchmarkTotal(
              benchmarkCounters[totalKey] + bounded
            );
            benchmarkCounters[maximumKey] = Math.max(
              benchmarkCounters[maximumKey], bounded
            );
          };
          const resetBenchmarkCounters = () => {
            for (const key of Object.keys(benchmarkCounters)) {
              benchmarkCounters[key] = 0;
            }
          };
        """
        let benchmarkIdentityResolver = """
          const resolveResponseIdentity = (root) => {
            if (!benchmarkMeasurementEnabled) {
              return canonicalResponseIdentityFor(root);
            }
            const startedAt = performance.now();
            try {
              return canonicalResponseIdentityFor(root);
            } finally {
              incrementBenchmarkCounter("response_identity_resolution_count");
              recordBenchmarkDuration(
                "response_identity_resolution_total_ms",
                "response_identity_resolution_max_ms",
                performance.now() - startedAt
              );
            }
          };
        """
        let benchmarkEvaluate = """
          const evaluate = () => {
            const measure = benchmarkMeasurementEnabled;
            const startedAt = measure ? performance.now() : 0;
            if (measure) { incrementBenchmarkCounter("detector_evaluate_count"); }
            try {
              const generating = isGenerating();
              if (generating === lastSent) { return; }
              post(generating);
              lastSent = generating;
            } finally {
              if (measure) {
                recordBenchmarkDuration(
                  "detector_evaluate_total_ms",
                  "detector_evaluate_max_ms",
                  performance.now() - startedAt
                );
              }
            }
          };
        """
        let benchmarkScheduleCounter = """
            if (benchmarkMeasurementEnabled) {
              incrementBenchmarkCounter("detector_schedule_count");
            }
        """
        let benchmarkMutationObserverCallback = """
          () => {
            if (benchmarkMeasurementEnabled) {
              incrementBenchmarkCounter("mutation_callback_batch_count");
            }
            schedule();
          }
        """
        let benchmarkExports = """
          \(benchmarkConfigurationExport)

          globalThis.__floatTabsAttentionBenchmarkSnapshotV1 = () => ({
            version: 1,
            token: TOKEN,
            enabled: benchmarkMeasurementEnabled,
            visibility_state: ["visible", "hidden", "prerender", "unloaded"].includes(document.visibilityState)
              ? document.visibilityState : "other",
            generating: isGenerating(),
            ...benchmarkCounters
          });
        """
        let responseIdentityResolver = "resolveResponseIdentity"
        return """
        (() => {
          "use strict";
          if (window.top !== window) { return; }
          const supportedHost = (host) => \(hostGate);
          if (!supportedHost(location.hostname)) { return; }
          const handler = () => {
            try {
              return window.webkit &&
                window.webkit.messageHandlers &&
                window.webkit.messageHandlers["floatTabsChatGPTAttention"];
            } catch (_) {
              return undefined;
            }
          };
          if (!handler()) { return; }

          const COALESCE_MS = 250;
          const TOKEN = (window.crypto && crypto.randomUUID)
            ? crypto.randomUUID()
            : "tok-" + Date.now().toString(36) + "-" +
              Math.random().toString(36).slice(2, 10);
          \(benchmarkInitialization)

          // Passive, bounded page-app observation. No application networking
          // or navigation API is replaced, and no event text or URL is read.
          const PAGE_EVENT_LIMIT = 16;
          const PAGE_COUNTER_LIMIT = Number.MAX_SAFE_INTEGER;
          const pageEvents = [];
          const pageCounts = {
            javascript_error_count: 0,
            unhandled_rejection_count: 0,
            resource_load_failure_count: 0,
            resource_http_error_count: 0,
            slow_resource_count: 0,
            lifecycle_event_count: 0
          };
          let pageDroppedEvents = 0;
          const pageDroppedEventsByKind = {
            javascript_error: 0,
            unhandled_rejection: 0,
            resource_load_failure: 0,
            resource_http_error: 0,
            resource_timing: 0,
            lifecycle: 0
          };
          let resourceTimingAvailable = false;
          let responseStatusAvailable = false;

          const incrementPageCount = (key) => {
            if (pageCounts[key] < PAGE_COUNTER_LIMIT) { pageCounts[key] += 1; }
          };
          const boundedUptime = () => Math.min(
            Math.max(Math.floor(performance.now()), 0),
            Number.MAX_SAFE_INTEGER
          );
          const boundedErrorCategory = (error) => {
            const name = error && typeof error.name === "string"
              ? error.name.toLowerCase() : "";
            const allowed = [
              "syntaxerror", "typeerror", "referenceerror", "rangeerror",
              "urierror", "evalerror", "aggregateerror"
            ];
            return allowed.includes(name) ? name.replace("error", "_error") : "unknown";
          };
          const errorProperty = ["e", "r", "r", "o", "r"].join("");
          const errorCategoryProperty = [
            "e", "r", "r", "o", "r", "_", "c", "a", "t", "e", "g", "o", "r", "y"
          ].join("");
          const pushPageEvent = (event) => {
            if (pageEvents.length === PAGE_EVENT_LIMIT) {
              const sameKindCount = pageEvents.filter((candidate) => candidate.kind === event.kind).length;
              let removeIndex = sameKindCount > 1
                ? pageEvents.findIndex((candidate) => candidate.kind === event.kind)
                : -1;
              const distinctKinds = new Set(pageEvents.map((candidate) => candidate.kind));
              if (removeIndex < 0 || distinctKinds.size === 1) {
                const duplicateIndex = pageEvents.findIndex((candidate, index) =>
                  pageEvents.filter((item) => item.kind === candidate.kind).length > 1
                    && index !== pageEvents.findIndex((item) => item.kind === candidate.kind)
                );
                removeIndex = duplicateIndex >= 0 ? duplicateIndex : 0;
              }
              const removed = pageEvents.splice(removeIndex, 1)[0];
              if (removed && Object.prototype.hasOwnProperty.call(pageDroppedEventsByKind, removed.kind) &&
                  pageDroppedEventsByKind[removed.kind] < PAGE_COUNTER_LIMIT) {
                pageDroppedEventsByKind[removed.kind] += 1;
              }
              if (pageDroppedEvents < PAGE_COUNTER_LIMIT) { pageDroppedEvents += 1; }
            }
            pageEvents.push({
              kind: event.kind,
              category: event.category,
              resource_type: event.resource_type || "none",
              http_status: Number.isInteger(event.http_status) ? event.http_status : null,
              duration_bucket: event.duration_bucket || null,
              error_category: event[errorCategoryProperty] || null,
              occurred_uptime_ms: boundedUptime()
            });
          };
          const resourceKind = (value) => {
            switch (value) {
              case "script": return "script";
              case "css": case "link": return "style";
              case "img": case "image": return "image";
              case "iframe": return "iframe";
              case "fetch": return "fetch";
              case "xmlhttprequest": return "xhr";
              default: return "other";
            }
          };
          const durationKind = (duration) => {
            if (duration >= 10000) { return "10s_or_more"; }
            if (duration >= 3000) { return "3s_to_10s"; }
            return "1s_to_3s";
          };
          const resourceFailureKind = (target) => {
            const localName = target && typeof target.localName === "string"
              ? target.localName.toLowerCase() : "";
            switch (localName) {
              case "script": return "script_load";
              case "link": return "style_load";
              case "img": return "image_load";
              case "iframe": return "frame_load";
              default: return "other_resource_load";
            }
          };

          window.addEventListener("error", (event) => {
            if (event.target === window) {
              incrementPageCount("javascript_error_count");
              pushPageEvent({
                kind: "javascript_error",
                category: "global_error",
                [errorCategoryProperty]: boundedErrorCategory(event && event[errorProperty])
              });
              return;
            }
            incrementPageCount("resource_load_failure_count");
            pushPageEvent({
              kind: "resource_load_failure",
              category: resourceFailureKind(event.target),
              resource_type: resourceKind(event.target && event.target.localName)
            });
          }, { capture: true, passive: true });

          window.addEventListener("unhandledrejection", () => {
            incrementPageCount("unhandled_rejection_count");
            pushPageEvent({ kind: "unhandled_rejection", category: "unhandled_rejection" });
          }, { passive: true });

          document.addEventListener("visibilitychange", () => {
            incrementPageCount("lifecycle_event_count");
            const state = document.visibilityState;
            pushPageEvent({
              kind: "lifecycle",
              category: state === "visible" ? "visibility_visible"
                : state === "hidden" ? "visibility_hidden" : "visibility_other"
            });
          }, { passive: true });
          window.addEventListener("pageshow", (event) => {
            if (event.persisted) {
              // A BFCache restore reuses the JavaScript document but represents
              // a new native navigation epoch. Drop prior-epoch recorder state.
              pageEvents.length = 0;
              pageDroppedEvents = 0;
              for (const key of Object.keys(pageDroppedEventsByKind)) { pageDroppedEventsByKind[key] = 0; }
              for (const key of Object.keys(pageCounts)) { pageCounts[key] = 0; }
            }
            incrementPageCount("lifecycle_event_count");
            pushPageEvent({ kind: "lifecycle", category: event.persisted ? "page_show_bfcache" : "page_show" });
          }, { passive: true });
          window.addEventListener("pagehide", (event) => {
            incrementPageCount("lifecycle_event_count");
            pushPageEvent({ kind: "lifecycle", category: event.persisted ? "page_hide_bfcache" : "page_hide" });
          }, { passive: true });
          window.addEventListener("online", () => {
            incrementPageCount("lifecycle_event_count");
            pushPageEvent({ kind: "lifecycle", category: "online" });
          }, { passive: true });
          window.addEventListener("offline", () => {
            incrementPageCount("lifecycle_event_count");
            pushPageEvent({ kind: "lifecycle", category: "offline" });
          }, { passive: true });

          try {
            const hasResponseStatus = typeof PerformanceResourceTiming !== "undefined" &&
              "responseStatus" in PerformanceResourceTiming.prototype;
            responseStatusAvailable = Boolean(hasResponseStatus);
            if (typeof PerformanceObserver !== "undefined") {
              const resourceObserver = new PerformanceObserver((list) => {
                for (const entry of list.getEntries()) {
                  const type = resourceKind(entry.initiatorType);
                  if (typeof entry.responseStatus === "number" &&
                      Number.isInteger(entry.responseStatus) &&
                      entry.responseStatus >= 400 && entry.responseStatus <= 599) {
                    incrementPageCount("resource_http_error_count");
                    pushPageEvent({
                      kind: "resource_http_error",
                      category: "http_error",
                      resource_type: type,
                      http_status: entry.responseStatus
                    });
                  }
                  if (typeof entry.duration === "number" && entry.duration >= 1000) {
                    incrementPageCount("slow_resource_count");
                    pushPageEvent({
                      kind: "resource_timing",
                      category: "slow_resource",
                      resource_type: type,
                      duration_bucket: durationKind(entry.duration)
                    });
                  }
                }
              });
              resourceObserver.observe({ type: "resource", buffered: true });
              resourceTimingAvailable = true;
            }
          } catch (_) {
            resourceTimingAvailable = false;
          }

          globalThis.__floatTabsPageAppDiagnosticSnapshotV1 = () => ({
            version: 1,
            document_identity: TOKEN,
            events: pageEvents.slice(0, PAGE_EVENT_LIMIT).map((event) => ({
              kind: event.kind,
              category: event.category,
              error_category: event[errorCategoryProperty] || null,
              resource_type: event.resource_type,
              http_status: event.http_status,
              duration_bucket: event.duration_bucket,
              age_ms: Math.min(
                Math.max(boundedUptime() - event.occurred_uptime_ms, 0),
                86400000
              )
            })),
            dropped_events: pageDroppedEvents,
            dropped_javascript_error_events: pageDroppedEventsByKind.javascript_error,
            dropped_unhandled_rejection_events: pageDroppedEventsByKind.unhandled_rejection,
            dropped_resource_load_failure_events: pageDroppedEventsByKind.resource_load_failure,
            dropped_resource_http_error_events: pageDroppedEventsByKind.resource_http_error,
            dropped_resource_timing_events: pageDroppedEventsByKind.resource_timing,
            dropped_lifecycle_events: pageDroppedEventsByKind.lifecycle,
            javascript_error_count: pageCounts.javascript_error_count,
            unhandled_rejection_count: pageCounts.unhandled_rejection_count,
            resource_load_failure_count: pageCounts.resource_load_failure_count,
            resource_http_error_count: pageCounts.resource_http_error_count,
            slow_resource_count: pageCounts.slow_resource_count,
            lifecycle_event_count: pageCounts.lifecycle_event_count,
            resource_timing_available: resourceTimingAvailable,
            response_status_available: responseStatusAvailable
          });

          let lastSent = null;
          let timer = null;
          let lastCheck = 0;
          let observer = null;

          const post = (generating) => {
            const target = handler();
            if (!target) { return; }
            const responseIdentity = generating
              ? null
              : \(responseIdentityResolver)(latestAssistantResponseRoot());
            target.postMessage({
              version: 1,
              kind: lastSent === null ? "baseline" : "state",
              token: TOKEN,
              generating: generating,
              responseIdentity: responseIdentity
            });
          };

          // A control counts only while it is actually presented: connected,
          // laying out at least one client rect, and not hidden through the
          // computed box model. Opacity and transforms are deliberately not
          // consulted — transient animations must not create false negatives.
          const isRendered = (element) => {
            if (!element.isConnected) { return false; }
            if (element.getClientRects().length === 0) { return false; }
            const style = window.getComputedStyle(element);
            if (style.display === "none") { return false; }
            const visibility = style.visibility;
            if (visibility === "hidden" || visibility === "collapse") {
              return false;
            }
            return true;
          };

          \(ChatGPTResponseIdentity.sharedDOMHelperSource)

          \(benchmarkIdentityResolver)
          \(benchmarkEvaluate)

          // Trailing coalescing: a burst of DOM mutations collapses into at most
          // one state read per window, while a sustained mutation stream (streamed
          // tokens) still gets periodic reads instead of postponing forever.
          const schedule = () => {
            \(benchmarkScheduleCounter)
            if (timer !== null) { return; }
            const wait = Math.max(0, COALESCE_MS - (Date.now() - lastCheck));
            timer = setTimeout(() => {
              timer = null;
              lastCheck = Date.now();
              evaluate();
            }, wait);
          };

          const startObserving = () => {
            if (observer || !document.documentElement) { return; }
            observer = new MutationObserver(\(benchmarkMutationObserverCallback));
            // Render-state transitions can arrive through attributes alone —
            // a control hidden or revealed by class/style/hidden mutations
            // without any node insertion or removal must still re-evaluate.
            // characterData is intentionally excluded: token streaming must
            // not add observation pressure.
            observer.observe(document.documentElement, {
              childList: true,
              subtree: true,
              attributes: true,
              attributeFilter: [
                "data-testid",
                "class",
                "style",
                "hidden",
                "aria-hidden",
                "aria-label",
                "title",
                "disabled",
                "aria-disabled"
              ]
            });
          };

          if (document.documentElement) {
            startObserving();
          } else {
            const boot = new MutationObserver(() => {
              if (document.documentElement) {
                boot.disconnect();
                startObserving();
              }
            });
            boot.observe(document, { childList: true });
          }

          document.addEventListener("DOMContentLoaded", schedule, { once: true });

          globalThis.__floatTabsAttentionProbeV1 = () => {
            const generating = isGenerating();
            const responseIdentity = generating
              ? null
              : \(responseIdentityResolver)(latestAssistantResponseRoot());
            return {
              version: 1,
              kind: "baseline",
              token: TOKEN,
              generating: generating,
              responseIdentity: responseIdentity
            };
          };

          // BFCache/history restoration does not rerun document-start injection.
          // A restored document re-reports its current state; the native side
          // also exposes a narrow same-world resync entry for the confirmed
          // current history item.
          window.addEventListener("pageshow", () => {
            lastSent = null;
            schedule();
          });

          globalThis.__floatTabsAttentionResyncV1 = () => {
            const generating = isGenerating();
            const responseIdentity = generating
              ? null
              : \(responseIdentityResolver)(latestAssistantResponseRoot());
            // The explicit resync returns the identity-bearing baseline to
            // native code directly. Keep the detector coalescer aligned so a
            // queued pageshow/mutation evaluation cannot create duplicate
            // native traffic for this same state.
            lastSent = generating;
            return {
              version: 1,
              kind: "baseline",
              token: TOKEN,
              generating: generating,
              responseIdentity: responseIdentity
            };
          };

          \(benchmarkExports)
        })();
        """
    }

    private struct DocumentSession {
        let token: String
        let epoch: UInt64
        var tracker = ChatGPTDocumentGenerationTracker()
    }

    private enum DocumentAdmission {
        case awaitingSupportedBaseline
        case activeSupportedDocument
        case unsupportedCurrentDocument
        case awaitingAuthorizedResync
    }

    /// A single in-flight Instant Back transition carries only the target's
    /// support classification and whether it should receive a fresh
    /// current-document resync. Attention state and document history never
    /// enter this marker.
    private struct PendingInstantBackHandoff {
        let shouldResyncCurrentDocument: Bool
        let targetIsKnownUnsupported: Bool
    }

    private struct PendingCurrentDocumentResync {
        let requestID: UUID
        let generation: UInt64
        let attempt: Int
        let webViewIdentity: ObjectIdentifier
        let physicalRuntimeEpoch: UInt64
    }

    private enum BoundedLivenessProbeResult {
        case value(Any?)
        case timedOut
        case suppressed

        var value: Any? {
            guard case let .value(value) = self else { return nil }
            return value
        }

        var didTimeOut: Bool {
            if case .timedOut = self { return true }
            return false
        }

        var wasSuppressed: Bool {
            if case .suppressed = self { return true }
            return false
        }
    }

    private enum PendingLivenessProbe {
        case active(
            physicalRuntimeEpoch: UInt64,
            role: String,
            startedAt: TimeInterval,
            continuation: CheckedContinuation<BoundedLivenessProbeResult, Never>
        )
        case timedOut(
            physicalRuntimeEpoch: UInt64,
            role: String,
            startedAt: TimeInterval
        )
    }

    private enum PendingLongTermWorkloadCapture {
        case active(
            id: UUID,
            continuation: CheckedContinuation<[String: Any], Never>
        )
        case timedOut(id: UUID)

        var id: UUID {
            switch self {
            case let .active(id, _):
                return id
            case let .timedOut(id):
                return id
            }
        }
    }

    private static let resyncAttemptLimit = 2
    private static let maximumOutstandingLivenessProbes = 2
    private static let maximumOutstandingCurrentDocumentResyncRequests = 2

    let slotID: UUID
    private let onObservation: @MainActor (UUID, ChatGPTAttentionObservation) -> Void
    private let onAttentionEvent: (@MainActor (UUID, ChatGPTAttentionEvent) -> Void)?
    private let onIncidentRequest: (@MainActor (UUID, RuntimeDiagnosticIncidentContext) -> Void)?
    private let diagnostics: any RuntimeDiagnosticRecording
    private let livenessProbe: LivenessProbeProvider
    private let livenessSleeper: LivenessSleeper
    private let incidentHealthProbeEvaluator: ChatGPTIncidentHealthProbeEvaluator
    private let incidentPageAppProbeEvaluator: ChatGPTIncidentPageAppProbeEvaluator
    private let incidentHealthProbeTimeout: TimeInterval
    private let longTermWorkloadTimeout: TimeInterval
    private let livenessProbeTimeout: TimeInterval
    private let currentDocumentResyncEvaluator: CurrentDocumentResyncEvaluator?
    private let currentDocumentResyncTimeout: TimeInterval
    private let benchmarkProbeEvaluator: ChatGPTBenchmarkProbeEvaluator
    private var benchmarkCounters = ChatGPTAttentionBenchmarkCounters()
    private var benchmarkOperationInFlight = false
    private weak var webView: WKWebView?
    private weak var userContentController: WKUserContentController?
    private var document: DocumentSession?
    /// The one runtime-only admission state. The current committed document,
    /// not a requested/provisional/persisted URL, controls whether a ChatGPT
    /// epoch may exist.
    private var documentAdmission = DocumentAdmission.awaitingSupportedBaseline
    private var pendingInstantBackHandoff: PendingInstantBackHandoff?
    private var pendingCurrentDocumentResync: PendingCurrentDocumentResync?
    private var currentDocumentResyncTimeoutTasks: [UUID: Task<Void, Never>] = [:]
    private var outstandingCurrentDocumentResyncRequestIDs = Set<UUID>()
    private var nextResyncGeneration: UInt64 = 0
    private var nextDocumentEpoch: UInt64 = 0
    /// Physical callback ownership is distinct from the semantic document
    /// epoch. It advances only at the authoritative WebContent termination
    /// seam, so ordinary didCommit/reset boundaries cannot manufacture
    /// capacity for callbacks that still belong to the same process.
    private var physicalRuntimeEpoch: UInt64 = 1
    private var livenessWatchdogTask: Task<Void, Never>?
    private var livenessWatchdogGeneration: UInt64 = 0
    private var livenessGeneration: UInt64 = 0
    private var livenessCycleOwnerGeneration: UInt64?
    private var livenessIdleCandidateOwnerGeneration: UInt64?
    private var pendingLivenessProbes: [UUID: PendingLivenessProbe] = [:]
    private var livenessProbeTimeoutTasks: [UUID: Task<Void, Never>] = [:]
    private var activeLivenessIncidentContext: RuntimeDiagnosticIncidentContext?
    private var activeResyncIncidentContext: RuntimeDiagnosticIncidentContext?
    private var livenessIncidentSnapshotRequested = false
    private var resyncIncidentSnapshotRequested = false
    private var pendingIncidentHealthProbeID: UUID?
    private var incidentHealthProbeTimeoutTask: Task<Void, Never>?
    private var pendingIncidentPageAppProbeID: UUID?
    private var incidentPageAppProbeTimeoutTask: Task<Void, Never>?
    private var pendingLongTermWorkloadCapture: PendingLongTermWorkloadCapture?
    private var longTermWorkloadTimeoutTask: Task<Void, Never>?
#if DEBUG
    private(set) var debugLivenessWatchdogStartCount = 0
#endif
    private(set) var isInvalidated = false

    /// Whether a transient Instant Back baseline handoff is awaiting either
    /// cancellation or authoritative current-history confirmation.
    var isInstantBackHandoffPending: Bool {
        pendingInstantBackHandoff != nil
    }

    /// Content-free view of the bridge-owned current document. The opaque
    /// document token is deliberately never projected into diagnostics.
    var diagnosticSnapshotFields: [String: RuntimeDiagnosticValue] {
        let isActiveDocument: Bool
        if case .activeSupportedDocument = documentAdmission {
            isActiveDocument = true
        } else {
            isActiveDocument = false
        }
        let admitted = isActiveDocument && document != nil
        var fields: [String: RuntimeDiagnosticValue] = [
            "attention_document_admitted": .bool(admitted),
            "chatgpt_document_epoch": document.map {
                .integer(Int64($0.epoch))
            } ?? .null,
            "chatgpt_generating": document?.tracker.diagnosticGeneratingState.map {
                .bool($0)
            } ?? .null
        ]
        switch documentAdmission {
        case .awaitingSupportedBaseline:
            fields["attention_document_admission"] = .string("awaiting_supported_baseline")
        case .activeSupportedDocument:
            fields["attention_document_admission"] = .string("active_supported_document")
        case .unsupportedCurrentDocument:
            fields["attention_document_admission"] = .string("unsupported_current_document")
        case .awaitingAuthorizedResync:
            fields["attention_document_admission"] = .string("awaiting_authorized_resync")
        }
        return fields
    }

    /// Performs one explicit incident-only DOM snapshot in the same isolated
    /// content world as the attention bridge. The opaque document token is
    /// used only as an in-memory stale guard and is never returned or logged.
    func captureIncidentHealthSnapshot(
        for expectedWebView: WKWebView,
        contextIsCurrent: @escaping @MainActor () -> Bool,
        completion: @escaping @MainActor (ChatGPTIncidentHealthProbeResult) -> Void
    ) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        if !isInvalidated,
           case .unsupportedCurrentDocument = documentAdmission {
            completion(Self.incidentHealthResult(
                outcome: .unsupportedDocument,
                values: nil,
                document: nil,
                startedAt: startedAt
            ))
            return
        }
        guard !isInvalidated,
              let attachedWebView = webView,
              attachedWebView === expectedWebView,
              case .activeSupportedDocument = documentAdmission,
              let document else {
            completion(Self.incidentHealthResult(
                outcome: .bridgeUnavailable,
                values: nil,
                document: nil,
                startedAt: startedAt
            ))
            return
        }
        guard contextIsCurrent() else {
            completion(Self.incidentHealthResult(
                outcome: .stale,
                values: nil,
                document: nil,
                startedAt: startedAt
            ))
            return
        }
        guard pendingIncidentHealthProbeID == nil else {
            completion(Self.incidentHealthResult(
                outcome: .bridgeUnavailable,
                values: nil,
                document: nil,
                startedAt: startedAt
            ))
            return
        }

        let probeID = UUID()
        let expectedDocumentEpoch = document.epoch
        let expectedDocumentToken = document.token
        pendingIncidentHealthProbeID = probeID
        let timeoutNanoseconds = UInt64(incidentHealthProbeTimeout * 1_000_000_000)
        incidentHealthProbeTimeoutTask = Task { @MainActor [weak self, weak expectedWebView] in
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }
            guard let self, let expectedWebView else { return }
            self.finishIncidentHealthProbe(
                id: probeID,
                webView: expectedWebView,
                documentEpoch: expectedDocumentEpoch,
                documentToken: expectedDocumentToken,
                contextIsCurrent: contextIsCurrent,
                outcome: .timeout,
                values: nil,
                startedAt: startedAt,
                completion: completion
            )
        }

        Task { @MainActor [weak self, weak expectedWebView] in
            guard let self, let expectedWebView else { return }
            do {
                let value = try await self.incidentHealthProbeEvaluator(
                    expectedWebView,
                    Self.incidentHealthProbeScript
                )
                let values = ChatGPTIncidentHealthProbeValues.parse(value)
                self.finishIncidentHealthProbe(
                    id: probeID,
                    webView: expectedWebView,
                    documentEpoch: expectedDocumentEpoch,
                    documentToken: expectedDocumentToken,
                    contextIsCurrent: contextIsCurrent,
                    outcome: values == nil ? .evaluationFailed : .success,
                    values: values,
                    startedAt: startedAt,
                    completion: completion
                )
            } catch {
                self.finishIncidentHealthProbe(
                    id: probeID,
                    webView: expectedWebView,
                    documentEpoch: expectedDocumentEpoch,
                    documentToken: expectedDocumentToken,
                    contextIsCurrent: contextIsCurrent,
                    outcome: .evaluationFailed,
                    values: nil,
                    startedAt: startedAt,
                    completion: completion
                )
            }
        }
    }

    private func finishIncidentHealthProbe(
        id: UUID,
        webView expectedWebView: WKWebView,
        documentEpoch expectedDocumentEpoch: UInt64,
        documentToken expectedDocumentToken: String,
        contextIsCurrent: @escaping @MainActor () -> Bool,
        outcome: ChatGPTIncidentHealthProbeOutcome,
        values: ChatGPTIncidentHealthProbeValues?,
        startedAt: TimeInterval,
        completion: @escaping @MainActor (ChatGPTIncidentHealthProbeResult) -> Void
    ) {
        guard pendingIncidentHealthProbeID == id else { return }
        let currentDocumentMatches: Bool
        if case .activeSupportedDocument = documentAdmission,
           let document {
            currentDocumentMatches = document.epoch == expectedDocumentEpoch
                && document.token == expectedDocumentToken
        } else {
            currentDocumentMatches = false
        }
        let isCurrent = !isInvalidated
            && self.webView === expectedWebView
            && currentDocumentMatches
            && contextIsCurrent()

        incidentHealthProbeTimeoutTask?.cancel()
        incidentHealthProbeTimeoutTask = nil
        pendingIncidentHealthProbeID = nil
        let finalOutcome: ChatGPTIncidentHealthProbeOutcome = isCurrent ? outcome : .stale
        let finalValues = finalOutcome == .success ? values : nil
        completion(Self.incidentHealthResult(
            outcome: finalOutcome,
            values: finalValues,
            document: isCurrent ? document : nil,
            startedAt: startedAt
        ))
    }

    /// Performs one explicit read of the document-local passive recorder. Its
    /// result is accepted only for the captured document token, epoch, WebView,
    /// and caller-owned runtime/navigation context.
    func captureIncidentPageAppDiagnostics(
        for expectedWebView: WKWebView,
        contextIsCurrent: @escaping @MainActor () -> Bool,
        completion: @escaping @MainActor (ChatGPTIncidentPageAppProbeResult) -> Void
    ) {
        let startedAt = ProcessInfo.processInfo.systemUptime
        if !isInvalidated,
           case .unsupportedCurrentDocument = documentAdmission {
            completion(Self.pageAppResult(
                outcome: .unsupportedDocument,
                values: nil,
                document: nil,
                startedAt: startedAt
            ))
            return
        }
        guard !isInvalidated,
              let attachedWebView = webView,
              attachedWebView === expectedWebView,
              case .activeSupportedDocument = documentAdmission,
              let document else {
            completion(Self.pageAppResult(
                outcome: .bridgeUnavailable,
                values: nil,
                document: nil,
                startedAt: startedAt
            ))
            return
        }
        guard contextIsCurrent() else {
            completion(Self.pageAppResult(
                outcome: .stale,
                values: nil,
                document: nil,
                startedAt: startedAt
            ))
            return
        }
        guard pendingIncidentPageAppProbeID == nil else {
            completion(Self.pageAppResult(
                outcome: .bridgeUnavailable,
                values: nil,
                document: nil,
                startedAt: startedAt
            ))
            return
        }

        let probeID = UUID()
        let expectedDocumentEpoch = document.epoch
        let expectedDocumentToken = document.token
        pendingIncidentPageAppProbeID = probeID
        let timeoutNanoseconds = UInt64(incidentHealthProbeTimeout * 1_000_000_000)
        incidentPageAppProbeTimeoutTask = Task { @MainActor [weak self, weak expectedWebView] in
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }
            guard let self, let expectedWebView else { return }
            self.finishIncidentPageAppProbe(
                id: probeID,
                webView: expectedWebView,
                documentEpoch: expectedDocumentEpoch,
                documentToken: expectedDocumentToken,
                contextIsCurrent: contextIsCurrent,
                outcome: .timeout,
                values: nil,
                startedAt: startedAt,
                completion: completion
            )
        }

        Task { @MainActor [weak self, weak expectedWebView] in
            guard let self, let expectedWebView else { return }
            do {
                let value = try await self.incidentPageAppProbeEvaluator(
                    expectedWebView,
                    Self.incidentPageAppProbeScript,
                    expectedDocumentToken
                )
                let returnedIdentity = (value as? [String: Any])?["document_identity"] as? String
                let values = ChatGPTIncidentPageAppProbeValues.parse(
                    value,
                    expectedDocumentToken: expectedDocumentToken
                )
                let outcome: ChatGPTIncidentPageAppProbeOutcome
                if returnedIdentity != expectedDocumentToken {
                    outcome = .stale
                } else {
                    outcome = values == nil ? .evaluationFailed : .success
                }
                self.finishIncidentPageAppProbe(
                    id: probeID,
                    webView: expectedWebView,
                    documentEpoch: expectedDocumentEpoch,
                    documentToken: expectedDocumentToken,
                    contextIsCurrent: contextIsCurrent,
                    outcome: outcome,
                    values: values,
                    startedAt: startedAt,
                    completion: completion
                )
            } catch {
                self.finishIncidentPageAppProbe(
                    id: probeID,
                    webView: expectedWebView,
                    documentEpoch: expectedDocumentEpoch,
                    documentToken: expectedDocumentToken,
                    contextIsCurrent: contextIsCurrent,
                    outcome: .evaluationFailed,
                    values: nil,
                    startedAt: startedAt,
                    completion: completion
                )
            }
        }
    }

    private func finishIncidentPageAppProbe(
        id: UUID,
        webView expectedWebView: WKWebView,
        documentEpoch expectedDocumentEpoch: UInt64,
        documentToken expectedDocumentToken: String,
        contextIsCurrent: @escaping @MainActor () -> Bool,
        outcome: ChatGPTIncidentPageAppProbeOutcome,
        values: ChatGPTIncidentPageAppProbeValues?,
        startedAt: TimeInterval,
        completion: @escaping @MainActor (ChatGPTIncidentPageAppProbeResult) -> Void
    ) {
        guard pendingIncidentPageAppProbeID == id else { return }
        let currentDocumentMatches: Bool
        if case .activeSupportedDocument = documentAdmission,
           let document {
            currentDocumentMatches = document.epoch == expectedDocumentEpoch
                && document.token == expectedDocumentToken
        } else {
            currentDocumentMatches = false
        }
        let isCurrent = !isInvalidated
            && self.webView === expectedWebView
            && currentDocumentMatches
            && contextIsCurrent()

        incidentPageAppProbeTimeoutTask?.cancel()
        incidentPageAppProbeTimeoutTask = nil
        pendingIncidentPageAppProbeID = nil
        let finalOutcome: ChatGPTIncidentPageAppProbeOutcome = isCurrent ? outcome : .stale
        completion(Self.pageAppResult(
            outcome: finalOutcome,
            values: finalOutcome == .success ? values : nil,
            document: isCurrent ? document : nil,
            startedAt: startedAt
        ))
    }

    private static func incidentHealthResult(
        outcome: ChatGPTIncidentHealthProbeOutcome,
        values: ChatGPTIncidentHealthProbeValues?,
        document: DocumentSession?,
        startedAt: TimeInterval
    ) -> ChatGPTIncidentHealthProbeResult {
        ChatGPTIncidentHealthProbeResult(
            outcome: outcome,
            values: values,
            documentEpoch: document?.epoch,
            generating: document?.tracker.diagnosticGeneratingState,
            latencyMilliseconds: min(
                max(ProcessInfo.processInfo.systemUptime - startedAt, 0) * 1_000,
                5_000
            )
        )
    }

    private static func pageAppResult(
        outcome: ChatGPTIncidentPageAppProbeOutcome,
        values: ChatGPTIncidentPageAppProbeValues?,
        document: DocumentSession?,
        startedAt: TimeInterval
    ) -> ChatGPTIncidentPageAppProbeResult {
        ChatGPTIncidentPageAppProbeResult(
            outcome: outcome,
            values: values,
            documentEpoch: document?.epoch,
            latencyMilliseconds: min(
                max(ProcessInfo.processInfo.systemUptime - startedAt, 0) * 1_000,
                5_000
            ),
            captureUptimeMilliseconds: Int64(max(startedAt * 1_000, 0))
        )
    }

    init(
        slotID: UUID,
        onObservation: @escaping @MainActor (UUID, ChatGPTAttentionObservation) -> Void,
        diagnostics: any RuntimeDiagnosticRecording = RuntimeDiagnosticNoopRecorder(),
        livenessProbe: LivenessProbeProvider? = nil,
        livenessSleeper: LivenessSleeper? = nil,
        incidentHealthProbeEvaluator: ChatGPTIncidentHealthProbeEvaluator? = nil,
        incidentPageAppProbeEvaluator: ChatGPTIncidentPageAppProbeEvaluator? = nil,
        benchmarkProbeEvaluator: ChatGPTBenchmarkProbeEvaluator? = nil,
        incidentHealthProbeTimeout: TimeInterval = ChatGPTAttentionBridge.defaultIncidentHealthProbeTimeout,
        longTermWorkloadTimeout: TimeInterval = ChatGPTAttentionBridge.defaultLongTermWorkloadTimeout,
        livenessProbeTimeout: TimeInterval = ChatGPTAttentionBridge.defaultLivenessProbeTimeout,
        currentDocumentResyncEvaluator: CurrentDocumentResyncEvaluator? = nil,
        currentDocumentResyncTimeout: TimeInterval = ChatGPTAttentionBridge.defaultCurrentDocumentResyncTimeout,
        onAttentionEvent: (@MainActor (UUID, ChatGPTAttentionEvent) -> Void)? = nil,
        onIncidentRequest: (@MainActor (UUID, RuntimeDiagnosticIncidentContext) -> Void)? = nil
    ) {
        self.slotID = slotID
        self.onObservation = onObservation
        self.onAttentionEvent = onAttentionEvent
        self.onIncidentRequest = onIncidentRequest
        self.diagnostics = diagnostics
        self.livenessProbe = livenessProbe ?? Self.productionLivenessProbe
        self.livenessSleeper = livenessSleeper ?? Self.productionLivenessSleeper
        self.incidentHealthProbeEvaluator = incidentHealthProbeEvaluator
            ?? Self.productionIncidentHealthProbeEvaluator
        self.incidentPageAppProbeEvaluator = incidentPageAppProbeEvaluator
            ?? Self.productionIncidentPageAppProbeEvaluator
        self.benchmarkProbeEvaluator = benchmarkProbeEvaluator
            ?? Self.productionBenchmarkProbeEvaluator
        self.incidentHealthProbeTimeout = min(
            max(incidentHealthProbeTimeout, 0),
            Self.defaultIncidentHealthProbeTimeout
        )
        self.longTermWorkloadTimeout = min(
            max(longTermWorkloadTimeout, 0),
            Self.defaultLongTermWorkloadTimeout
        )
        self.livenessProbeTimeout = min(
            max(livenessProbeTimeout, 0.001),
            Self.defaultLivenessProbeTimeout
        )
        self.currentDocumentResyncEvaluator = currentDocumentResyncEvaluator
        self.currentDocumentResyncTimeout = min(
            max(currentDocumentResyncTimeout, 0.001),
            Self.defaultCurrentDocumentResyncTimeout
        )
        super.init()
    }

    // MARK: Installation

    /// Adds the document-start main-frame script and the same-world message
    /// handler. Must run on the Factory-owned `WKUserContentController` before
    /// the WKWebView is constructed so `.atDocumentStart` is reliable for the
    /// first load.
    func install(into userContentController: WKUserContentController) {
        guard !isInvalidated else { return }
        userContentController.addUserScript(
            WKUserScript(
                source: Self.scriptSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: Self.contentWorld
            )
        )
        userContentController.add(
            self,
            contentWorld: Self.contentWorld,
            name: Self.messageHandlerName
        )
        self.userContentController = userContentController
    }

    func attach(to webView: WKWebView) {
        guard !isInvalidated else { return }
        if let previousWebView = self.webView,
           previousWebView !== webView {
            handleRuntimeReplacement()
        }
        self.webView = webView
    }

#if DEBUG
    /// Configures the current document's in-memory benchmark counters. The
    /// opaque token is checked here and never appears in the returned fields.
    @MainActor
    func configureBenchmarkMeasurement(
        enabled: Bool?,
        reset: Bool,
        for expectedWebView: WKWebView,
        runtimeIdentity: WebRuntimeDiagnosticIdentity,
        navigationGeneration: UInt64?,
        contextIsCurrent: @escaping @MainActor () -> Bool
    ) async -> [String: Any] {
        guard !benchmarkOperationInFlight else {
            return benchmarkUnavailable(reason: "operation_in_flight")
        }
        guard let expectedDocument = currentBenchmarkDocument(for: expectedWebView) else {
            return benchmarkUnavailable(reason: "document_unavailable")
        }
        guard contextIsCurrent() else {
            return benchmarkStale(reason: "stale_context")
        }

        benchmarkOperationInFlight = true
        defer { benchmarkOperationInFlight = false }
        if reset { benchmarkCounters.resetValues() }

        let enabledArgument = enabled.map { $0 ? "true" : "false" } ?? "undefined"
        let resetArgument = reset ? "true" : "false"
        let script = "globalThis.__floatTabsAttentionBenchmarkConfigureV1?.(\(enabledArgument), \(resetArgument))"
        do {
            let value = try await benchmarkProbeEvaluator(expectedWebView, script)
            guard benchmarkContextMatches(
                expectedWebView: expectedWebView,
                expectedDocument: expectedDocument,
                contextIsCurrent: contextIsCurrent
            ) else {
                return benchmarkStale(reason: "stale_context")
            }
            guard let fields = value as? [String: Any],
                  fields["version"] as? Int == 1,
                  let returnedToken = fields["token"] as? String,
                  let returnedEnabled = fields["enabled"] as? Bool else {
                return benchmarkUnavailable(reason: "evaluation_failed")
            }
            guard returnedToken == expectedDocument.token else {
                return benchmarkStale(reason: "stale_document")
            }
            guard enabled.map({ $0 == returnedEnabled }) ?? true else {
                return benchmarkUnavailable(reason: "measurement_state_mismatch")
            }
            benchmarkCounters.setEnabled(returnedEnabled)
            var result = benchmarkRuntimeFields(
                runtimeIdentity: runtimeIdentity,
                navigationGeneration: navigationGeneration
            )
            result["status"] = "ok"
            result["measurement_enabled"] = returnedEnabled
            result["document_epoch"] = expectedDocument.epoch
            return result
        } catch {
            return benchmarkUnavailable(reason: "evaluation_failed")
        }
    }
#endif

    /// Reads only bounded scalar values from the current isolated document.
    /// It rejects a callback if the Slot runtime, navigation, WebView, document
    /// epoch, or opaque document token changed while evaluation was in flight.
    @MainActor
    func captureBenchmarkSnapshot(
        for expectedWebView: WKWebView,
        runtimeIdentity: WebRuntimeDiagnosticIdentity,
        navigationGeneration: UInt64?,
        contextIsCurrent: @escaping @MainActor () -> Bool
    ) async -> [String: Any] {
        guard !benchmarkOperationInFlight else {
            return benchmarkUnavailable(reason: "operation_in_flight")
        }
        guard let expectedDocument = currentBenchmarkDocument(for: expectedWebView) else {
            return benchmarkUnavailable(reason: "document_unavailable")
        }
        guard contextIsCurrent() else {
            return benchmarkStale(reason: "stale_context")
        }

        benchmarkOperationInFlight = true
        defer { benchmarkOperationInFlight = false }
        let startedAt = ProcessInfo.processInfo.systemUptime
        do {
            let value = try await benchmarkProbeEvaluator(
                expectedWebView,
                Self.benchmarkSnapshotScript
            )
            let roundTripMilliseconds = ChatGPTAttentionBenchmarkCounters.boundedDuration(
                (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            )
            guard benchmarkContextMatches(
                expectedWebView: expectedWebView,
                expectedDocument: expectedDocument,
                contextIsCurrent: contextIsCurrent
            ) else {
                return benchmarkStale(reason: "stale_context")
            }
            guard let values = ChatGPTAttentionBenchmarkDocumentValues.parse(value) else {
                return benchmarkUnavailable(reason: "evaluation_failed")
            }
            guard values.token == expectedDocument.token else {
                return benchmarkStale(reason: "stale_document")
            }
            guard values.enabled == benchmarkCounters.isEnabled else {
                return benchmarkUnavailable(reason: "measurement_state_mismatch")
            }

            var result = benchmarkRuntimeFields(
                runtimeIdentity: runtimeIdentity,
                navigationGeneration: navigationGeneration
            )
            result["status"] = "ok"
            result["slot_id"] = slotID.uuidString
            result["measurement_enabled"] = benchmarkCounters.isEnabled
            result["document_epoch"] = expectedDocument.epoch
            result["js_roundtrip_latency_ms"] = round(roundTripMilliseconds * 1000) / 1000
            result["captured_uptime_ms"] = Int64(max(startedAt * 1_000, 0))
            result.merge(values.fields) { _, new in new }
            result.merge(benchmarkCounters.fields) { _, new in new }
            return result
        } catch {
            return benchmarkUnavailable(reason: "evaluation_failed")
        }
    }

    /// Adapts the existing benchmark snapshot seam into Release-safe,
    /// content-free periodic fields. This is a read of counters maintained by
    /// the already-installed attention observer; it does not add an observer,
    /// timer, polling loop, or separate sampling cadence.
    @MainActor
    func captureLongTermWorkloadDiagnosticFields(
        for expectedWebView: WKWebView,
        runtimeIdentity: WebRuntimeDiagnosticIdentity,
        navigationGeneration: UInt64?,
        contextIsCurrent: @escaping @MainActor () -> Bool
    ) async -> [String: RuntimeDiagnosticValue] {
        guard pendingLongTermWorkloadCapture == nil else {
            var fields = Self.longTermWorkloadStatusFields(
                status: "suppressed",
                reason: "pending_request_budget"
            )
            fields.merge(nativeAttentionHealthDiagnosticFields()) { _, new in new }
            return fields
        }
        guard !benchmarkOperationInFlight else {
            var fields = Self.longTermWorkloadStatusFields(
                status: "suppressed",
                reason: "benchmark_operation_in_flight"
            )
            fields.merge(nativeAttentionHealthDiagnosticFields()) { _, new in new }
            return fields
        }

        let requestID = UUID()
        let raw = await withCheckedContinuation { continuation in
            pendingLongTermWorkloadCapture = .active(
                id: requestID,
                continuation: continuation
            )
            let timeoutNanoseconds = UInt64(longTermWorkloadTimeout * 1_000_000_000)
            longTermWorkloadTimeoutTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                } catch {
                    return
                }
                self?.finishLongTermWorkloadCapture(
                    id: requestID,
                    raw: [
                        "status": "timeout",
                        "reason": "deadline_exceeded",
                        "measurement_enabled": self?.benchmarkCounters.isEnabled ?? false
                    ],
                    timedOut: true
                )
            }
            Task { @MainActor [weak self, weak expectedWebView] in
                guard let self else {
                    continuation.resume(returning: [
                        "status": "evaluation_failed",
                        "reason": "bridge_unavailable"
                    ])
                    return
                }
                guard let expectedWebView else {
                    self.finishLongTermWorkloadCapture(
                        id: requestID,
                        raw: [
                            "status": "evaluation_failed",
                            "reason": "webview_unavailable"
                        ],
                        timedOut: false
                    )
                    return
                }
                let result = await self.captureBenchmarkSnapshot(
                    for: expectedWebView,
                    runtimeIdentity: runtimeIdentity,
                    navigationGeneration: navigationGeneration,
                    contextIsCurrent: contextIsCurrent
                )
                self.finishLongTermWorkloadCapture(
                    id: requestID,
                    raw: result,
                    timedOut: false
                )
            }
        }
        var fields = Self.longTermWorkloadDiagnosticFields(from: raw)
        fields.merge(nativeAttentionHealthDiagnosticFields()) { _, new in new }
        return fields
    }

    /// Completes one bounded workload request. A timeout resumes the caller
    /// immediately but retains the timed-out request marker until its WebKit
    /// completion returns, so a stuck callback cannot be replaced by an
    /// unbounded queue of additional requests.
    private func finishLongTermWorkloadCapture(
        id: UUID,
        raw: [String: Any],
        timedOut: Bool
    ) {
        guard let pendingLongTermWorkloadCapture,
              pendingLongTermWorkloadCapture.id == id else {
            return
        }

        switch pendingLongTermWorkloadCapture {
        case let .active(_, continuation):
            longTermWorkloadTimeoutTask?.cancel()
            longTermWorkloadTimeoutTask = nil
            self.pendingLongTermWorkloadCapture = timedOut
                ? .timedOut(id: id)
                : nil
            continuation.resume(returning: raw)
        case .timedOut:
            // The caller already received the timeout outcome. This is the
            // late WebKit completion boundary: release the single outstanding
            // request budget, but never invoke or overwrite the old outcome.
            guard !timedOut else { return }
            self.pendingLongTermWorkloadCapture = nil
        }
    }

    private static func longTermWorkloadStatusFields(
        status: String,
        reason: String
    ) -> [String: RuntimeDiagnosticValue] {
        [
            "attention_workload_probe_status": .string(status),
            "attention_workload_probe_reason": .string(reason)
        ]
    }

    /// Projects the bounded native health counters independently of the page
    /// snapshot. Standard diagnostics must retain these fields when a sample
    /// is unavailable, stale, timed out, suppressed, or otherwise unable to
    /// produce document content.
    private func nativeAttentionHealthDiagnosticFields() -> [String: RuntimeDiagnosticValue] {
        [
            "attention_liveness_timeout_count": .integer(benchmarkCounters.livenessTimeoutCount),
            "attention_liveness_suppression_count": .integer(benchmarkCounters.livenessSuppressionCount),
            "attention_resync_timeout_count": .integer(benchmarkCounters.currentDocumentResyncTimeoutCount),
            "attention_resync_suppression_count": .integer(benchmarkCounters.currentDocumentResyncSuppressionCount)
        ]
    }

    private static func longTermWorkloadDiagnosticFields(
        from raw: [String: Any]
    ) -> [String: RuntimeDiagnosticValue] {
        var fields: [String: RuntimeDiagnosticValue] = [:]
        if let rawStatus = raw["status"] as? String {
            let status = rawStatus == "unavailable"
                && raw["reason"] as? String == "operation_in_flight"
                ? "suppressed"
                : rawStatus
            fields["attention_workload_probe_status"] = .string(status)
        }
        if let reason = raw["reason"] as? String {
            fields["attention_workload_probe_reason"] = .string(reason)
        }

        let integerKeys = [
            "document_epoch": "attention_workload_document_epoch",
            "mutation_callback_batch_count": "attention_mutation_callback_batch_count",
            "detector_schedule_count": "attention_detector_schedule_count",
            "detector_evaluate_count": "attention_detector_evaluate_count",
            "response_identity_resolution_count": "attention_response_resolution_count",
            "liveness_probe_count": "attention_liveness_probe_count",
            "confirmation_probe_count": "attention_confirmation_probe_count",
            "liveness_failure_count": "attention_liveness_failure_count",
            "recovered_completion_count": "attention_recovered_completion_count",
            "liveness_timeout_count": "attention_liveness_timeout_count",
            "liveness_suppression_count": "attention_liveness_suppression_count",
            "current_document_resync_timeout_count": "attention_resync_timeout_count",
            "current_document_resync_suppression_count": "attention_resync_suppression_count",
            "captured_uptime_ms": "attention_workload_captured_uptime_ms"
        ]
        let doubleKeys = [
            "js_roundtrip_latency_ms": "attention_workload_js_roundtrip_latency_ms",
            "detector_evaluate_total_ms": "attention_detector_evaluate_total_ms",
            "detector_evaluate_max_ms": "attention_detector_evaluate_max_ms",
            "response_identity_resolution_total_ms": "attention_response_resolution_total_ms",
            "response_identity_resolution_max_ms": "attention_response_resolution_max_ms",
            "liveness_probe_total_ms": "attention_liveness_probe_total_ms",
            "liveness_probe_max_ms": "attention_liveness_probe_max_ms"
        ]

        for (rawKey, diagnosticKey) in integerKeys {
            guard let number = raw[rawKey] as? NSNumber else { continue }
            fields[diagnosticKey] = .integer(number.int64Value)
        }
        for (rawKey, diagnosticKey) in doubleKeys {
            guard let number = raw[rawKey] as? NSNumber,
                  number.doubleValue.isFinite else { continue }
            fields[diagnosticKey] = .double(number.doubleValue)
        }
        if let enabled = raw["measurement_enabled"] as? Bool {
            fields["attention_workload_measurement_enabled"] = .bool(enabled)
        }
        return fields
    }

    private func currentBenchmarkDocument(
        for expectedWebView: WKWebView
    ) -> DocumentSession? {
        guard !isInvalidated,
              webView === expectedWebView,
              case .activeSupportedDocument = documentAdmission else {
            return nil
        }
        return document
    }

    private func benchmarkContextMatches(
        expectedWebView: WKWebView,
        expectedDocument: DocumentSession,
        contextIsCurrent: @MainActor () -> Bool
    ) -> Bool {
        guard !isInvalidated,
              webView === expectedWebView,
              case .activeSupportedDocument = documentAdmission,
              let document,
              document.epoch == expectedDocument.epoch,
              document.token == expectedDocument.token else {
            return false
        }
        return contextIsCurrent()
    }

    private func benchmarkRuntimeFields(
        runtimeIdentity: WebRuntimeDiagnosticIdentity,
        navigationGeneration: UInt64?
    ) -> [String: Any] {
        let navigationValue: Any = navigationGeneration.map { NSNumber(value: $0) } ?? NSNull()
        return [
            "slot_id": slotID.uuidString,
            "runtime_generation": runtimeIdentity.runtimeGeneration,
            "webview_instance_id": runtimeIdentity.webViewInstanceID.uuidString,
            "navigation_generation": navigationValue
        ]
    }

    private func benchmarkUnavailable(reason: String) -> [String: Any] {
        [
            "status": "unavailable",
            "reason": reason,
            "slot_id": slotID.uuidString,
            "measurement_enabled": benchmarkCounters.isEnabled
        ]
    }

    private func benchmarkStale(reason: String) -> [String: Any] {
        [
            "status": "stale",
            "reason": reason,
            "slot_id": slotID.uuidString,
            "measurement_enabled": benchmarkCounters.isEnabled
        ]
    }

    // MARK: WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let payload = ChatGPTBridgePayload.parse(body) else {
            return
        }
        accept(
            payload: payload,
            messageWebView: message.webView,
            isMainFrame: message.frameInfo.isMainFrame,
            originHost: message.frameInfo.securityOrigin.host,
            originProtocol: message.frameInfo.securityOrigin.`protocol`
        )
    }

    /// Validation pipeline and acceptance, split from the message-handler
    /// entry point so tests exercise the exact production semantics. Every
    /// check below must pass independently; origin comes from the message's
    /// own security origin, never from `webView.url`, because stale
    /// old-document messages race navigation.
    func accept(
        payload: ChatGPTBridgePayload,
        messageWebView: WKWebView?,
        isMainFrame: Bool,
        originHost: String?,
        originProtocol: String?
    ) {
        guard !isInvalidated,
              let attachedWebView = webView,
              messageWebView === attachedWebView,
              isMainFrame,
              let host = originHost?.lowercased(), !host.isEmpty,
              let protocolScheme = originProtocol?.lowercased(),
              protocolScheme == "https" || protocolScheme == "http",
              ChatGPTSitePolicy.isSupportedHost(host) else {
            return
        }

        switch documentAdmission {
        case .unsupportedCurrentDocument, .awaitingAuthorizedResync:
            // After a confirmed current-document boundary, only the direct
            // result from the actual current WebView may open the fresh epoch.
            // Unsupported documents stay closed until a later supported commit.
            // Natural or stale script messages are silent in both states.
            return
        case .awaitingSupportedBaseline, .activeSupportedDocument:
            break
        }

        if pendingInstantBackHandoff != nil {
            // The current accepted document remains authoritative until the
            // history item is confirmed. Its normal state stream must not be
            // frozen or buffered; a different-token baseline is rejected until
            // confirmation and the explicit current-document resync.
            guard document?.token == payload.token else {
                return
            }
            observeGeneration(
                payload.generating,
                responseIdentity: payload.responseIdentity
            )
            return
        }

        switch documentAdmission {
        case .awaitingSupportedBaseline:
            // This path is reserved for boundaries that cannot identify a
            // committed document (initial/test seams and runtime recovery).
            // Ordinary supported didCommit uses authorized current-document
            // resync instead, so a stale baseline cannot claim the new epoch.
            guard payload.kind == ChatGPTBridgePayload.baselineKind else { return }
            document = makeDocumentSession(token: payload.token)
            documentAdmission = .activeSupportedDocument
        case .activeSupportedDocument:
            guard document?.token == payload.token else { return }
        case .unsupportedCurrentDocument, .awaitingAuthorizedResync:
            return
        }
        observeGeneration(
            payload.generating,
            responseIdentity: payload.responseIdentity
        )
    }

    private func makeDocumentSession(token: String) -> DocumentSession {
        nextDocumentEpoch &+= 1
        return DocumentSession(token: token, epoch: nextDocumentEpoch)
    }

    // MARK: Navigation / runtime lifecycle

    /// Begins the one bounded bridge handoff for a WebKit Instant Back
    /// request. The request itself is not authority: until the navigation
    /// observer confirms the requested current history item, the old accepted
    /// document remains the only Attention epoch.
    func beginInstantBackHandoff(targetURL: URL? = nil) {
        guard !isInvalidated else {
            pendingInstantBackHandoff = nil
            return
        }
        pendingInstantBackHandoff = PendingInstantBackHandoff(
            shouldResyncCurrentDocument: targetURL.map {
                ChatGPTSitePolicy.isSupportedChatGPTURL($0)
            } ?? false,
            targetIsKnownUnsupported: targetURL.map {
                !ChatGPTSitePolicy.isSupportedChatGPTURL($0)
            } ?? false
        )
    }

    /// Cancels a pending handoff when Instant Back falls back to ordinary
    /// loading, fails, or another navigation supersedes it. The old document
    /// epoch remains untouched until the ordinary didCommit boundary.
    func cancelInstantBackHandoff() {
        pendingInstantBackHandoff = nil
    }

    /// Confirms the handoff only after SlotNavigationObserver has established
    /// that the requested WKBackForwardList item is the current item. Reset the
    /// old runtime first, then ask the actual current document to emit a fresh
    /// baseline when the confirmed target supports ChatGPT attention.
    func confirmInstantBackHandoff() {
        guard let handoff = pendingInstantBackHandoff else { return }
        pendingInstantBackHandoff = nil
        handleRuntimeReplacement()

        if handoff.targetIsKnownUnsupported {
            documentAdmission = .unsupportedCurrentDocument
            return
        }

        guard handoff.shouldResyncCurrentDocument else { return }
        requestCurrentDocumentResync()
    }

    /// The runtime was authoritatively replaced without a committed URL — for
    /// example, the WebContent process terminated. Forward one reset boundary,
    /// clear the old document epoch, and wait for the recovered document's
    /// natural baseline. Ordinary didCommit uses the URL-aware overload below.
    func handleRuntimeReplacement() {
        resetRuntime(admission: .awaitingSupportedBaseline)
    }

    /// The WebContent process termination callback is the sole authoritative
    /// physical-runtime replacement boundary. Advance the physical epoch and
    /// discard old callback markers only here; ordinary document resets keep
    /// them so late callbacks remain the only way to release same-process
    /// request capacity.
    func handleWebContentProcessReplacement() {
        physicalRuntimeEpoch &+= 1
        resetRuntime(admission: .awaitingSupportedBaseline)
        discardPendingPhysicalRequestMarkers()
    }

    /// The ordinary didCommit boundary supplies the actual committed/current
    /// WebKit URL before any presentation callback or persisted URL can be
    /// consulted. A supported commit closes natural baseline admission first,
    /// then asks the actual current WKWebView for its token-bearing baseline;
    /// this prevents an in-flight same-origin baseline from the replaced
    /// document from claiming the new epoch. A nil URL remains an unknown/test
    /// seam and therefore preserves natural-baseline recovery semantics.
    func handleRuntimeReplacement(committedURL: URL?) {
        guard let committedURL else {
            resetRuntime(admission: .awaitingSupportedBaseline)
            return
        }

        guard ChatGPTSitePolicy.isSupportedChatGPTURL(committedURL) else {
            resetRuntime(admission: .unsupportedCurrentDocument)
            return
        }

        resetRuntime(admission: .awaitingAuthorizedResync)
        requestCurrentDocumentResync()
    }

    private func resetRuntime(admission: DocumentAdmission) {
        invalidatePendingLivenessProbes()
        stopLivenessWatchdog()
        resetBenchmarkMeasurementForRuntimeReplacement()
        invalidatePendingCurrentDocumentResync()
        pendingInstantBackHandoff = nil
        let hadActiveDocument = document != nil
        document = nil
        documentAdmission = admission
        if hadActiveDocument {
            emit(ChatGPTAttentionEvent(observation: .runtimeReset, responseIdentity: nil))
        }
    }

    /// Permanently detaches the bridge from its WKWebView. Removes only this
    /// bridge's own message handler — Factory scripts and any unrelated user
    /// scripts stay untouched — drops the document epoch, and rejects every
    /// later callback. Forwards one reset boundary if a document was active.
    func invalidate() {
        guard !isInvalidated else { return }
        resetBenchmarkMeasurementForRuntimeReplacement()
        isInvalidated = true
        invalidatePendingLivenessProbes()
        stopLivenessWatchdog()
        invalidatePendingCurrentDocumentResync()
        discardPendingPhysicalRequestMarkers()
        pendingInstantBackHandoff = nil
        let hadActiveDocument = document != nil
        document = nil
        documentAdmission = .unsupportedCurrentDocument
        userContentController?.removeScriptMessageHandler(
            forName: Self.messageHandlerName,
            contentWorld: Self.contentWorld
        )
        userContentController = nil
        webView = nil
        if hadActiveDocument {
            emit(ChatGPTAttentionEvent(observation: .runtimeReset, responseIdentity: nil))
        }
    }

    private func resetBenchmarkMeasurementForRuntimeReplacement() {
        benchmarkCounters.resetValues()
#if DEBUG
        let shouldDisableDocumentCounters = benchmarkCounters.isEnabled || benchmarkOperationInFlight
        benchmarkCounters.setEnabled(false)
        benchmarkCounters.resetValues()
        guard shouldDisableDocumentCounters, let webView else { return }
        webView.evaluateJavaScript(
            "globalThis.__floatTabsAttentionBenchmarkConfigureV1?.(false, true)",
            in: nil,
            in: Self.contentWorld
        ) { _ in }
#else
        benchmarkCounters.setEnabled(true)
#endif
    }

    private func observeGeneration(
        _ generating: Bool,
        responseIdentity: ChatGPTResponseIdentity? = nil
    ) -> ChatGPTAttentionObservation? {
        guard let event = document?.tracker.observeEvent(
            generating,
            responseIdentity: responseIdentity
        ) else { return nil }
        emit(event)
        return event.observation
    }

    private func emit(_ event: ChatGPTAttentionEvent) {
        let observation = event.observation
        switch observation {
        case .generationStarted:
            livenessGeneration &+= 1
            startLivenessWatchdog()
        case .generationFinished, .runtimeReset:
            stopLivenessWatchdog()
        }
        if let onAttentionEvent {
            onAttentionEvent(slotID, event)
        } else {
            onObservation(slotID, observation)
        }
    }

    private func startLivenessWatchdog() {
        guard !isInvalidated, livenessWatchdogTask == nil, documentAdmission == .activeSupportedDocument, let document, let webView else { return }
        livenessWatchdogGeneration &+= 1
        let watchdogGeneration = livenessWatchdogGeneration
        let documentEpoch = document.epoch
        let token = document.token
        let webViewIdentity = ObjectIdentifier(webView)
#if DEBUG
        debugLivenessWatchdogStartCount += 1
#endif
        diagnostics.record(event: "attention.liveness_watchdog.started", level: .info, subsystem: "attention", fields: [
            "slot_id": .string(slotID.uuidString),
            "watchdog_interval_ms": .integer(2_000)
        ])
        livenessWatchdogTask = Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            while !Task.isCancelled {
                guard await self.livenessSleeper(Self.livenessWatchdogIntervalNanoseconds) else { return }
                guard !Task.isCancelled else { return }
                await self.performLivenessCycle(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token)
            }
        }
    }

    private func stopLivenessWatchdog() {
        let wasActive = livenessWatchdogTask != nil
        let stoppedGeneration = livenessWatchdogGeneration
        if livenessCycleOwnerGeneration == stoppedGeneration {
            livenessCycleOwnerGeneration = nil
        }
        livenessWatchdogGeneration &+= 1
        livenessWatchdogTask?.cancel()
        livenessWatchdogTask = nil
        clearLivenessIdleCandidate(ownedBy: stoppedGeneration)
        if wasActive {
            diagnostics.record(event: "attention.liveness_watchdog.stopped", level: .info, subsystem: "attention", fields: ["slot_id": .string(slotID.uuidString)])
        }
    }

    private func clearLivenessIdleCandidate(ownedBy watchdogGeneration: UInt64) {
        guard livenessIdleCandidateOwnerGeneration == watchdogGeneration else { return }
        livenessIdleCandidateOwnerGeneration = nil
    }

    private func isCurrentLivenessContext(watchdogGeneration: UInt64, documentEpoch: UInt64, webView: WKWebView, webViewIdentity: ObjectIdentifier, token: String) -> Bool {
        guard !isInvalidated, documentAdmission == .activeSupportedDocument, livenessWatchdogTask != nil, livenessWatchdogGeneration == watchdogGeneration, let attachedWebView = self.webView, attachedWebView === webView, ObjectIdentifier(attachedWebView) == webViewIdentity, let document, document.epoch == documentEpoch, document.token == token else { return false }
        return true
    }

    private func parseLivenessProbe(_ value: Any?) -> ChatGPTBridgePayload? {
        guard let body = value as? [String: Any], let payload = ChatGPTBridgePayload.parse(body), payload.kind == ChatGPTBridgePayload.baselineKind else { return nil }
        return payload
    }

    /// Bounds the physical WebKit callback budget independently from the
    /// semantic document epoch. A timeout releases the caller immediately but
    /// retains the request marker until the late callback arrives, so a stale
    /// result can only release physical capacity and never reopen state.
    private func boundedLivenessProbe(
        _ webView: WKWebView,
        role: String
    ) async -> BoundedLivenessProbeResult {
        guard pendingLivenessProbes.count < Self.maximumOutstandingLivenessProbes else {
            benchmarkCounters.recordLivenessSuppression()
            recordLivenessAnomaly(
                result: "suppressed",
                role: role,
                startedAt: ProcessInfo.processInfo.systemUptime,
                reason: "pending_request_budget",
                captureSnapshot: false
            )
            return .suppressed
        }

        let requestID = UUID()
        let requestPhysicalRuntimeEpoch = physicalRuntimeEpoch
        let startedAt = ProcessInfo.processInfo.systemUptime
        return await withCheckedContinuation { continuation in
            pendingLivenessProbes[requestID] = .active(
                physicalRuntimeEpoch: requestPhysicalRuntimeEpoch,
                role: role,
                startedAt: startedAt,
                continuation: continuation
            )
            let timeoutNanoseconds = UInt64(livenessProbeTimeout * 1_000_000_000)
            livenessProbeTimeoutTasks[requestID] = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                } catch {
                    return
                }
                self?.finishLivenessProbe(
                    id: requestID,
                    value: nil,
                    timedOut: true,
                    physicalRuntimeEpoch: requestPhysicalRuntimeEpoch
                )
            }
            Task { @MainActor [weak self, weak webView] in
                guard let self else { return }
                guard let webView else {
                    self.finishLivenessProbe(
                        id: requestID,
                        value: nil,
                        timedOut: false,
                        physicalRuntimeEpoch: requestPhysicalRuntimeEpoch
                    )
                    return
                }
                let value = await self.livenessProbe(webView)
                self.finishLivenessProbe(
                    id: requestID,
                    value: value,
                    timedOut: false,
                    physicalRuntimeEpoch: requestPhysicalRuntimeEpoch
                )
            }
        }
    }

    private func finishLivenessProbe(
        id: UUID,
        value: Any?,
        timedOut: Bool,
        physicalRuntimeEpoch: UInt64
    ) {
        guard let pending = pendingLivenessProbes[id] else { return }
        switch pending {
        case let .active(requestEpoch, role, startedAt, continuation):
            guard requestEpoch == physicalRuntimeEpoch else { return }
            livenessProbeTimeoutTasks.removeValue(forKey: id)?.cancel()
            if timedOut {
                benchmarkCounters.recordLivenessTimeout()
            }
            pendingLivenessProbes[id] = timedOut
                ? .timedOut(
                    physicalRuntimeEpoch: requestEpoch,
                    role: role,
                    startedAt: startedAt
                )
                : nil
            continuation.resume(returning: timedOut ? .timedOut : .value(value))
            if timedOut {
                recordLivenessAnomaly(
                    result: "timeout",
                    role: role,
                    startedAt: startedAt,
                    reason: "deadline_exceeded",
                    captureSnapshot: true
                )
            }
        case let .timedOut(requestEpoch, role, startedAt):
            // The timeout already completed the semantic request. A late
            // callback only releases the physical request budget.
            guard requestEpoch == physicalRuntimeEpoch else { return }
            guard !timedOut else { return }
            pendingLivenessProbes.removeValue(forKey: id)
            recordLivenessAnomaly(
                result: "late_callback",
                role: role,
                startedAt: startedAt,
                reason: "callback_after_timeout",
                captureSnapshot: false
            )
        }
    }

    private func invalidatePendingLivenessProbes() {
        for (requestID, pending) in pendingLivenessProbes {
            guard case let .active(requestEpoch, role, startedAt, continuation) = pending else { continue }
            livenessProbeTimeoutTasks.removeValue(forKey: requestID)?.cancel()
            pendingLivenessProbes[requestID] = .timedOut(
                physicalRuntimeEpoch: requestEpoch,
                role: role,
                startedAt: startedAt
            )
            continuation.resume(returning: .value(nil))
        }
    }

    private func discardPendingPhysicalLivenessProbes() {
        for task in livenessProbeTimeoutTasks.values {
            task.cancel()
        }
        livenessProbeTimeoutTasks.removeAll()
        pendingLivenessProbes.removeAll()
    }

    private func recordLivenessProbeFailure(
        role: String,
        startedAt: TimeInterval,
        result: String
    ) {
        benchmarkCounters.recordLivenessFailure()
        diagnostics.record(
            event: "attention.liveness_probe.failed",
            level: .debug,
            subsystem: "attention",
            fields: [
                "slot_id": .string(slotID.uuidString),
                "probe_role": .string(role),
                "probe_result": .string(result)
            ]
        )
        recordLivenessAnomaly(
            result: result,
            role: role,
            startedAt: startedAt,
            reason: result,
            captureSnapshot: true
        )
    }

    private func recordLivenessAnomaly(
        result: String,
        role: String,
        startedAt: TimeInterval,
        reason: String,
        captureSnapshot: Bool
    ) {
        let context = activeLivenessIncidentContext ?? RuntimeDiagnosticIncidentContext(
            id: UUID(),
            kind: .attentionLiveness,
            trigger: result,
            startedAtUptime: startedAt
        )
        activeLivenessIncidentContext = context
        var fields = context.fields(phase: .trigger)
        fields.merge([
            "slot_id": .string(slotID.uuidString),
            "attention_probe_result": .string(result),
            "probe_role": .string(role),
            "probe_reason": .string(reason),
            "probe_elapsed_ms": .integer(Int64(min(max((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000, 0), 5_000).rounded())),
            "document_epoch": document.map { .integer(Int64($0.epoch)) } ?? .null,
            "physical_runtime_epoch": .integer(Int64(physicalRuntimeEpoch)),
            "watchdog_generation": .integer(Int64(livenessWatchdogGeneration)),
            "outstanding_request_count": .integer(Int64(pendingLivenessProbes.count))
        ]) { _, new in new }
        diagnostics.record(
            event: "attention.liveness_probe.abnormal",
            level: .warning,
            subsystem: "attention",
            fields: fields
        )
        if captureSnapshot && !livenessIncidentSnapshotRequested {
            livenessIncidentSnapshotRequested = true
            onIncidentRequest?(slotID, context)
        }
    }

    private func recordResyncAnomaly(
        result: String,
        attempt: Int,
        generation: UInt64,
        reason: String,
        captureSnapshot: Bool
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        let context = activeResyncIncidentContext ?? RuntimeDiagnosticIncidentContext(
            id: UUID(),
            kind: .attentionLiveness,
            trigger: "resync_\(result)",
            startedAtUptime: now
        )
        activeResyncIncidentContext = context
        var fields = context.fields(phase: .trigger)
        fields.merge([
            "slot_id": .string(slotID.uuidString),
            "attention_probe_result": .string(result),
            "probe_role": .string("resync"),
            "probe_reason": .string(reason),
            "resync_attempt": .integer(Int64(attempt)),
            "resync_generation": .integer(Int64(generation)),
            "document_epoch": document.map { .integer(Int64($0.epoch)) } ?? .null,
            "physical_runtime_epoch": .integer(Int64(physicalRuntimeEpoch)),
            "outstanding_request_count": .integer(Int64(outstandingCurrentDocumentResyncRequestIDs.count))
        ]) { _, new in new }
        diagnostics.record(
            event: "attention.current_document_resync.abnormal",
            level: .warning,
            subsystem: "attention",
            fields: fields
        )
        if result == "timeout" {
            diagnostics.record(
                event: "attention.current_document_resync.timeout",
                level: .debug,
                subsystem: "attention",
                fields: [
                    "slot_id": .string(slotID.uuidString),
                    "attempt": .integer(Int64(attempt)),
                    "reason": .string(reason)
                ]
            )
        } else if result == "suppressed" {
            diagnostics.record(
                event: "attention.current_document_resync.suppressed",
                level: .debug,
                subsystem: "attention",
                fields: [
                    "slot_id": .string(slotID.uuidString),
                    "reason": .string(reason)
                ]
            )
        }
        if captureSnapshot && !resyncIncidentSnapshotRequested {
            resyncIncidentSnapshotRequested = true
            onIncidentRequest?(slotID, context)
        }
    }

    private func closeResyncIncident(outcome: String) {
        guard let context = activeResyncIncidentContext else { return }
        var fields = context.fields(phase: .closure)
        fields["incident_outcome"] = .string(outcome)
        diagnostics.record(
            event: "attention.current_document_resync.incident_closed",
            level: .notice,
            subsystem: "attention",
            fields: fields
        )
        activeResyncIncidentContext = nil
        resyncIncidentSnapshotRequested = false
    }

    @MainActor
    private func performLivenessCycle(watchdogGeneration: UInt64, documentEpoch: UInt64, webView: WKWebView, webViewIdentity: ObjectIdentifier, token: String) async {
        guard livenessCycleOwnerGeneration == nil, isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token) else { return }
        livenessCycleOwnerGeneration = watchdogGeneration
        defer {
            if livenessCycleOwnerGeneration == watchdogGeneration {
                livenessCycleOwnerGeneration = nil
            }
        }
        let generation = livenessGeneration
        let cyclePhysicalRuntimeEpoch = physicalRuntimeEpoch
        let firstProbeStartedAt = ProcessInfo.processInfo.systemUptime
        let firstResult = await boundedLivenessProbe(webView, role: "first")
        let firstValue = firstResult.value
        recordBenchmarkLivenessProbe(
            startedAt: firstProbeStartedAt,
            isConfirmation: false,
            physicalRuntimeEpoch: cyclePhysicalRuntimeEpoch
        )
        guard !firstResult.didTimeOut,
              !firstResult.wasSuppressed,
              let firstValue,
              let firstProbe = parseLivenessProbe(firstValue),
              isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token),
              firstProbe.token == token else {
            if firstResult.didTimeOut { return }
            if firstResult.wasSuppressed { return }
            if isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token) {
                recordLivenessProbeFailure(
                    role: "first",
                    startedAt: firstProbeStartedAt,
                    result: firstValue == nil ? "evaluation_or_callback_failure" : "parse_invalid_result"
                )
            } else if firstValue != nil {
                recordLivenessAnomaly(
                    result: "stale_context",
                    role: "first",
                    startedAt: firstProbeStartedAt,
                    reason: "runtime_or_document_changed",
                    captureSnapshot: false
                )
            }
            return
        }
        if firstProbe.generating {
            clearLivenessIdleCandidate(ownedBy: watchdogGeneration)
            return
        }
        livenessIdleCandidateOwnerGeneration = watchdogGeneration
        guard await livenessSleeper(Self.livenessConfirmationDelayNanoseconds), livenessIdleCandidateOwnerGeneration == watchdogGeneration, livenessGeneration == generation, isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token) else {
            clearLivenessIdleCandidate(ownedBy: watchdogGeneration)
            return
        }
        let secondProbeStartedAt = ProcessInfo.processInfo.systemUptime
        let secondResult = await boundedLivenessProbe(webView, role: "confirmation")
        let secondValue = secondResult.value
        recordBenchmarkLivenessProbe(
            startedAt: secondProbeStartedAt,
            isConfirmation: true,
            physicalRuntimeEpoch: cyclePhysicalRuntimeEpoch
        )
        guard !secondResult.didTimeOut,
              !secondResult.wasSuppressed,
              let secondValue,
              let secondProbe = parseLivenessProbe(secondValue),
              secondProbe.token == token,
              isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token) else {
            if secondResult.didTimeOut {
                clearLivenessIdleCandidate(ownedBy: watchdogGeneration)
                return
            }
            if secondResult.wasSuppressed {
                clearLivenessIdleCandidate(ownedBy: watchdogGeneration)
                return
            }
            if isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token) {
                recordLivenessProbeFailure(
                    role: "confirmation",
                    startedAt: secondProbeStartedAt,
                    result: secondValue == nil ? "evaluation_or_callback_failure" : "parse_invalid_result"
                )
            } else if secondValue != nil {
                recordLivenessAnomaly(
                    result: "stale_context",
                    role: "confirmation",
                    startedAt: secondProbeStartedAt,
                    reason: "runtime_or_document_changed",
                    captureSnapshot: false
                )
            }
            clearLivenessIdleCandidate(ownedBy: watchdogGeneration)
            return
        }
        guard !secondProbe.generating, livenessGeneration == generation else {
            clearLivenessIdleCandidate(ownedBy: watchdogGeneration)
            return
        }
        clearLivenessIdleCandidate(ownedBy: watchdogGeneration)
        guard observeGeneration(
            false,
            responseIdentity: secondProbe.responseIdentity
        ) == .generationFinished else { return }
        benchmarkCounters.recordRecoveredCompletion()
        diagnostics.record(event: "attention.liveness_probe.recovered_completion", level: .info, subsystem: "attention", fields: [
            "slot_id": .string(slotID.uuidString),
            "confirmation_count": .integer(2),
            "watchdog_interval_ms": .integer(2_000),
            "confirmation_delay_ms": .integer(250)
        ])
        if let incidentContext = activeLivenessIncidentContext {
            var fields = incidentContext.fields(phase: .closure)
            fields["incident_outcome"] = .string("healthy_current_runtime")
            fields["document_epoch"] = .integer(Int64(documentEpoch))
            fields["physical_runtime_epoch"] = .integer(Int64(physicalRuntimeEpoch))
            diagnostics.record(
                event: "attention.liveness_probe.incident_closed",
                level: .notice,
                subsystem: "attention",
                fields: fields
            )
            activeLivenessIncidentContext = nil
            livenessIncidentSnapshotRequested = false
        }
    }

    private func recordBenchmarkLivenessProbe(
        startedAt: TimeInterval,
        isConfirmation: Bool,
        physicalRuntimeEpoch: UInt64
    ) {
        guard self.physicalRuntimeEpoch == physicalRuntimeEpoch else { return }
        let durationMilliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        benchmarkCounters.recordLivenessProbe(
            durationMilliseconds: durationMilliseconds,
            isConfirmation: isConfirmation
        )
    }

#if DEBUG
    var debugLivenessWatchdogActive: Bool { livenessWatchdogTask != nil }

    func debugRunLivenessCycle() async {
        guard let document, let webView, livenessWatchdogTask != nil else { return }
        await performLivenessCycle(watchdogGeneration: livenessWatchdogGeneration, documentEpoch: document.epoch, webView: webView, webViewIdentity: ObjectIdentifier(webView), token: document.token)
    }
#endif

    private func requestCurrentDocumentResync() {
        documentAdmission = .awaitingAuthorizedResync
        guard !isInvalidated,
              let webView,
              self.webView === webView else {
            return
        }
        guard outstandingCurrentDocumentResyncRequestIDs.count
            < Self.maximumOutstandingCurrentDocumentResyncRequests else {
            benchmarkCounters.recordCurrentDocumentResyncSuppression()
            recordResyncAnomaly(
                result: "suppressed",
                attempt: 0,
                generation: nextResyncGeneration,
                reason: "pending_request_budget",
                captureSnapshot: false
            )
            return
        }

        nextResyncGeneration &+= 1
        let generation = nextResyncGeneration
        let requestID = UUID()
        let pending = PendingCurrentDocumentResync(
            requestID: requestID,
            generation: generation,
            attempt: 1,
            webViewIdentity: ObjectIdentifier(webView),
            physicalRuntimeEpoch: physicalRuntimeEpoch
        )
        pendingCurrentDocumentResync = pending
        outstandingCurrentDocumentResyncRequestIDs.insert(requestID)
        scheduleCurrentDocumentResyncTimeout(
            requestID: requestID,
            generation: generation,
            attempt: pending.attempt,
            webViewIdentity: ObjectIdentifier(webView),
            physicalRuntimeEpoch: pending.physicalRuntimeEpoch
        )
        evaluateCurrentDocumentResync(
            in: webView,
            requestID: requestID,
            generation: generation,
            attempt: pending.attempt,
            physicalRuntimeEpoch: pending.physicalRuntimeEpoch
        )
    }

    private func evaluateCurrentDocumentResync(
        in webView: WKWebView,
        requestID: UUID,
        generation: UInt64,
        attempt: Int,
        physicalRuntimeEpoch: UInt64
    ) {
        if let currentDocumentResyncEvaluator {
            Task { @MainActor [weak self, weak webView] in
                guard let self else { return }
                guard let webView else {
                    self.completeCurrentDocumentResync(
                        requestID: requestID,
                        generation: generation,
                        attempt: attempt,
                        physicalRuntimeEpoch: physicalRuntimeEpoch,
                        webView: nil,
                        result: .failure(CancellationError())
                    )
                    return
                }
                do {
                    let value = try await currentDocumentResyncEvaluator(
                        webView,
                        "globalThis.__floatTabsAttentionResyncV1?.()"
                    )
                    self.completeCurrentDocumentResync(
                        requestID: requestID,
                        generation: generation,
                        attempt: attempt,
                        physicalRuntimeEpoch: physicalRuntimeEpoch,
                        webView: webView,
                        result: .success(value)
                    )
                } catch {
                    self.completeCurrentDocumentResync(
                        requestID: requestID,
                        generation: generation,
                        attempt: attempt,
                        physicalRuntimeEpoch: physicalRuntimeEpoch,
                        webView: webView,
                        result: .failure(error)
                    )
                }
            }
            return
        }

        webView.evaluateJavaScript(
            "globalThis.__floatTabsAttentionResyncV1?.()",
            in: nil,
            in: Self.contentWorld
        ) { [weak self, weak webView] (result: Result<Any, Error>) in
            self?.completeCurrentDocumentResync(
                requestID: requestID,
                generation: generation,
                attempt: attempt,
                physicalRuntimeEpoch: physicalRuntimeEpoch,
                webView: webView,
                result: result
            )
        }
    }

    private func scheduleCurrentDocumentResyncTimeout(
        requestID: UUID,
        generation: UInt64,
        attempt: Int,
        webViewIdentity: ObjectIdentifier,
        physicalRuntimeEpoch: UInt64
    ) {
        currentDocumentResyncTimeoutTasks[requestID]?.cancel()
        let timeoutNanoseconds = UInt64(currentDocumentResyncTimeout * 1_000_000_000)
        currentDocumentResyncTimeoutTasks[requestID] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }
            self?.finishCurrentDocumentResyncTimeout(
                requestID: requestID,
                generation: generation,
                attempt: attempt,
                webViewIdentity: webViewIdentity,
                physicalRuntimeEpoch: physicalRuntimeEpoch
            )
        }
    }

    private func finishCurrentDocumentResyncTimeout(
        requestID: UUID,
        generation: UInt64,
        attempt: Int,
        webViewIdentity: ObjectIdentifier,
        physicalRuntimeEpoch: UInt64
    ) {
        guard outstandingCurrentDocumentResyncRequestIDs.contains(requestID) else {
            return
        }
        currentDocumentResyncTimeoutTasks.removeValue(forKey: requestID)
        // Keep the request ID outstanding until its callback returns. The
        // timeout closes only semantic admission; it does not manufacture
        // capacity for another physical WebKit evaluation.
        guard let pending = pendingCurrentDocumentResync,
              pending.requestID == requestID,
              pending.generation == generation,
              pending.attempt == attempt,
              pending.webViewIdentity == webViewIdentity,
              pending.physicalRuntimeEpoch == physicalRuntimeEpoch,
              self.physicalRuntimeEpoch == physicalRuntimeEpoch else {
            return
        }
        pendingCurrentDocumentResync = nil
        benchmarkCounters.recordCurrentDocumentResyncTimeout()
        recordResyncAnomaly(
            result: "timeout",
            attempt: attempt,
            generation: generation,
            reason: "deadline_exceeded",
            captureSnapshot: true
        )
    }

    private func completeCurrentDocumentResync(
        requestID: UUID,
        generation: UInt64,
        attempt: Int,
        physicalRuntimeEpoch: UInt64,
        webView: WKWebView?,
        result: Result<Any, Error>
    ) {
        guard outstandingCurrentDocumentResyncRequestIDs.remove(requestID) != nil else {
            return
        }
        currentDocumentResyncTimeoutTasks.removeValue(forKey: requestID)?.cancel()

        let semanticPendingMatches = pendingCurrentDocumentResync?.requestID == requestID
        guard !isInvalidated,
              let webView,
              self.webView === webView,
              let pending = pendingCurrentDocumentResync,
              pending.requestID == requestID,
              pending.generation == generation,
              pending.attempt == attempt,
              pending.webViewIdentity == ObjectIdentifier(webView),
              pending.physicalRuntimeEpoch == physicalRuntimeEpoch,
              self.physicalRuntimeEpoch == physicalRuntimeEpoch else {
            recordResyncAnomaly(
                result: semanticPendingMatches ? "stale_context" : "late_callback",
                attempt: attempt,
                generation: generation,
                reason: semanticPendingMatches ? "runtime_or_document_changed" : "callback_after_timeout",
                captureSnapshot: false
            )
            return
        }

        if case let .success(value) = result,
           let body = value as? [String: Any],
           let payload = ChatGPTBridgePayload.parse(body),
           payload.kind == ChatGPTBridgePayload.baselineKind {
            pendingCurrentDocumentResync = nil
            acceptAuthorizedCurrentDocumentBaseline(payload)
            closeResyncIncident(outcome: "baseline_accepted")
            return
        }

        let resultClassification: String = switch result {
        case .failure:
            "evaluation_or_callback_failure"
        case .success:
            "parse_invalid_result"
        }
        recordResyncAnomaly(
            result: resultClassification,
            attempt: attempt,
            generation: generation,
            reason: "bounded_resync_result_invalid",
            captureSnapshot: attempt == 1
        )

        guard attempt < Self.resyncAttemptLimit else {
            // Keep the authorization barrier closed after bounded failure. A
            // later ordinary runtime replacement owns recovery; no arbitrary
            // baseline may reopen this epoch.
            pendingCurrentDocumentResync = nil
            closeResyncIncident(outcome: "attempts_exhausted")
            return
        }

        let retryRequestID = UUID()
        let retry = PendingCurrentDocumentResync(
            requestID: retryRequestID,
            generation: generation,
            attempt: attempt + 1,
            webViewIdentity: ObjectIdentifier(webView),
            physicalRuntimeEpoch: physicalRuntimeEpoch
        )
        pendingCurrentDocumentResync = retry
        outstandingCurrentDocumentResyncRequestIDs.insert(retryRequestID)
        scheduleCurrentDocumentResyncTimeout(
            requestID: retryRequestID,
            generation: generation,
            attempt: retry.attempt,
            webViewIdentity: ObjectIdentifier(webView),
            physicalRuntimeEpoch: retry.physicalRuntimeEpoch
        )
        evaluateCurrentDocumentResync(
            in: webView,
            requestID: retryRequestID,
            generation: generation,
            attempt: retry.attempt,
            physicalRuntimeEpoch: retry.physicalRuntimeEpoch
        )
    }

    private func acceptAuthorizedCurrentDocumentBaseline(
        _ payload: ChatGPTBridgePayload
    ) {
        guard payload.kind == ChatGPTBridgePayload.baselineKind else { return }
        document = makeDocumentSession(token: payload.token)
        documentAdmission = .activeSupportedDocument
        observeGeneration(
            payload.generating,
            responseIdentity: payload.responseIdentity
        )
    }

    private func invalidatePendingCurrentDocumentResync() {
        nextResyncGeneration &+= 1
        pendingCurrentDocumentResync = nil
        for task in currentDocumentResyncTimeoutTasks.values {
            task.cancel()
        }
        currentDocumentResyncTimeoutTasks.removeAll()
    }

    private func discardPendingPhysicalRequestMarkers() {
        discardPendingPhysicalLivenessProbes()
        for task in currentDocumentResyncTimeoutTasks.values {
            task.cancel()
        }
        currentDocumentResyncTimeoutTasks.removeAll()
        outstandingCurrentDocumentResyncRequestIDs.removeAll()
        pendingCurrentDocumentResync = nil
    }
}
