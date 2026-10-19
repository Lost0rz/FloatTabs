import Combine
import Darwin
import OSLog
import WebKit

enum WebRuntimeLivenessWorld: String, Equatable, Sendable {
    case mainPage = "main_page"
    case floatTabsIsolated = "floattabs_isolated"
}

enum WebRuntimeLivenessOutcome: String, Equatable, Sendable {
    case success
    case timeout
    case failed
    case stale
}

struct WebRuntimeLivenessProbeResult: Equatable, Sendable {
    let outcome: WebRuntimeLivenessOutcome
    let readyState: String?
    let visibilityState: String?
    let latencyMilliseconds: Double

    static func success(
        readyState: String,
        visibilityState: String,
        latencyMilliseconds: Double
    ) -> Self {
        Self(
            outcome: .success,
            readyState: readyState,
            visibilityState: visibilityState,
            latencyMilliseconds: latencyMilliseconds
        )
    }

    static func terminal(
        _ outcome: WebRuntimeLivenessOutcome,
        latencyMilliseconds: Double
    ) -> Self {
        Self(
            outcome: outcome,
            readyState: nil,
            visibilityState: nil,
            latencyMilliseconds: latencyMilliseconds
        )
    }

    var stale: Self {
        .terminal(.stale, latencyMilliseconds: latencyMilliseconds)
    }

    func diagnosticFields(prefix: String) -> [String: RuntimeDiagnosticValue] {
        [
            "\(prefix)_probe_outcome": .string(outcome.rawValue),
            "\(prefix)_probe_latency_ms": .double(min(max(latencyMilliseconds, 0), 5_000)),
            "\(prefix)_document_ready_state": readyState.map(RuntimeDiagnosticValue.string) ?? .null,
            "\(prefix)_document_visibility_state": visibilityState.map(RuntimeDiagnosticValue.string) ?? .null
        ]
    }
}

typealias WebRuntimeLivenessProbeEvaluator = @MainActor (
    WKWebView,
    WebRuntimeLivenessWorld
) async -> WebRuntimeLivenessProbeResult

@MainActor
private final class WebRuntimeLivenessProbeGate {
    private var continuation: CheckedContinuation<WebRuntimeLivenessProbeResult, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var finished = false

    func install(_ continuation: CheckedContinuation<WebRuntimeLivenessProbeResult, Never>) {
        self.continuation = continuation
    }

    func installTimeoutTask(_ task: Task<Void, Never>) {
        timeoutTask = task
    }

    func finish(_ result: WebRuntimeLivenessProbeResult) {
        guard !finished else { return }
        finished = true
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }
}

@MainActor
final class WebFocusRouter: ObservableObject {
    @Published private(set) var currentTarget: WebFocusTarget = .unavailable
    @Published private(set) var currentWebsiteIdentifier: String?

    private(set) weak var currentWebView: WKWebView?
    private(set) var currentAdapter: (any WebSiteAdapter)?
    private let registry: WebSiteAdapterRegistry
    private let diagnostics: any RuntimeDiagnosticRecording
    private let logger = Logger(subsystem: "com.lost0rz.FloatTabs", category: "WebFocus")
    private let livenessProbeEvaluator: WebRuntimeLivenessProbeEvaluator
    private let livenessProbeIntervalNanoseconds: UInt64
    private var livenessObservationTask: Task<Void, Never>?
    private var livenessGeneration: UInt64 = 0
    private var livenessObservationStartedAt: TimeInterval?
    private var consecutivePostFinishDualTimeouts = 0

    static let defaultLivenessProbeInterval: TimeInterval = 30
    static let defaultLivenessProbeTimeout: TimeInterval = 5
    static let postFinishStallConfirmationCount = 2

    var onTransition: ((WebFocusTransition) -> Void)?

    init(
        registry: WebSiteAdapterRegistry = WebSiteAdapterRegistry(),
        diagnostics: any RuntimeDiagnosticRecording = RuntimeDiagnosticNoopRecorder(),
        livenessProbeInterval: TimeInterval = WebFocusRouter.defaultLivenessProbeInterval,
        livenessProbeTimeout: TimeInterval = WebFocusRouter.defaultLivenessProbeTimeout,
        livenessProbeEvaluator: WebRuntimeLivenessProbeEvaluator? = nil
    ) {
        self.registry = registry
        self.diagnostics = diagnostics
        let normalizedInterval = min(max(livenessProbeInterval, 1), 300)
        let normalizedTimeout = min(max(livenessProbeTimeout, 0.1), 5)
        livenessProbeIntervalNanoseconds = UInt64(normalizedInterval * 1_000_000_000)
        self.livenessProbeEvaluator = livenessProbeEvaluator ?? { webView, world in
            await Self.productionLivenessProbe(
                webView: webView,
                world: world,
                timeout: normalizedTimeout
            )
        }
    }

