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
    let responseOwnership: ChatGPTResponseOwnershipProbeValues?

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
        let responseOwnership: ChatGPTResponseOwnershipProbeValues?
        if let ownershipFields = fields["response_ownership"] {
            responseOwnership = ChatGPTResponseOwnershipProbeValues.parse(ownershipFields)
            guard responseOwnership != nil else { return nil }
        } else {
            responseOwnership = nil
        }
        return ChatGPTIncidentHealthProbeValues(
            documentReadyState: documentReadyState,
            visibilityState: visibilityState,
            conversationShellPresent: conversationShellPresent,
            composerPresent: composerPresent,
            loadingIndicatorPresent: loadingIndicatorPresent,
            loadingIndicatorVisible: loadingIndicatorVisible,
            conversationLoadErrorPresent: conversationLoadErrorPresent,
            responseOwnership: responseOwnership
        )
    }

    var diagnosticFields: [String: RuntimeDiagnosticValue] {
        var fields: [String: RuntimeDiagnosticValue] = [
            "document_ready_state": .string(documentReadyState),
            "visibility_state": .string(visibilityState),
            "conversation_shell_present": .bool(conversationShellPresent),
            "composer_present": .bool(composerPresent),
            "loading_indicator_present": .bool(loadingIndicatorPresent),
            "loading_indicator_visible": .bool(loadingIndicatorVisible),
            "conversation_load_error_present": .bool(conversationLoadErrorPresent)
        ]
        if let responseOwnership {
            fields.merge(responseOwnership.diagnosticFields) { _, new in new }
        }
        return fields
    }
}

/// Temporary, privacy-safe structural metadata emitted only by the explicit
/// DEBUG incident snapshot. Values are parsed into closed categories before
/// they can reach diagnostics; this model intentionally has no text fields.
struct ChatGPTResponseOwnershipProbeValues: Equatable, Sendable {
    let selectedPath: String
    let candidateTagCategory: String
    let candidateRoleCategory: String
    let candidateTestIDCategory: String
    let candidateAncestorDepth: Int?
    let responseActionCount: Int
    let semanticBlockCount: Int
    let hasUserMarker: Bool
    let hasAssistantMarker: Bool
    let hasStatus: Bool
    let hasAlert: Bool
    let hasLiveRegion: Bool
    let hasComposer: Bool
    let hasMultipleTurns: Bool
    let notificationSemanticBlockPresent: Bool
    let structuredBlocksRootIsCandidate: Bool

    static func parse(_ value: Any) -> ChatGPTResponseOwnershipProbeValues? {
        guard let fields = value as? [String: Any],
              Set(fields.keys) == Set([
                "version", "selected_path", "candidate_tag_category", "candidate_role_category",
                "candidate_testid_category", "candidate_ancestor_depth", "response_action_count",
                "semantic_block_count", "has_user_marker", "has_assistant_marker", "has_status",
                "has_alert", "has_live_region", "has_composer", "has_multiple_turns",
                "notification_semantic_block_present", "structured_blocks_root_is_candidate"
              ]),
              fields["version"] as? Int == 1,
              let selectedPath = fields["selected_path"] as? String,
              ["explicit", "article", "fallback", "none"].contains(selectedPath),
              let candidateTagCategory = fields["candidate_tag_category"] as? String,
              ["article", "div", "section", "main", "other", "none"].contains(candidateTagCategory),
              let candidateRoleCategory = fields["candidate_role_category"] as? String,
              ["assistant", "user", "status", "alert", "textbox", "button", "other", "none"]
                .contains(candidateRoleCategory),
              let candidateTestIDCategory = fields["candidate_testid_category"] as? String,
              ["conversation_turn", "message", "composer", "other", "none"]
                .contains(candidateTestIDCategory),
              let responseActionCount = boundedCount(fields["response_action_count"]),
              let semanticBlockCount = boundedCount(fields["semantic_block_count"]),
              let hasUserMarker = fields["has_user_marker"] as? Bool,
              let hasAssistantMarker = fields["has_assistant_marker"] as? Bool,
              let hasStatus = fields["has_status"] as? Bool,
              let hasAlert = fields["has_alert"] as? Bool,
              let hasLiveRegion = fields["has_live_region"] as? Bool,
              let hasComposer = fields["has_composer"] as? Bool,
              let hasMultipleTurns = fields["has_multiple_turns"] as? Bool,
              let notificationSemanticBlockPresent = fields["notification_semantic_block_present"] as? Bool,
              let structuredBlocksRootIsCandidate = fields["structured_blocks_root_is_candidate"] as? Bool else {
            return nil
        }
        let candidateAncestorDepth: Int?
        if let depth = fields["candidate_ancestor_depth"] as? Int {
            guard (0...64).contains(depth) else { return nil }
            candidateAncestorDepth = depth
        } else if fields["candidate_ancestor_depth"] is NSNull {
            candidateAncestorDepth = nil
        } else {
            return nil
        }
        return ChatGPTResponseOwnershipProbeValues(
            selectedPath: selectedPath,
            candidateTagCategory: candidateTagCategory,
            candidateRoleCategory: candidateRoleCategory,
            candidateTestIDCategory: candidateTestIDCategory,
            candidateAncestorDepth: candidateAncestorDepth,
            responseActionCount: responseActionCount,
            semanticBlockCount: semanticBlockCount,
            hasUserMarker: hasUserMarker,
            hasAssistantMarker: hasAssistantMarker,
            hasStatus: hasStatus,
            hasAlert: hasAlert,
            hasLiveRegion: hasLiveRegion,
            hasComposer: hasComposer,
            hasMultipleTurns: hasMultipleTurns,
            notificationSemanticBlockPresent: notificationSemanticBlockPresent,
            structuredBlocksRootIsCandidate: structuredBlocksRootIsCandidate
        )
    }