    func setCurrentWebView(_ webView: WKWebView?) {
        guard currentWebView !== webView else { return }
        diagnostics.record(
            event: "web_focus.webview_changed",
            level: .debug,
            subsystem: "focus",
            fields: ["has_webview": .bool(webView != nil)]
        )
        livenessObservationTask?.cancel()
        livenessObservationTask = nil
        precondition(livenessGeneration < UInt64.max, "Web runtime liveness generation exhausted")
        livenessGeneration += 1
        consecutivePostFinishDualTimeouts = 0
        livenessObservationStartedAt = webView == nil ? nil : ProcessInfo.processInfo.systemUptime
        currentWebView = webView
        currentAdapter = nil
        currentWebsiteIdentifier = nil
        currentTarget = .unavailable

        guard let webView else { return }
        startCrossWorldLivenessObservation(for: webView)
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            await self.refreshRecognition(for: webView)
        }
    }

    /// Re-identifies the adapter and DOM on navigation/SPA transitions. The
    /// toggle path also calls this implicitly, so a refresh never depends on a
    /// stale DOM node or a stale adapter decision.
    func refreshRecognition() async {
        guard let webView = currentWebView else {
            currentAdapter = nil
            currentWebsiteIdentifier = nil
            currentTarget = .unavailable
            return
        }
        await refreshRecognition(for: webView)
    }

    func refreshRecognition(for webView: WKWebView) async {
        guard currentWebView === webView else { return }
        let adapter = await registry.adapter(for: webView.url, webView: webView)
        currentAdapter = adapter
        currentWebsiteIdentifier = adapter.identifier
        do {
            currentTarget = try await adapter.currentFocus(in: webView)
            diagnostics.record(
                event: "web_focus.recognition",
                level: .debug,
                subsystem: "focus",
                fields: [
                    "site": .string(adapter.identifier),
                    "target": .string(currentTarget.rawValue),
                    "success": .bool(true)
                ]
            )
        } catch {
            currentTarget = .unavailable
            var fields = RuntimeDiagnosticPrivacy.sanitizedErrorCategory(error)
            fields["success"] = .bool(false)
            diagnostics.record(
                event: "web_focus.recognition",
                level: .warning,
                subsystem: "focus",
                fields: fields
            )
        }
    }

    @discardableResult
    func captureInputTargetForExternalVoice() async -> WebFocusVoiceTarget {
        guard let webView = currentWebView else { return .none }
        let adapter = await registry.adapter(for: webView.url, webView: webView)
        currentAdapter = adapter
        currentWebsiteIdentifier = adapter.identifier
        do {
            let captured = try await adapter.captureInputTargetForVoice(in: webView)
            logger.debug(
                "voice focus target captured=\(captured.succeeded, privacy: .public) site=\(adapter.identifier, privacy: .public)"
            )
            diagnostics.record(
                event: "web_focus.capture_voice_target",
                level: .info,
                subsystem: "focus",
                fields: [
                    "site": .string(adapter.identifier),
                    "captured": .bool(captured.succeeded),
                    "voice_target_kind": .string(captured.kind.rawValue),
                    "voice_target_source": .string(captured.source.rawValue)
                ]
            )
            return captured
        } catch {
            logger.error(
                "voice focus target capture failed site=\(adapter.identifier, privacy: .public) category=\(RuntimeDiagnosticPrivacy.safeErrorCategory(error), privacy: .public) domain=\(RuntimeDiagnosticPrivacy.safeErrorDomain(error), privacy: .public) code=\(RuntimeDiagnosticPrivacy.safeErrorCode(error), privacy: .public)"
            )
            var failureFields = RuntimeDiagnosticPrivacy.sanitizedErrorCategory(error)
            failureFields["focus_owner"] = .string("external_voice")
            failureFields["voice_target_kind"] = .string(WebFocusVoiceTargetKind.none.rawValue)
            failureFields["voice_target_source"] = .string(WebFocusVoiceTargetSource.none.rawValue)
            diagnostics.record(
                event: "web_focus.failed",
                level: .warning,
                subsystem: "focus",
                fields: failureFields
            )
            return .none
        }
    }

    func focusInputForPresentation(
        preservingCapturedTarget: Bool = false,
        trace: RuntimeDiagnosticTrace? = nil
    ) async -> Bool {
        guard let webView = currentWebView else { return false }
        let adapter = await registry.adapter(for: webView.url, webView: webView)
        currentAdapter = adapter
        currentWebsiteIdentifier = adapter.identifier
        do {
            let voiceTarget: WebFocusVoiceTarget
            if preservingCapturedTarget {
                voiceTarget = try await adapter.focusInputForVoice(in: webView)
            } else {
                try await adapter.focusInput(in: webView)
                voiceTarget = .none
            }
            currentTarget = .input
            logger.debug(
                "voice focus restored captured=\(preservingCapturedTarget, privacy: .public) site=\(adapter.identifier, privacy: .public)"
            )
            diagnostics.record(
                event: "web_focus.presentation.completed",
                level: .info,
                subsystem: "focus",
                trace: trace,
                fields: [
                    "site": .string(adapter.identifier),
                    "preserved_capture": .bool(preservingCapturedTarget),
                    "focus_owner": .string(
                        preservingCapturedTarget ? "external_voice" : "standard_presentation"
                    ),
                    "voice_target_kind": .string(voiceTarget.kind.rawValue),
                    "voice_target_source": .string(voiceTarget.source.rawValue)
                ]
            )
            return true
        } catch {
            logger.error(
                "voice focus restore failed captured=\(preservingCapturedTarget, privacy: .public) site=\(adapter.identifier, privacy: .public) category=\(RuntimeDiagnosticPrivacy.safeErrorCategory(error), privacy: .public) domain=\(RuntimeDiagnosticPrivacy.safeErrorDomain(error), privacy: .public) code=\(RuntimeDiagnosticPrivacy.safeErrorCode(error), privacy: .public)"
            )
            var failureFields = RuntimeDiagnosticPrivacy.sanitizedErrorCategory(error)
            if preservingCapturedTarget {
                failureFields["focus_owner"] = .string("external_voice")
                failureFields["voice_target_kind"] = .string(WebFocusVoiceTargetKind.none.rawValue)
                failureFields["voice_target_source"] = .string(WebFocusVoiceTargetSource.none.rawValue)
            }
            diagnostics.record(
                event: "web_focus.failed",
                level: .warning,
                subsystem: "focus",
                trace: trace,
                fields: failureFields
            )
            return false
        }
    }

    func isInputFocusReady() async -> Bool {
        guard let webView = currentWebView else { return false }
        let adapter = await registry.adapter(for: webView.url, webView: webView)
        currentAdapter = adapter
        currentWebsiteIdentifier = adapter.identifier
        do {
            let target = try await adapter.currentFocus(in: webView)
            currentTarget = target
            return target == .input
        } catch {
            currentTarget = .unavailable
            return false
        }
    }

    @discardableResult
    func togglePrimaryFocus(trace: RuntimeDiagnosticTrace? = nil) async -> WebFocusTransition {
        guard let webView = currentWebView else {
            return recordFailure(
                websiteIdentifier: currentWebsiteIdentifier ?? "unavailable",
                from: currentTarget,
                to: .unavailable,
                error: WebFocusAdapterError.noWebView,
                trace: trace
            )
        }

        let adapter = await registry.adapter(for: webView.url, webView: webView)
        currentAdapter = adapter
        currentWebsiteIdentifier = adapter.identifier

        let from: WebFocusTarget
        do {
            from = try await adapter.currentFocus(in: webView)
        } catch {
            from = .unavailable
        }
        currentTarget = from

        let destination: WebFocusTarget = from == .input ? .page : .input
        do {
            let focused = try await adapter.togglePrimaryFocus(in: webView)
            currentTarget = focused
            return recordSuccess(
                websiteIdentifier: adapter.identifier,
                from: from,
                to: focused,
                trace: trace
            )
        } catch {
            currentTarget = .unavailable
            return recordFailure(
                websiteIdentifier: adapter.identifier,
                from: from,
                to: destination,
                error: error,
                trace: trace
            )
        }
    }

    /// Read-only incident seam. Production uses the periodic loop below; tests
    /// call this directly so stall classification can be verified without
    /// waiting on wall-clock timers.
    func captureCrossWorldLivenessOnce() async {
        guard let webView = currentWebView,
              let url = webView.url,
              ChatGPTSitePolicy.isSupportedChatGPTURL(url) else {
            return
        }

        let generation = livenessGeneration
        let observationStartedAt = ProcessInfo.processInfo.systemUptime
        async let mainRaw = livenessProbeEvaluator(webView, .mainPage)
        async let isolatedRaw = livenessProbeEvaluator(webView, .floatTabsIsolated)
        let (mainCaptured, isolatedCaptured) = await (mainRaw, isolatedRaw)

        let runtimeContextCurrent = currentWebView === webView && livenessGeneration == generation
        let main = runtimeContextCurrent ? mainCaptured : mainCaptured.stale
        let isolated = runtimeContextCurrent ? isolatedCaptured : isolatedCaptured.stale
        let observer = webView.navigationDelegate as? SlotNavigationObserver
        let correlationFields = observer?.currentRuntimeCorrelationFields ?? [:]
        let navigationFinished = correlationFields["navigation_phase"] == .string("finished")
        let nativeFinishedFacts = !webView.isLoading && webView.estimatedProgress >= 0.999
        let postFinishBoundary = navigationFinished && nativeFinishedFacts
        let dualTimeout = main.outcome == .timeout && isolated.outcome == .timeout

        if runtimeContextCurrent && postFinishBoundary && dualTimeout {
            consecutivePostFinishDualTimeouts += 1
        } else {
            consecutivePostFinishDualTimeouts = 0
        }

        var fields = diagnostics.environmentFields()
        fields.merge(main.diagnosticFields(prefix: "main_world")) { _, new in new }
        fields.merge(isolated.diagnosticFields(prefix: "isolated_world")) { _, new in new }
        fields.merge([
            "runtime_context_current": .bool(runtimeContextCurrent),
            "navigation_finished": .bool(navigationFinished),
            "native_finished_facts": .bool(nativeFinishedFacts),
            "is_loading": .bool(webView.isLoading),
            "estimated_progress": .double(webView.estimatedProgress),
            "webview_hidden": .bool(webView.isHidden),
            "webview_window_visible": .bool(webView.window?.isVisible == true),
            "post_finish_dual_timeout_count": .integer(Int64(consecutivePostFinishDualTimeouts)),
            "probe_cycle_latency_ms": .double(
                min(max(ProcessInfo.processInfo.systemUptime - observationStartedAt, 0) * 1_000, 10_000)
            ),
            "system_physical_memory_bytes": Self.diagnosticInteger(ProcessInfo.processInfo.physicalMemory),
            "webcontent_resource_attribution": .string("unavailable_public_api")
        ]) { _, new in new }
        if let selectedAt = livenessObservationStartedAt {
            fields["selected_runtime_observation_age_ms"] = .double(
                max(0, ProcessInfo.processInfo.systemUptime - selectedAt) * 1_000
            )
        }
        if let residentSize = Self.currentProcessResidentSizeBytes() {
            fields["host_resident_size_bytes"] = Self.diagnosticInteger(residentSize)
        } else {
            fields["host_resident_size_bytes"] = .null
        }
        fields.merge(correlationFields) { current, _ in current }

        diagnostics.record(
            event: "web_runtime.cross_world_liveness",
            level: dualTimeout ? .warning : .notice,
            subsystem: "web",
            fields: fields
        )

        guard runtimeContextCurrent, postFinishBoundary, dualTimeout else { return }
        var stallFields = fields
        stallFields["stall_class"] = .string("POST_FINISH_RUNTIME_STALL")
        stallFields["stall_confirmation_state"] = .string(
            consecutivePostFinishDualTimeouts >= Self.postFinishStallConfirmationCount
                ? "confirmed"
                : "candidate"
        )
        diagnostics.record(
            event: consecutivePostFinishDualTimeouts >= Self.postFinishStallConfirmationCount
                ? "web_runtime.post_finish_stall_detected"
                : "web_runtime.post_finish_stall_candidate",
            level: .warning,
            subsystem: "web",
            fields: stallFields
        )
    }

    private func startCrossWorldLivenessObservation(for webView: WKWebView) {
        livenessObservationTask?.cancel()
        livenessObservationTask = Task { @MainActor [weak self, weak webView] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: self?.livenessProbeIntervalNanoseconds ?? 0)
                } catch {
                    return
                }
                guard let self, let webView, self.currentWebView === webView else { return }
                await self.captureCrossWorldLivenessOnce()
            }
        }
    }

    private static let runtimeLivenessProbeScript = """
    (() => ({
      ready_state: ["loading", "interactive", "complete"].includes(document.readyState)
        ? document.readyState : "other",
      visibility_state: ["visible", "hidden", "prerender", "unloaded"].includes(document.visibilityState)
        ? document.visibilityState : "other"
    }))()
    """

    private static func productionLivenessProbe(
        webView: WKWebView,
        world: WebRuntimeLivenessWorld,
        timeout: TimeInterval
    ) async -> WebRuntimeLivenessProbeResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let gate = WebRuntimeLivenessProbeGate()
        return await withCheckedContinuation { continuation in
            gate.install(continuation)
            let timeoutTask = Task { @MainActor [weak gate] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                } catch {
                    return
                }
                gate?.finish(.terminal(.timeout, latencyMilliseconds: timeout * 1_000))
            }
            gate.installTimeoutTask(timeoutTask)

            let finishValue: @MainActor (Any?, Error?) -> Void = { value, error in
                let latency = min(
                    max(ProcessInfo.processInfo.systemUptime - startedAt, 0) * 1_000,
                    5_000
                )
                guard error == nil,
                      let fields = value as? [String: Any],
                      let readyState = fields["ready_state"] as? String,
                      let visibilityState = fields["visibility_state"] as? String,
                      ["loading", "interactive", "complete", "other"].contains(readyState),
                      ["visible", "hidden", "prerender", "unloaded", "other"].contains(visibilityState) else {
                    gate.finish(.terminal(.failed, latencyMilliseconds: latency))
                    return
                }
                gate.finish(
                    .success(
                        readyState: readyState,
                        visibilityState: visibilityState,
                        latencyMilliseconds: latency
                    )
                )
            }

            switch world {
            case .mainPage:
                webView.evaluateJavaScript(Self.runtimeLivenessProbeScript) { value, error in
                    finishValue(value, error)
                }
            case .floatTabsIsolated:
                webView.evaluateJavaScript(
                    Self.runtimeLivenessProbeScript,
                    in: nil,
                    in: ChatGPTAttentionBridge.contentWorld
                ) { result in
                    switch result {
                    case let .success(value): finishValue(value, nil)
                    case let .failure(error): finishValue(nil, error)
                    }
                }
            }
        }
    }

    private static func currentProcessResidentSizeBytes() -> UInt64? {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    rebound,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
    }

    private static func diagnosticInteger(_ value: UInt64) -> RuntimeDiagnosticValue {
        .integer(value > UInt64(Int64.max) ? Int64.max : Int64(value))
    }

    private func recordSuccess(
        websiteIdentifier: String,
        from: WebFocusTarget,
        to: WebFocusTarget,
        trace: RuntimeDiagnosticTrace?
    ) -> WebFocusTransition {
        let transition = WebFocusTransition(
            websiteIdentifier: websiteIdentifier,
            from: from,
            to: to,
            succeeded: true,
            failureReason: nil
        )
        logger.info(
            "focus toggle site=\(websiteIdentifier, privacy: .public) from=\(from.rawValue, privacy: .public) to=\(to.rawValue, privacy: .public) success=true"
        )
        diagnostics.record(
            event: "web_focus.toggle",
            level: .info,
            subsystem: "focus",
            trace: trace,
            fields: [
                "site": .string(websiteIdentifier),
                "from": .string(from.rawValue),
                "to": .string(to.rawValue),
                "success": .bool(true)
            ]
        )
        onTransition?(transition)
        return transition
    }

    private func recordFailure(
        websiteIdentifier: String,
        from: WebFocusTarget,
        to: WebFocusTarget,
        error: Error,
        trace: RuntimeDiagnosticTrace?
    ) -> WebFocusTransition {
        let transition = WebFocusTransition(
            websiteIdentifier: websiteIdentifier,
            from: from,
            to: to,
            succeeded: false,
            failureReason: error.localizedDescription
        )
        logger.error(
            "focus toggle site=\(websiteIdentifier, privacy: .public) from=\(from.rawValue, privacy: .public) to=\(to.rawValue, privacy: .public) success=false category=\(Self.errorCategory(error), privacy: .public)"
        )
        var fields = RuntimeDiagnosticPrivacy.sanitizedErrorCategory(error)
        fields["site"] = .string(websiteIdentifier)
        fields["from"] = .string(from.rawValue)
        fields["to"] = .string(to.rawValue)
        fields["success"] = .bool(false)
        diagnostics.record(
            event: "web_focus.toggle",
            level: .warning,
            subsystem: "focus",
            trace: trace,
            fields: fields
        )
        diagnostics.record(
            event: "web_focus.failed",
            level: .warning,
            subsystem: "focus",
            trace: trace,
            fields: fields
        )
        onTransition?(transition)
        return transition
    }

    private static func errorCategory(_ error: Error) -> String {
        guard let value = RuntimeDiagnosticPrivacy.sanitizedErrorCategory(error)["error_category"] else {
            return "runtime"
        }
        if case let .string(category) = value { return category }
        return "runtime"
    }
}