    var diagnosticFields: [String: RuntimeDiagnosticValue] {
        [
            "selected_path": .string(selectedPath),
            "candidate_tag_category": .string(candidateTagCategory),
            "candidate_role_category": .string(candidateRoleCategory),
            "candidate_testid_category": .string(candidateTestIDCategory),
            "candidate_ancestor_depth": candidateAncestorDepth.map { .integer(Int64($0)) } ?? .null,
            "response_action_count": .integer(Int64(responseActionCount)),
            "semantic_block_count": .integer(Int64(semanticBlockCount)),
            "has_user_marker": .bool(hasUserMarker),
            "has_assistant_marker": .bool(hasAssistantMarker),
            "has_status": .bool(hasStatus),
            "has_alert": .bool(hasAlert),
            "has_live_region": .bool(hasLiveRegion),
            "has_composer": .bool(hasComposer),
            "has_multiple_turns": .bool(hasMultipleTurns),
            "notification_semantic_block_present": .bool(notificationSemanticBlockPresent),
            "structured_blocks_root_is_candidate": .bool(structuredBlocksRootIsCandidate)
        ]
    }

    private static func boundedCount(_ value: Any?) -> Int? {
        guard let count = value as? Int, (0...255).contains(count) else { return nil }
        return count
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
    let resourceType: String
    let httpStatus: Int?
    let durationBucket: String?
    let ageMilliseconds: Int

    func diagnosticFields(prefix: String) -> [String: RuntimeDiagnosticValue] {
        [
            "\(prefix)_kind": .string(kind),
            "\(prefix)_category": .string(category),
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
    let droppedEvents: Int
    let javascriptErrorCount: Int
    let unhandledRejectionCount: Int
    let resourceLoadFailureCount: Int
    let resourceHTTPErrorCount: Int
    let slowResourceCount: Int
    let lifecycleEventCount: Int
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

        let events = rawEvents.compactMap(parseEvent)
        guard events.count == rawEvents.count else { return nil }
        return Self(
            events: events,
            droppedEvents: droppedEvents,
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

    var diagnosticFields: [String: RuntimeDiagnosticValue] {
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
        for (index, event) in events.enumerated() {
            fields.merge(event.diagnosticFields(prefix: String(format: "page_app_event_%02d", index))) {
                _, new in new
            }
        }
        return fields
    }

    private static func boundedCounter(_ value: Any?) -> Int? {
        guard let value = value as? Int, (0...255).contains(value) else { return nil }
        return value
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
        guard let kind = raw["kind"] as? String, kinds.contains(kind),
              let category = raw["category"] as? String, categories.contains(category),
              let resourceType = raw["resource_type"] as? String, resourceTypes.contains(resourceType),
              let age = raw["age_ms"] as? Int, (0...86_400_000).contains(age) else {
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

    var diagnosticFields: [String: RuntimeDiagnosticValue] {
        var fields: [String: RuntimeDiagnosticValue] = [
            "page_app_probe_outcome": .string(outcome.rawValue),
            "page_app_probe_latency_ms": .double(min(max(latencyMilliseconds, 0), 5_000)),
            "page_app_capture_uptime_ms": .integer(captureUptimeMilliseconds),
            "chatgpt_document_epoch": documentEpoch.map { .integer(Int64($0)) } ?? .null
        ]
        let valueFields = values?.diagnosticFields ?? [
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
            "page_app_capture_ring_capacity": .integer(Int64(ChatGPTIncidentPageAppProbeValues.maximumEvents))
        ]
        fields.merge(valueFields) { _, new in new }
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
    static let livenessWatchdogIntervalNanoseconds: UInt64 = 2_000_000_000
    static let livenessConfirmationDelayNanoseconds: UInt64 = 250_000_000
    static let livenessProbeScript = "globalThis.__floatTabsAttentionProbeV1?.()"

    typealias LivenessProbeProvider = @MainActor (WKWebView) async -> Any?
    typealias LivenessSleeper = @MainActor (UInt64) async -> Bool

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

    /// The single shared world instance used for both the injected script and
    /// the message handler. One instance is required: worlds with equal names
    /// are still distinct objects.
    static let contentWorld = WKContentWorld.world(name: contentWorldName)

    /// Test/diagnostic seam: the exact script injected into supported
    /// documents, generated by `makeScriptSource()` from Swift-owned
    /// constants.
    static let scriptSource = makeScriptSource()

#if DEBUG
    /// Temporary Gate 1 callable. The page's text nodes are never read; the
    /// result contains only fixed categories, booleans and bounded counts.
    static let debugResponseOwnershipSnapshotProbeSource = """
    globalThis.__floatTabsDebugResponseOwnershipSnapshotV1 = () => {
      const explicitSelector =
        '[data-message-author-role="assistant"],[data-message-role="assistant"]';
      const articleSelector = 'article[data-testid*="conversation-turn"]';
      const turnMarkerSelector =
        '[data-message-author-role="user"],[data-message-role="user"],' +
        '[data-message-author-role="assistant"],[data-message-role="assistant"],' +
        'article[data-testid*="conversation-turn"]';
      const composerSelector =
        '#prompt-textarea, textarea[aria-label="Message ChatGPT"], ' +
        '[contenteditable="true"][data-testid*="composer"], main [role="textbox"]';
      const semanticSelector =
        'h1,h2,h3,h4,h5,h6,p,li,blockquote,pre,table,math,' +
        '.katex-display,.katex,mjx-container,' +
        '[data-math],[data-latex],[data-tex],[role="math"]';
      const explicitNodes = Array.from(document.querySelectorAll(explicitSelector));
      const articleNodes = explicitNodes.length ? [] : Array.from(
        document.querySelectorAll(articleSelector)
      ).filter((article) => {
        const role = article.getAttribute('data-message-author-role')
          || article.querySelector('[data-message-author-role]')
            ?.getAttribute('data-message-author-role');
        return role === 'assistant' && isRendered(article);
      });
      const candidate = latestAssistantResponseRoot();
      const selectedPath = explicitNodes.length ? 'explicit'
        : articleNodes.length ? 'article'
        : candidate ? 'fallback' : 'none';
      const nodesIncludingRoot = (root, selector) => {
        if (!root) return [];
        return (root.matches && root.matches(selector) ? [root] : [])
          .concat(Array.from(root.querySelectorAll(selector)));
      };
      const tagCategory = (root) => {
        if (!root) return 'none';
        const tag = String(root.tagName || '').toLowerCase();
        return ['article', 'div', 'section', 'main'].includes(tag) ? tag : 'other';
      };
      const roleCategory = (root) => {
        if (!root) return 'none';
        const value = (root.getAttribute('role')
          || root.getAttribute('data-message-author-role')
          || root.getAttribute('data-message-role') || '').toLowerCase();
        return ['assistant', 'user', 'status', 'alert', 'textbox', 'button'].includes(value)
          ? value : value ? 'other' : 'none';
      };
      const testIDCategory = (root) => {
        if (!root) return 'none';
        if (root.matches('article[data-testid*="conversation-turn"], [data-testid="conversation-turn"]')) {
          return 'conversation_turn';
        }
        if (root.matches('[data-testid*="message"]')) return 'message';
        if (root.matches('[data-testid*="composer"]')) return 'composer';
        return root.hasAttribute('data-testid') ? 'other' : 'none';
      };
      const excludedWithinRoot = (node, root) => {
        let current = node;
        while (current) {
          if (current.matches && current.matches(RESPONSE_EXCLUDED_SELECTOR)) return true;
          if (current === root) return false;
          current = current.parentElement;
        }
        return true;
      };
      const semanticNodes = candidate
        ? nodesIncludingRoot(candidate, semanticSelector).filter((node) =>
            isRendered(node) && !excludedWithinRoot(node, candidate)
          )
        : [];
      const topLevelSemanticNodes = semanticNodes.filter((node) =>
        !semanticNodes.some((other) => other !== node && other.contains(node))
      );
      const notificationNodes = candidate
        ? nodesIncludingRoot(candidate, '[role="status"],[role="alert"],[aria-live]')
        : [];
      const notificationSemanticBlockPresent = topLevelSemanticNodes.some((node) =>
        notificationNodes.some((notification) =>
          notification === node || notification.contains(node)
        )
      );
      let ancestorDepth = null;
      if (candidate && selectedPath === 'fallback') {
        const controls = Array.from(
          document.querySelectorAll('button,[role="button"]')
        ).filter((element) => isResponseAction(element));
        for (let index = controls.length - 1; index >= 0 && ancestorDepth === null; index -= 1) {
          let ancestor = controls[index].parentElement;
          let depth = 0;
          while (ancestor
                 && ancestor !== document.body
                 && ancestor !== document.documentElement) {
            depth += 1;
            if (ancestor === candidate) {
              ancestorDepth = Math.min(depth, 64);
              break;
            }
            ancestor = ancestor.parentElement;
          }
        }
      }
      const turnMarkers = nodesIncludingRoot(candidate, turnMarkerSelector);
      const topLevelTurnMarkers = turnMarkers.filter((node) =>
        !turnMarkers.some((other) => other !== node && other.contains(node))
      );
      const has = (selector) => Boolean(candidate && (
        (candidate.matches && candidate.matches(selector)) || candidate.querySelector(selector)
      ));
      const actionCount = candidate ? responseActions(candidate).length : 0;
      return {
        version: 1,
        selected_path: selectedPath,
        candidate_tag_category: tagCategory(candidate),
        candidate_role_category: roleCategory(candidate),
        candidate_testid_category: testIDCategory(candidate),
        candidate_ancestor_depth: ancestorDepth,
        response_action_count: Math.min(actionCount, 255),
        semantic_block_count: Math.min(topLevelSemanticNodes.length, 255),
        has_user_marker: has('[data-message-author-role="user"],[data-message-role="user"]'),
        has_assistant_marker: has('[data-message-author-role="assistant"],[data-message-role="assistant"]'),
        has_status: has('[role="status"]'),
        has_alert: has('[role="alert"]'),
        has_live_region: has('[aria-live]'),
        has_composer: has(composerSelector),
        has_multiple_turns: topLevelTurnMarkers.length > 1,
        notification_semantic_block_present: notificationSemanticBlockPresent,
        structured_blocks_root_is_candidate: candidate !== null
      };
    };
    """
    private static let incidentOwnershipProbeExpression = """
    (() => {
      const probe = globalThis.__floatTabsDebugResponseOwnershipSnapshotV1;
      return typeof probe === 'function' ? probe() : null;
    })()
    """
#else
    private static let debugResponseOwnershipSnapshotProbeSource = ""
    private static let incidentOwnershipProbeExpression = "null"
#endif

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
      const responseOwnership = \(incidentOwnershipProbeExpression);
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
        conversation_load_error_present: Boolean(pageError),
        ...(responseOwnership ? { response_ownership: responseOwnership } : {})
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
        let debugOwnershipProbeSource = debugResponseOwnershipSnapshotProbeSource
#else
        let debugOwnershipProbeSource = ""
#endif
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

          // Passive, bounded page-app observation. No application networking
          // or navigation API is replaced, and no event text or URL is read.
          const PAGE_EVENT_LIMIT = 16;
          const PAGE_COUNTER_LIMIT = 255;
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
          let resourceTimingAvailable = false;
          let responseStatusAvailable = false;

          const incrementPageCount = (key) => {
            if (pageCounts[key] < PAGE_COUNTER_LIMIT) { pageCounts[key] += 1; }
          };
          const boundedAge = () => Math.min(
            Math.max(Math.floor(performance.now()), 0), 86400000
          );
          const pushPageEvent = (event) => {
            if (pageEvents.length === PAGE_EVENT_LIMIT) {
              pageEvents.shift();
              if (pageDroppedEvents < PAGE_COUNTER_LIMIT) { pageDroppedEvents += 1; }
            }
            pageEvents.push({
              kind: event.kind,
              category: event.category,
              resource_type: event.resource_type || "none",
              http_status: Number.isInteger(event.http_status) ? event.http_status : null,
              duration_bucket: event.duration_bucket || null,
              age_ms: boundedAge()
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
              pushPageEvent({ kind: "javascript_error", category: "global_error" });
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
            events: pageEvents.slice(0, PAGE_EVENT_LIMIT),
            dropped_events: pageDroppedEvents,
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
            const latestRoot = latestAssistantResponseRoot();
            target.postMessage({
              version: 1,
              kind: lastSent === null ? "baseline" : "state",
              token: TOKEN,
              generating: generating,
              responseIdentity: generating
                ? null
                : canonicalResponseIdentityFor(latestRoot)
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

          \(debugOwnershipProbeSource)

          const evaluate = () => {
            const generating = isGenerating();
            if (generating === lastSent) { return; }
            post(generating);
            lastSent = generating;
          };

          // Trailing coalescing: a burst of DOM mutations collapses into at most
          // one state read per window, while a sustained mutation stream (streamed
          // tokens) still gets periodic reads instead of postponing forever.
          const schedule = () => {
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
            observer = new MutationObserver(schedule);
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
            return {
              version: 1,
              kind: "baseline",
              token: TOKEN,
              generating: generating,
              responseIdentity: canonicalResponseIdentityFor(
                latestAssistantResponseRoot()
              )
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
              responseIdentity: canonicalResponseIdentityFor(
                latestAssistantResponseRoot()
              )
            };
          };
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
        let generation: UInt64
        let attempt: Int
        let webViewIdentity: ObjectIdentifier
    }

    private static let resyncAttemptLimit = 2

    let slotID: UUID
    private let onObservation: @MainActor (UUID, ChatGPTAttentionObservation) -> Void
    private let onAttentionEvent: (@MainActor (UUID, ChatGPTAttentionEvent) -> Void)?
    private let diagnostics: any RuntimeDiagnosticRecording
    private let livenessProbe: LivenessProbeProvider
    private let livenessSleeper: LivenessSleeper
    private let incidentHealthProbeEvaluator: ChatGPTIncidentHealthProbeEvaluator
    private let incidentPageAppProbeEvaluator: ChatGPTIncidentPageAppProbeEvaluator
    private let incidentHealthProbeTimeout: TimeInterval
    private weak var webView: WKWebView?
    private weak var userContentController: WKUserContentController?
    private var document: DocumentSession?
    /// The one runtime-only admission state. The current committed document,
    /// not a requested/provisional/persisted URL, controls whether a ChatGPT
    /// epoch may exist.
    private var documentAdmission = DocumentAdmission.awaitingSupportedBaseline
    private var pendingInstantBackHandoff: PendingInstantBackHandoff?
    private var pendingCurrentDocumentResync: PendingCurrentDocumentResync?
    private var nextResyncGeneration: UInt64 = 0
    private var nextDocumentEpoch: UInt64 = 0
    private var livenessWatchdogTask: Task<Void, Never>?
    private var livenessWatchdogGeneration: UInt64 = 0
    private var livenessGeneration: UInt64 = 0
    private var livenessCycleOwnerGeneration: UInt64?
    private var livenessIdleCandidateOwnerGeneration: UInt64?
    private var pendingIncidentHealthProbeID: UUID?
    private var incidentHealthProbeTimeoutTask: Task<Void, Never>?
    private var pendingIncidentPageAppProbeID: UUID?
    private var incidentPageAppProbeTimeoutTask: Task<Void, Never>?
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
        incidentHealthProbeTimeout: TimeInterval = ChatGPTAttentionBridge.defaultIncidentHealthProbeTimeout,
        onAttentionEvent: (@MainActor (UUID, ChatGPTAttentionEvent) -> Void)? = nil
    ) {
        self.slotID = slotID
        self.onObservation = onObservation
        self.onAttentionEvent = onAttentionEvent
        self.diagnostics = diagnostics
        self.livenessProbe = livenessProbe ?? Self.productionLivenessProbe
        self.livenessSleeper = livenessSleeper ?? Self.productionLivenessSleeper
        self.incidentHealthProbeEvaluator = incidentHealthProbeEvaluator
            ?? Self.productionIncidentHealthProbeEvaluator
        self.incidentPageAppProbeEvaluator = incidentPageAppProbeEvaluator
            ?? Self.productionIncidentPageAppProbeEvaluator
        self.incidentHealthProbeTimeout = min(
            max(incidentHealthProbeTimeout, 0),
            Self.defaultIncidentHealthProbeTimeout
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
        stopLivenessWatchdog()
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
        isInvalidated = true
        stopLivenessWatchdog()
        invalidatePendingCurrentDocumentResync()
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

    private func recordLivenessProbeFailure() {
        diagnostics.record(event: "attention.liveness_probe.failed", level: .debug, subsystem: "attention", fields: ["slot_id": .string(slotID.uuidString)])
    }

    private func performLivenessCycle(watchdogGeneration: UInt64, documentEpoch: UInt64, webView: WKWebView, webViewIdentity: ObjectIdentifier, token: String) async {
        guard livenessCycleOwnerGeneration == nil, isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token) else { return }
        livenessCycleOwnerGeneration = watchdogGeneration
        defer {
            if livenessCycleOwnerGeneration == watchdogGeneration {
                livenessCycleOwnerGeneration = nil
            }
        }
        let generation = livenessGeneration
        guard let firstValue = await livenessProbe(webView), let firstProbe = parseLivenessProbe(firstValue), isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token), firstProbe.token == token else {
            if isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token) { recordLivenessProbeFailure() }
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
        guard let secondValue = await livenessProbe(webView), let secondProbe = parseLivenessProbe(secondValue), secondProbe.token == token, isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token) else {
            if isCurrentLivenessContext(watchdogGeneration: watchdogGeneration, documentEpoch: documentEpoch, webView: webView, webViewIdentity: webViewIdentity, token: token) { recordLivenessProbeFailure() }
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
        diagnostics.record(event: "attention.liveness_probe.recovered_completion", level: .info, subsystem: "attention", fields: [
            "slot_id": .string(slotID.uuidString),
            "confirmation_count": .integer(2),
            "watchdog_interval_ms": .integer(2_000),
            "confirmation_delay_ms": .integer(250)
        ])
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

        nextResyncGeneration &+= 1
        let generation = nextResyncGeneration
        let pending = PendingCurrentDocumentResync(
            generation: generation,
            attempt: 1,
            webViewIdentity: ObjectIdentifier(webView)
        )
        pendingCurrentDocumentResync = pending
        evaluateCurrentDocumentResync(
            in: webView,
            generation: generation,
            attempt: pending.attempt
        )
    }

    private func evaluateCurrentDocumentResync(
        in webView: WKWebView,
        generation: UInt64,
        attempt: Int
    ) {
        webView.evaluateJavaScript(
            "globalThis.__floatTabsAttentionResyncV1?.()",
            in: nil,
            in: Self.contentWorld
        ) { [weak self, weak webView] (result: Result<Any, Error>) in
            guard let self,
                  let webView,
                  !self.isInvalidated,
                  self.webView === webView,
                  let pending = self.pendingCurrentDocumentResync,
                  pending.generation == generation,
                  pending.attempt == attempt,
                  pending.webViewIdentity == ObjectIdentifier(webView) else {
                return
            }

            if case let .success(value) = result,
               let body = value as? [String: Any],
               let payload = ChatGPTBridgePayload.parse(body),
               payload.kind == ChatGPTBridgePayload.baselineKind {
                self.pendingCurrentDocumentResync = nil
                self.acceptAuthorizedCurrentDocumentBaseline(payload)
                return
            }

            guard attempt < Self.resyncAttemptLimit else {
                // Keep the authorization barrier closed after bounded failure.
                // A later ordinary runtime replacement owns recovery; no
                // arbitrary baseline may reopen this epoch.
                self.pendingCurrentDocumentResync = nil
                return
            }

            let retry = PendingCurrentDocumentResync(
                generation: generation,
                attempt: attempt + 1,
                webViewIdentity: ObjectIdentifier(webView)
            )
            self.pendingCurrentDocumentResync = retry
            self.evaluateCurrentDocumentResync(
                in: webView,
                generation: generation,
                attempt: retry.attempt
            )
        }
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
    }
}
