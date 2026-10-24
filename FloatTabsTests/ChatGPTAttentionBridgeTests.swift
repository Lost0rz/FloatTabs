import WebKit
import JavaScriptCore
import XCTest
@testable import FloatTabs

/// Collects observations from one detached bridge so tests can drive the
/// exact production acceptance pipeline without a live page.
@MainActor
private final class ChatGPTAttentionBridgeHarness {
    private final class ProbeSequence {
        var values: [Any?]
        private(set) var count = 0

        init(values: [Any?]) {
            self.values = values
        }

        func next() -> Any? {
            count += 1
            guard !values.isEmpty else { return nil }
            return values.removeFirst()
        }
    }

    private final class ObservationLog {
        private(set) var entries: [ChatGPTAttentionObservation] = []

        func record(_ observation: ChatGPTAttentionObservation) {
            entries.append(observation)
        }
    }

    let slotID = UUID()
    let webView = WKWebView()
    let bridge: ChatGPTAttentionBridge
    private let log = ObservationLog()

    var observations: [ChatGPTAttentionObservation] { log.entries }

    init(
        probeValues: [Any?] = [],
        incidentHealthProbeEvaluator: ChatGPTIncidentHealthProbeEvaluator? = nil,
        incidentPageAppProbeEvaluator: ChatGPTIncidentPageAppProbeEvaluator? = nil,
        benchmarkProbeEvaluator: ChatGPTBenchmarkProbeEvaluator? = nil,
        incidentHealthProbeTimeout: TimeInterval = ChatGPTAttentionBridge.defaultIncidentHealthProbeTimeout,
        longTermWorkloadTimeout: TimeInterval = ChatGPTAttentionBridge.defaultLongTermWorkloadTimeout
    ) {
        // The observation callback must not capture the harness itself before
        // initialization completes; the log reference it captures is enough.
        let log = self.log
        let probes = ProbeSequence(values: probeValues)
        bridge = ChatGPTAttentionBridge(
            slotID: slotID,
            onObservation: { _, observation in
                log.record(observation)
            },
            livenessProbe: { _ in
                probes.next()
            },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            },
            incidentHealthProbeEvaluator: incidentHealthProbeEvaluator,
            incidentPageAppProbeEvaluator: incidentPageAppProbeEvaluator,
            benchmarkProbeEvaluator: benchmarkProbeEvaluator,
            incidentHealthProbeTimeout: incidentHealthProbeTimeout,
            longTermWorkloadTimeout: longTermWorkloadTimeout
        )
        bridge.attach(to: webView)
        probeCount = { probes.count }
    }

    private(set) var probeCount: () -> Int = { 0 }

    func accept(
        _ generating: Bool,
        token: String,
        host: String = "chatgpt.com",
        originProtocol: String = "https",
        isMainFrame: Bool = true,
        kind: String = ChatGPTBridgePayload.baselineKind,
        messageWebView: WKWebView? = nil
    ) {
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: ChatGPTBridgePayload.currentVersion,
                kind: kind,
                token: token,
                generating: generating
            ),
            messageWebView: messageWebView ?? webView,
            isMainFrame: isMainFrame,
            originHost: host,
            originProtocol: originProtocol
        )
    }
}

@MainActor
private final class IncidentHealthProbeGate {
    private var continuation: CheckedContinuation<Any, Error>?

    func evaluate() async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func resolve(_ value: Any) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }
}

@MainActor
private final class CurrentDocumentResyncGate {
    private var continuation: CheckedContinuation<Any, Error>?

    func evaluate() async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func resolve(_ value: Any) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: value)
    }
}

@MainActor
private final class CurrentDocumentResyncBudgetGate {
    private var continuations: [CheckedContinuation<Any, Error>] = []
    private(set) var callCount = 0

    func evaluate() async throws -> Any {
        callCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilStarted(_ expectedCallCount: Int) async {
        while callCount < expectedCallCount {
            await Task.yield()
        }
    }

    func resolveAll(_ value: Any) {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume(returning: value) }
    }
}

@MainActor
private final class ChatGPTLongTermObservationSleeper {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private var waiters: [Waiter] = []
    private(set) var requestedIntervals: [TimeInterval] = []

    var pendingCount: Int { waiters.count }

    func sleep(_ interval: TimeInterval) async throws {
        let id = UUID()
        requestedIntervals.append(interval)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resume(id: id, throwing: CancellationError())
            }
        }
    }

    func advanceNext() {
        guard let waiter = waiters.first else { return }
        waiters.removeFirst()
        waiter.continuation.resume()
    }

    private func resume(id: UUID, throwing error: Error) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: error)
    }
}

@MainActor
private final class LivenessProbeGate {
    private var queuedValues: [Any?] = []
    private var suspendedContinuations: [CheckedContinuation<Any?, Never>] = []
    private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var callCount = 0

    func next() async -> Any? {
        callCount += 1
        let readyWaiters = callWaiters.filter { $0.0 <= callCount }
        callWaiters.removeAll { $0.0 <= callCount }
        readyWaiters.forEach { $0.1.resume() }

        if !queuedValues.isEmpty {
            return queuedValues.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            suspendedContinuations.append(continuation)
        }
    }

    func enqueue(_ values: [Any?]) {
        queuedValues.append(contentsOf: values)
    }

    func waitForCall(_ expectedCallCount: Int) async {
        guard callCount < expectedCallCount else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((expectedCallCount, continuation))
        }
    }

    func resumeSuspended(_ value: Any?) {
        precondition(!suspendedContinuations.isEmpty)
        suspendedContinuations.removeFirst().resume(returning: value)
    }
}

@MainActor
private final class LivenessConfirmationGate {
    private var continuations: [Int: CheckedContinuation<Bool, Never>] = [:]
    private var callWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var callCount = 0

    var isWaiting: Bool { !continuations.isEmpty }

    func sleep(_ nanoseconds: UInt64) async -> Bool {
        guard nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds else {
            return false
        }
        callCount += 1
        let callIndex = callCount
        let readyWaiters = callWaiters.filter { $0.0 <= callCount }
        callWaiters.removeAll { $0.0 <= callCount }
        readyWaiters.forEach { $0.1.resume() }
        return await withCheckedContinuation { continuation in
            continuations[callIndex] = continuation
        }
    }

    func waitForCall(_ expectedCallCount: Int) async {
        guard callCount < expectedCallCount else { return }
        await withCheckedContinuation { continuation in
            callWaiters.append((expectedCallCount, continuation))
        }
    }

    func resume(call callIndex: Int) {
        guard let continuation = continuations.removeValue(forKey: callIndex) else { return }
        continuation.resume(returning: true)
    }

    func resume() {
        guard let callIndex = continuations.keys.min() else { return }
        resume(call: callIndex)
    }
}

private final class FTDiag004FailingResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        urlSchemeTask.didFailWithError(NSError(domain: "FTDiag004Fixture", code: 1))
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

@MainActor
final class ChatGPTAttentionBridgeTests: XCTestCase {
    private var tokenA: String!
    private var tokenB: String!

    override func setUp() {
        super.setUp()
        tokenA = UUID().uuidString
        tokenB = UUID().uuidString
    }

    func testRealWKWebViewPageWorldFailuresReachIncidentSnapshot() async throws {
        let bridge = ChatGPTAttentionBridge(slotID: UUID()) { _, _ in }
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            FTDiag004FailingResourceSchemeHandler(),
            forURLScheme: "ftdiag004"
        )
        bridge.install(into: configuration.userContentController)
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            configuration: configuration
        )
        bridge.attach(to: webView)

        let fixture = """
        <!doctype html>
        <html><head>
          <script>
            setTimeout(() => {
              throw new Error("FT_DIAG_004_PRIVATE_ERROR_MESSAGE");
            }, 0);
            Promise.reject(new Error("FT_DIAG_004_PRIVATE_REJECTION_REASON"));
          </script>
          <script src="ftdiag004://fixture/FT_DIAG_004_PRIVATE_RESOURCE_URL?token=fixture"></script>
        </head><body><main></main></body></html>
        """
        webView.loadHTMLString(fixture, baseURL: URL(string: "https://chatgpt.com/")!)

        let documentAdmitted = await waitUntil(timeout: 10) {
            bridge.diagnosticSnapshotFields["attention_document_admitted"] == .bool(true)
        }
        XCTAssertTrue(documentAdmitted, "the production bridge must admit the local ChatGPT fixture")
        guard documentAdmitted else { return }

        let result: ChatGPTIncidentPageAppProbeResult = await withCheckedContinuation { continuation in
            bridge.captureIncidentPageAppDiagnostics(
                for: webView,
                contextIsCurrent: { true }
            ) { result in
                continuation.resume(returning: result)
            }
        }

        XCTAssertEqual(result.outcome, .success)
        let snapshot = try XCTUnwrap(result.values)
        XCTAssertGreaterThan(snapshot.javascriptErrorCount, 0)
        XCTAssertGreaterThan(snapshot.unhandledRejectionCount, 0)
        XCTAssertGreaterThan(snapshot.resourceLoadFailureCount, 0)
        XCTAssertTrue(snapshot.events.contains {
            $0.kind == "javascript_error" && $0.category == "global_error"
        })
        XCTAssertTrue(snapshot.events.contains {
            $0.kind == "unhandled_rejection" && $0.category == "unhandled_rejection"
        })
        XCTAssertTrue(snapshot.events.contains {
            $0.kind == "resource_load_failure"
                && $0.category == "script_load"
                && $0.resourceType == "script"
        })

        let capturedMetadata = String(reflecting: result.diagnosticFields)
        for privateValue in [
            "FT_DIAG_004_PRIVATE_ERROR_MESSAGE",
            "FT_DIAG_004_PRIVATE_REJECTION_REASON",
            "FT_DIAG_004_PRIVATE_RESOURCE_URL"
        ] {
            XCTAssertFalse(capturedMetadata.contains(privateValue))
        }

        var runtimeAndNavigationAreCurrent = true
        var staleResult: ChatGPTIncidentPageAppProbeResult?
        bridge.captureIncidentPageAppDiagnostics(
            for: webView,
            contextIsCurrent: { runtimeAndNavigationAreCurrent }
        ) { result in
            staleResult = result
        }
        runtimeAndNavigationAreCurrent = false
        let staleCaptureCompleted = await waitUntil(timeout: 5) { staleResult != nil }
        XCTAssertTrue(staleCaptureCompleted)
        XCTAssertEqual(staleResult?.outcome, .stale)
        XCTAssertNil(staleResult?.values)
    }

    override func tearDown() {
        tokenA = nil
        tokenB = nil
        super.tearDown()
    }

    func testExplicitIncidentHealthProbePopulatesSupportedDocumentBooleans() async {
        var evaluatedScript: String?
        let harness = ChatGPTAttentionBridgeHarness(
            incidentHealthProbeEvaluator: { _, script in
                evaluatedScript = script
                return Self.healthProbePayload()
            }
        )
        harness.accept(false, token: tokenA)

        let result = await captureHealthProbe(harness)

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.documentEpoch, 1)
        XCTAssertEqual(result.generating, false)
        XCTAssertEqual(evaluatedScript, ChatGPTAttentionBridge.incidentHealthProbeScript)
        XCTAssertNotNil(result.values)
        XCTAssertEqual(result.diagnosticFields["attention_document_admitted"], .bool(true))
        XCTAssertEqual(result.diagnosticFields["document_ready_state"], .string("complete"))
        XCTAssertEqual(result.diagnosticFields["visibility_state"], .string("visible"))
        XCTAssertEqual(result.diagnosticFields["conversation_shell_present"], .bool(true))
        XCTAssertEqual(result.diagnosticFields["composer_present"], .bool(true))
        XCTAssertEqual(result.diagnosticFields["loading_indicator_present"], .bool(false))
        XCTAssertEqual(result.diagnosticFields["loading_indicator_visible"], .bool(false))
        XCTAssertEqual(result.diagnosticFields["conversation_load_error_present"], .bool(false))
    }

    func testIncidentHealthProbeReturnsExplicitUnsupportedAndUnavailableOutcomes() async {
        var evaluatorCalls = 0
        let unsupported = ChatGPTAttentionBridgeHarness(
            incidentHealthProbeEvaluator: { _, _ in
                evaluatorCalls += 1
                return Self.healthProbePayload()
            }
        )
        unsupported.bridge.handleRuntimeReplacement(
            committedURL: URL(string: "https://example.org/")
        )
        let unsupportedResult = await captureHealthProbe(unsupported)
        XCTAssertEqual(unsupportedResult.outcome, .unsupportedDocument)
        XCTAssertNil(unsupportedResult.values)

        let unavailable = ChatGPTAttentionBridgeHarness(
            incidentHealthProbeEvaluator: { _, _ in
                evaluatorCalls += 1
                return Self.healthProbePayload()
            }
        )
        let unavailableResult = await captureHealthProbe(unavailable)
        XCTAssertEqual(unavailableResult.outcome, .bridgeUnavailable)
        XCTAssertNil(unavailableResult.values)
        XCTAssertEqual(evaluatorCalls, 0)
    }

    func testIncidentHealthProbeEvaluationFailureIsExplicitAndContentFree() async {
        let harness = ChatGPTAttentionBridgeHarness(
            incidentHealthProbeEvaluator: { _, _ in
                throw NSError(domain: "HealthProbeTest", code: 1)
            }
        )
        harness.accept(false, token: tokenA)

        let result = await captureHealthProbe(harness)

        XCTAssertEqual(result.outcome, .evaluationFailed)
        XCTAssertNil(result.values)
        XCTAssertEqual(result.diagnosticFields["conversation_shell_present"], .null)
        XCTAssertNil(result.diagnosticFields["document_token"])
        XCTAssertNil(result.diagnosticFields["error_message"])
    }

    func testIncidentHealthProbeTimeoutRejectsLateCallback() async {
        var callbackCount = 0
        var finalResult: ChatGPTIncidentHealthProbeResult?
        let harness = ChatGPTAttentionBridgeHarness(
            incidentHealthProbeEvaluator: { _, _ in
                try await Task.sleep(nanoseconds: 80_000_000)
                return Self.healthProbePayload()
            },
            incidentHealthProbeTimeout: 0.01
        )
        harness.accept(false, token: tokenA)
        harness.bridge.captureIncidentHealthSnapshot(
            for: harness.webView,
            contextIsCurrent: { true }
        ) { result in
            callbackCount += 1
            finalResult = result
        }

        let timedOut = await waitUntil { finalResult != nil }
        XCTAssertTrue(timedOut)
        XCTAssertEqual(finalResult?.outcome, .timeout)
        try? await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(finalResult?.outcome, .timeout)
        XCTAssertNil(finalResult?.values)
    }

    func testIncidentHealthProbeDiscardsChangedDocumentAndWebViewIdentities() async {
        let documentGate = IncidentHealthProbeGate()
        let documentHarness = ChatGPTAttentionBridgeHarness(
            incidentHealthProbeEvaluator: { _, _ in try await documentGate.evaluate() }
        )
        documentHarness.accept(false, token: tokenA)
        var documentResult: ChatGPTIncidentHealthProbeResult?
        documentHarness.bridge.captureIncidentHealthSnapshot(
            for: documentHarness.webView,
            contextIsCurrent: { true }
        ) { documentResult = $0 }
        await documentGate.waitUntilStarted()
        documentHarness.bridge.handleRuntimeReplacement()
        documentHarness.accept(true, token: tokenB)
        documentGate.resolve(Self.healthProbePayload())
        let documentCompleted = await waitUntil { documentResult != nil }
        XCTAssertTrue(documentCompleted)
        XCTAssertEqual(documentResult?.outcome, .stale)
        XCTAssertNil(documentResult?.values)

        let webViewGate = IncidentHealthProbeGate()
        let webViewHarness = ChatGPTAttentionBridgeHarness(
            incidentHealthProbeEvaluator: { _, _ in try await webViewGate.evaluate() }
        )
        webViewHarness.accept(false, token: tokenA)
        var webViewResult: ChatGPTIncidentHealthProbeResult?
        webViewHarness.bridge.captureIncidentHealthSnapshot(
            for: webViewHarness.webView,
            contextIsCurrent: { true }
        ) { webViewResult = $0 }
        await webViewGate.waitUntilStarted()
        webViewHarness.bridge.attach(to: WKWebView())
        webViewGate.resolve(Self.healthProbePayload())
        let webViewCompleted = await waitUntil { webViewResult != nil }
        XCTAssertTrue(webViewCompleted)
        XCTAssertEqual(webViewResult?.outcome, .stale)
        XCTAssertNil(webViewResult?.values)
    }

    func testIncidentHealthProbeScriptReturnsOnlyBoundedContentFreeFields() {
        let script = ChatGPTAttentionBridge.incidentHealthProbeScript
        XCTAssertTrue(script.contains("document.readyState"))
        XCTAssertTrue(script.contains("document.visibilityState"))
        XCTAssertTrue(script.contains("conversation_shell_present"))
        XCTAssertTrue(script.contains("composer_present"))
        XCTAssertTrue(script.contains("loading_indicator_present"))
        XCTAssertTrue(script.contains("loading_indicator_visible"))
        XCTAssertTrue(script.contains("conversation_load_error_present"))
        for forbidden in [
            "innerText", "textContent", "outerHTML", "document.cookie", "localStorage",
            "sessionStorage", "location.", "setInterval", "setTimeout", "MutationObserver",
            "addEventListener", "window.onerror"
        ] {
            XCTAssertFalse(script.contains(forbidden), "Probe must not read \(forbidden)")
        }
    }

    func testIncidentPageAppProbeParsesOnlyBoundedMetadataAndDropsHostileFields() async {
        var evaluatedScript: String?
        let harness = ChatGPTAttentionBridgeHarness(
            incidentPageAppProbeEvaluator: { _, script, token in
                evaluatedScript = script
                return Self.pageAppPayload(token: token, hostile: true)
            }
        )
        harness.accept(false, token: tokenA)

        let result = await capturePageAppProbe(harness)

        XCTAssertEqual(result.outcome, .success)
        XCTAssertEqual(result.documentEpoch, 1)
        XCTAssertEqual(evaluatedScript, ChatGPTAttentionBridge.incidentPageAppProbeScript)
        let fields = try! XCTUnwrap(result.values).diagnosticFields
        XCTAssertEqual(fields["page_app_javascript_error_count"], .integer(1))
        XCTAssertEqual(fields["page_app_unhandled_rejection_count"], .integer(1))
        XCTAssertEqual(fields["page_app_resource_http_error_count"], .integer(1))
        XCTAssertEqual(fields["page_app_resource_timing_available"], .bool(true))
        XCTAssertEqual(fields["page_app_response_status_available"], .bool(false))
        XCTAssertEqual(fields["page_app_handled_fetch_xhr_failure_observable"], .bool(false))
        XCTAssertEqual(fields["page_app_capture_ring_capacity"], .integer(16))
        XCTAssertFalse(fields.keys.contains { key in
            ["token", "message", "stack", "body", "header", "cookie", "prompt", "answer", "url"]
                .contains { key.lowercased().contains($0) }
        })
        XCTAssertFalse(fields.values.contains(.string("SECRET_ERROR_TEXT")))
        XCTAssertFalse(ChatGPTAttentionBridge.scriptSource.contains("window.fetch ="))
        XCTAssertFalse(ChatGPTAttentionBridge.scriptSource.contains("XMLHttpRequest.prototype"))
        XCTAssertFalse(ChatGPTAttentionBridge.scriptSource.contains("window.WebSocket ="))
    }

    func testIncidentPageAppProbeRejectsOversizedAndMalformedRecorderPayloads() {
        var oversized = Self.pageAppPayload(token: tokenA)
        oversized["events"] = Array(repeating: Self.pageAppEvent(), count: 17)
        XCTAssertNil(ChatGPTIncidentPageAppProbeValues.parse(oversized, expectedDocumentToken: tokenA))

        var overflowingCounter = Self.pageAppPayload(token: tokenA)
        overflowingCounter["javascript_error_count"] = Int64.max
        XCTAssertNil(
            ChatGPTIncidentPageAppProbeValues.parse(
                overflowingCounter,
                expectedDocumentToken: tokenA
            )
        )

        var maliciousEnum = Self.pageAppPayload(token: tokenA)
        maliciousEnum["events"] = [[
            "kind": "javascript_error",
            "category": "Bearer private-token",
            "resource_type": "script",
            "http_status": NSNull(),
            "duration_bucket": NSNull(),
            "age_ms": 1
        ]]
        XCTAssertNil(ChatGPTIncidentPageAppProbeValues.parse(maliciousEnum, expectedDocumentToken: tokenA))

        let bounded = Self.pageAppPayload(token: tokenA, eventCount: 16)
        XCTAssertEqual(
            ChatGPTIncidentPageAppProbeValues.parse(bounded, expectedDocumentToken: tokenA)?.events.count,
            16
        )
    }

    func testIncidentPageAppProbeRejectsChangedDocumentAndWebViewIdentities() async {
        let documentGate = IncidentHealthProbeGate()
        let documentHarness = ChatGPTAttentionBridgeHarness(
            incidentPageAppProbeEvaluator: { _, _, _ in try await documentGate.evaluate() }
        )
        documentHarness.accept(false, token: tokenA)
        var documentResult: ChatGPTIncidentPageAppProbeResult?
        documentHarness.bridge.captureIncidentPageAppDiagnostics(
            for: documentHarness.webView,
            contextIsCurrent: { true }
        ) { documentResult = $0 }
        await documentGate.waitUntilStarted()
        documentHarness.bridge.handleRuntimeReplacement()
        documentHarness.accept(true, token: tokenB)
        documentGate.resolve(Self.pageAppPayload(token: tokenA))
        let documentCompleted = await waitUntil { documentResult != nil }
        XCTAssertTrue(documentCompleted)
        XCTAssertEqual(documentResult?.outcome, .stale)
        XCTAssertNil(documentResult?.values)

        let identityHarness = ChatGPTAttentionBridgeHarness(
            incidentPageAppProbeEvaluator: { _, _, _ in Self.pageAppPayload(token: self.tokenB) }
        )
        identityHarness.accept(false, token: tokenA)
        let mismatchedIdentityResult = await capturePageAppProbe(identityHarness)
        XCTAssertEqual(mismatchedIdentityResult.outcome, .stale)
        XCTAssertNil(mismatchedIdentityResult.values)

        let webViewGate = IncidentHealthProbeGate()
        let webViewHarness = ChatGPTAttentionBridgeHarness(
            incidentPageAppProbeEvaluator: { _, _, _ in try await webViewGate.evaluate() }
        )
        webViewHarness.accept(false, token: tokenA)
        var webViewResult: ChatGPTIncidentPageAppProbeResult?
        webViewHarness.bridge.captureIncidentPageAppDiagnostics(
            for: webViewHarness.webView,
            contextIsCurrent: { true }
        ) { webViewResult = $0 }
        await webViewGate.waitUntilStarted()
        webViewHarness.bridge.attach(to: WKWebView())
        webViewGate.resolve(Self.pageAppPayload(token: tokenA))
        let webViewCompleted = await waitUntil { webViewResult != nil }
        XCTAssertTrue(webViewCompleted)
        XCTAssertEqual(webViewResult?.outcome, .stale)
        XCTAssertNil(webViewResult?.values)
    }

    func testInstalledPageAppRecorderUsesPassiveBoundedSignalsOnly() {
        let source = ChatGPTAttentionBridge.scriptSource
        for expected in [
            "unhandledrejection", "resource", "responseStatus", "visibilitychange",
            "pageshow", "pagehide", "online", "offline", "PAGE_EVENT_LIMIT",
            "PAGE_COUNTER_LIMIT", "page_show_bfcache", "pageEvents.length = 0",
            "__floatTabsPageAppDiagnosticSnapshotV1"
        ] {
            XCTAssertTrue(source.contains(expected), "Missing passive signal \(expected)")
        }
        for forbidden in [
            "event.message", "event.error", "event.reason", "entry.name", "document.cookie",
            "localStorage", "sessionStorage", "XMLHttpRequest.prototype", "window.fetch =",
            "window.WebSocket =", "history.pushState ="
        ] {
            XCTAssertFalse(source.contains(forbidden), "Recorder must not inspect or replace \(forbidden)")
        }
        XCTAssertTrue(source.contains("pageEvents.length === PAGE_EVENT_LIMIT"))
        XCTAssertTrue(source.contains("pageDroppedEvents < PAGE_COUNTER_LIMIT"))
        XCTAssertTrue(source.contains("pageCounts[key] < PAGE_COUNTER_LIMIT"))
        XCTAssertEqual(
            source.components(separatedBy: "new MutationObserver").count - 1,
            2,
            "Workload measurement must reuse the existing attention and boot observers"
        )
        XCTAssertFalse(source.contains("setInterval"))
    }

    func testReleaseWorkloadSnapshotContractIsContentFreeAndLongRunBounded() {
        let source = ChatGPTAttentionBridge.scriptSource
        for expected in [
            "__floatTabsAttentionBenchmarkSnapshotV1",
            "mutation_callback_batch_count",
            "detector_schedule_count",
            "detector_evaluate_count",
            "detector_evaluate_total_ms",
            "detector_evaluate_max_ms",
            "response_identity_resolution_count",
            "response_identity_resolution_total_ms",
            "response_identity_resolution_max_ms"
        ] {
            XCTAssertTrue(source.contains(expected), "Missing workload field \(expected)")
        }
        XCTAssertTrue(source.contains("Number.MAX_SAFE_INTEGER"))
        XCTAssertTrue(source.contains("BENCHMARK_TOTAL_DURATION_LIMIT_MS"))
        XCTAssertFalse(source.contains("document.body.innerText"))
        XCTAssertFalse(source.contains("document.documentElement.innerText"))
    }

    func testInstalledPageAppRecorderKeepsRingAndCountersBounded() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        globalThis.window = globalThis;
        window.top = window;
        globalThis.location = { hostname: "chatgpt.com" };
        window.webkit = { messageHandlers: { floatTabsChatGPTAttention: { postMessage: function() {} } } };
        window.crypto = { randomUUID: function() { return "page-app-test-token-0001"; } };
        globalThis.crypto = window.crypto;
        globalThis.document = {
          documentElement: {},
          visibilityState: "visible",
          addEventListener: function() {},
          querySelector: function() { return null; }
        };
        window.__listeners = {};
        window.addEventListener = function(name, listener) { window.__listeners[name] = listener; };
        globalThis.MutationObserver = class { constructor() {} observe() {} disconnect() {} };
        globalThis.PerformanceObserver = undefined;
        globalThis.PerformanceResourceTiming = undefined;
        globalThis.performance = { now: function() { return 123; } };
        """)
        context.evaluateScript(ChatGPTAttentionBridge.scriptSource)
        XCTAssertNil(context.exception, context.exception?.toString() ?? "JavaScript source did not parse")

        context.evaluateScript("""
        for (let i = 0; i < 260; i++) { window.__listeners.error({ target: window }); }
        window.__listeners.error({ target: { localName: "script" } });
        window.__listeners.unhandledrejection({ reason: "DO_NOT_READ_THIS" });
        """)
        XCTAssertNil(context.exception, context.exception?.toString() ?? "Recorder produced a JavaScript exception")
        let payload = try XCTUnwrap(
            context.evaluateScript(ChatGPTAttentionBridge.incidentPageAppProbeScript)?.toDictionary()
        )
        let values = try XCTUnwrap(
            ChatGPTIncidentPageAppProbeValues.parse(
                payload,
                expectedDocumentToken: "page-app-test-token-0001"
            )
        )
        XCTAssertEqual(values.events.count, 16)
        XCTAssertEqual(values.droppedEvents, 246)
        XCTAssertEqual(values.javascriptErrorCount, 260)
        XCTAssertEqual(values.resourceLoadFailureCount, 1)
        XCTAssertEqual(values.unhandledRejectionCount, 1)
        XCTAssertFalse(values.resourceTimingAvailable)
        XCTAssertFalse(values.responseStatusAvailable)
        XCTAssertFalse(values.diagnosticFields.values.contains(.string("DO_NOT_READ_THIS")))
    }

#if DEBUG
    func testLargeDOMDetectorBenchmarkUsesDeterministicContentFreeFixture() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        globalThis.window = globalThis;
        window.top = window;
        globalThis.location = { hostname: "chatgpt.com" };
        window.webkit = { messageHandlers: { floatTabsChatGPTAttention: { postMessage: function() {} } } };
        window.crypto = { randomUUID: function() { return "large-dom-benchmark-token-0001"; } };
        globalThis.crypto = window.crypto;
        window.__fixtureEnabled = false;
        window.__layoutChecks = 0;
        window.__clock = 0;
        const makeControl = (label) => ({
          isConnected: true,
          disabled: false,
          getClientRects: function() { window.__layoutChecks += 1; window.__clock += 0.1; return [1]; },
          getAttribute: function(name) {
            if (name === "aria-label") { return label; }
            return null;
          },
          matches: function(selector) { return selector === 'button,[role="button"]'; },
          querySelectorAll: function() { return []; },
          querySelector: function() { return null; },
          closest: function() { return null; }
        });
        window.__irrelevantControls = [];
        for (let index = 0; index < 4000; index += 1) {
          window.__irrelevantControls.push(makeControl(null));
        }
        window.__semanticStopControl = makeControl("Stop generating");
        globalThis.document = {
          documentElement: {},
          visibilityState: "visible",
          addEventListener: function() {},
          querySelector: function() { return null; },
          querySelectorAll: function(selector) {
            if (selector.includes("stop-button")) { return []; }
            if (!window.__fixtureEnabled) { return []; }
            if (selector === 'button,[role="button"]') {
              return window.__irrelevantControls.concat([window.__semanticStopControl]);
            }
            if (selector.includes("aria-label") && selector.includes("title")) {
              return [window.__semanticStopControl];
            }
            return [];
          }
        };
        window.addEventListener = function() {};
        window.getComputedStyle = function() { return { display: "block", visibility: "visible" }; };
        globalThis.MutationObserver = class {
          constructor(callback) { window.__mutationCallback = callback; }
          observe() {}
          disconnect() {}
        };
        globalThis.PerformanceObserver = undefined;
        globalThis.performance = { now: function() { return window.__clock; } };
        window.__timeouts = [];
        globalThis.setTimeout = function(callback) {
          window.__timeouts.push(callback);
          return window.__timeouts.length;
        };
        window.__flushTimeouts = function() {
          while (window.__timeouts.length) { window.__timeouts.shift()(); }
        };
        globalThis.Date = { now: function() { return 1000; } };
        """)
        context.evaluateScript(ChatGPTAttentionBridge.scriptSource)
        XCTAssertNil(context.exception, context.exception?.toString() ?? "Benchmark script did not parse")

        context.evaluateScript("window.__mutationCallback(); window.__flushTimeouts();")
        XCTAssertNil(context.exception, context.exception?.toString() ?? "Baseline detector run failed")
        context.evaluateScript("globalThis.__floatTabsAttentionBenchmarkConfigureV1(true, true);")
        context.evaluateScript("window.__fixtureEnabled = true; window.__mutationCallback(); window.__flushTimeouts();")
        XCTAssertNil(context.exception, context.exception?.toString() ?? "Large-DOM detector run failed")

        let snapshot = try XCTUnwrap(
            context.evaluateScript(ChatGPTAttentionBridge.benchmarkSnapshotScript)?.toDictionary()
        )
        let layoutChecks = context.evaluateScript("window.__layoutChecks")?.toInt32() ?? -1
        print("LARGE_DOM_BENCHMARK \(snapshot) layout_checks=\(layoutChecks)")
        XCTAssertEqual(snapshot["detector_evaluate_count"] as? Int, 1)
        XCTAssertGreaterThan(snapshot["detector_evaluate_max_ms"] as? Double ?? 0, 0)
        XCTAssertLessThan(layoutChecks, 100)
    }

    func testBenchmarkScriptCountsOnlyWhenEnabledAndReturnsContentFreeBoundedFields() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        globalThis.window = globalThis;
        window.top = window;
        globalThis.location = { hostname: "chatgpt.com" };
        window.webkit = { messageHandlers: { floatTabsChatGPTAttention: { postMessage: function() {} } } };
        window.crypto = { randomUUID: function() { return "benchmark-test-token-0001"; } };
        globalThis.crypto = window.crypto;
        globalThis.document = {
          documentElement: {},
          visibilityState: "visible",
          addEventListener: function() {},
          querySelector: function() { return null; },
          querySelectorAll: function(selector) {
            return window.generating && selector.includes("stop-button")
              ? [window.stopButton] : [];
          }
        };
        window.__windowListeners = {};
        window.addEventListener = function(name, listener) {
          window.__windowListeners[name] = listener;
        };
        window.stopButton = {
          isConnected: true,
          disabled: false,
          hidden: false,
          getClientRects: function() { return [1]; },
          getAttribute: function() { return null; },
          matches: function() { return false; },
          querySelectorAll: function() { return []; },
          querySelector: function() { return null; },
          closest: function() { return null; }
        };
        window.generating = false;
        window.getComputedStyle = function() { return { display: "block", visibility: "visible" }; };
        window.__mutationCallbacks = [];
        globalThis.MutationObserver = class {
          constructor(callback) { window.__mutationCallbacks.push(callback); }
          observe() {}
          disconnect() {}
        };
        globalThis.PerformanceObserver = undefined;
        globalThis.PerformanceResourceTiming = undefined;
        window.__timeouts = [];
        globalThis.setTimeout = function(callback) {
          window.__timeouts.push(callback);
          return window.__timeouts.length;
        };
        window.__flushTimeouts = function() {
          while (window.__timeouts.length) { window.__timeouts.shift()(); }
        };
        window.__performanceNowCalls = 0;
        globalThis.performance = {
          now: function() { window.__performanceNowCalls += 1; return window.__performanceNowCalls; }
        };
        """)
        context.evaluateScript(ChatGPTAttentionBridge.scriptSource)
        XCTAssertNil(context.exception, context.exception?.toString() ?? "Benchmark script did not parse")

        context.evaluateScript("""
        window.__mutationCallbacks[0]();
        window.__flushTimeouts();
        """)
        XCTAssertNil(context.exception, context.exception?.toString() ?? "Disabled detector run failed")
        XCTAssertEqual(context.evaluateScript("window.__performanceNowCalls")?.toInt32(), 0)
        let disabled = try XCTUnwrap(
            context.evaluateScript(ChatGPTAttentionBridge.benchmarkSnapshotScript)?.toDictionary()
        )
        XCTAssertEqual(disabled["enabled"] as? Bool, false)
        XCTAssertEqual(disabled["detector_evaluate_count"] as? Int, 0)

        context.evaluateScript("""
        globalThis.__floatTabsAttentionBenchmarkConfigureV1(true, true);
        window.generating = true;
        window.__mutationCallbacks[0]();
        window.__flushTimeouts();
        window.generating = false;
        window.__mutationCallbacks[0]();
        window.__flushTimeouts();
        """)
        XCTAssertNil(context.exception, context.exception?.toString() ?? "Enabled detector run failed")
        let enabled = try XCTUnwrap(
            context.evaluateScript(ChatGPTAttentionBridge.benchmarkSnapshotScript)?.toDictionary()
        )
        XCTAssertEqual(enabled["enabled"] as? Bool, true)
        XCTAssertEqual(enabled["mutation_callback_batch_count"] as? Int, 2)
        XCTAssertEqual(enabled["detector_schedule_count"] as? Int, 2)
        XCTAssertEqual(enabled["detector_evaluate_count"] as? Int, 2)
        XCTAssertEqual(enabled["response_identity_resolution_count"] as? Int, 1)
        XCTAssertGreaterThan(context.evaluateScript("window.__performanceNowCalls")?.toInt32() ?? 0, 0)

        let rendered = String(describing: enabled)
        XCTAssertFalse(rendered.contains("prompt"))
        XCTAssertFalse(rendered.contains("response body"))
        XCTAssertTrue(rendered.contains("benchmark-test-token-0001"))
    }
#endif

#if DEBUG
    func testBenchmarkCounterHelpersSaturateAndNativeCountersStayInertWhenDisabled() {
        var counters = ChatGPTAttentionBenchmarkCounters()
        counters.recordLivenessProbe(durationMilliseconds: 12, isConfirmation: false)
        counters.recordLivenessFailure()
        XCTAssertEqual(counters.fields["liveness_probe_count"] as? Int64, 0)
        XCTAssertEqual(counters.fields["liveness_failure_count"] as? Int64, 0)

        counters.setEnabled(true)
        counters.recordLivenessProbe(durationMilliseconds: 12, isConfirmation: true)
        counters.recordLivenessProbe(durationMilliseconds: .infinity, isConfirmation: false)
        counters.recordLivenessFailure()
        counters.recordRecoveredCompletion()
        counters.recordLivenessTimeout()
        counters.recordLivenessSuppression()
        counters.recordCurrentDocumentResyncTimeout()
        counters.recordCurrentDocumentResyncSuppression()
        XCTAssertEqual(counters.fields["liveness_probe_count"] as? Int64, 2)
        XCTAssertEqual(counters.fields["confirmation_probe_count"] as? Int64, 1)
        XCTAssertEqual(counters.fields["liveness_probe_total_ms"] as? Double, 12)
        XCTAssertEqual(counters.fields["liveness_probe_max_ms"] as? Double, 12)
        XCTAssertEqual(counters.fields["liveness_failure_count"] as? Int64, 1)
        XCTAssertEqual(counters.fields["recovered_completion_count"] as? Int64, 1)
        XCTAssertEqual(counters.fields["liveness_timeout_count"] as? Int64, 1)
        XCTAssertEqual(counters.fields["liveness_suppression_count"] as? Int64, 1)
        XCTAssertEqual(counters.fields["current_document_resync_timeout_count"] as? Int64, 1)
        XCTAssertEqual(counters.fields["current_document_resync_suppression_count"] as? Int64, 1)
        counters.resetValues()
        XCTAssertEqual(
            counters.fields["liveness_timeout_count"] as? Int64,
            1,
            "bridge-lifetime health evidence must survive a document measurement reset"
        )
        XCTAssertEqual(
            ChatGPTAttentionBenchmarkCounters.saturatedIncrement(.max),
            ChatGPTAttentionBenchmarkCounters.maximumCounter
        )
        XCTAssertEqual(ChatGPTAttentionBenchmarkCounters.boundedDuration(-10), 0)
        XCTAssertEqual(
            ChatGPTAttentionBenchmarkCounters.boundedDuration(.infinity),
            0
        )
        XCTAssertEqual(
            ChatGPTAttentionBenchmarkCounters.boundedDuration(.greatestFiniteMagnitude),
            ChatGPTAttentionBenchmarkCounters.maximumDurationMilliseconds
        )
        XCTAssertEqual(
            Set(counters.fields.keys),
            [
                "liveness_probe_count", "confirmation_probe_count",
                "liveness_probe_total_ms", "liveness_probe_max_ms",
                "liveness_failure_count", "recovered_completion_count",
                "liveness_timeout_count", "liveness_suppression_count",
                "current_document_resync_timeout_count",
                "current_document_resync_suppression_count"
            ]
        )
    }

    func testPhysicalRuntimeReplacementDiscardsTimedOutLivenessMarkersAndLateCallbacksAreHarmless() async throws {
        let probes = LivenessProbeGate()
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in observations.append(observation) },
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            },
            livenessProbeTimeout: 0.01
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        let firstTimedOutCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await probes.waitForCall(1)
        await firstTimedOutCycle.value

        let secondTimedOutCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await probes.waitForCall(2)
        await secondTimedOutCycle.value

        // Ordinary document replacement is intentionally not enough to free
        // these physical callback markers. The process replacement seam must
        // establish the new physical epoch and discard them.
        bridge.handleWebContentProcessReplacement()
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenB,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false],
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false]
        ])

        await bridge.debugRunLivenessCycle()
        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted, .generationFinished]
        )

        // The two callbacks belong to the old physical epoch. They must be
        // harmless after the new epoch has already completed a recovery.
        probes.resumeSuspended(nil)
        probes.resumeSuspended(nil)
        await Task.yield()
        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted, .generationFinished]
        )
    }

    func testPhysicalRuntimeReplacementResetsCurrentDocumentResyncBudgetWithoutAcceptingLateCallbacks() async throws {
        let gate = CurrentDocumentResyncBudgetGate()
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in observations.append(observation) },
            currentDocumentResyncEvaluator: { _, _ in try await gate.evaluate() },
            currentDocumentResyncTimeout: 1
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        let supportedURL = URL(string: "https://chatgpt.com/c/current")!

        bridge.handleRuntimeReplacement(committedURL: supportedURL)
        await gate.waitUntilStarted(1)
        bridge.handleRuntimeReplacement(committedURL: supportedURL)
        await gate.waitUntilStarted(2)

        // The same physical WebContent runtime remains bounded: the third
        // semantic replacement cannot manufacture a third WebKit request.
        bridge.handleRuntimeReplacement(committedURL: supportedURL)
        XCTAssertEqual(gate.callCount, 2)

        bridge.handleWebContentProcessReplacement()
        bridge.handleRuntimeReplacement(committedURL: supportedURL)
        await gate.waitUntilStarted(3)
        XCTAssertEqual(gate.callCount, 3)

        gate.resolveAll([
            "version": 1,
            "kind": ChatGPTBridgePayload.baselineKind,
            "token": tokenA!,
            "generating": true
        ] as [String: Any])
        let admitted = await waitUntil {
            observations == [.generationStarted]
        }
        XCTAssertTrue(admitted)
    }

    func testStandardDiagnosticsExposeBoundedLivenessBudgetCountersWithoutPageContent() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let probes = LivenessProbeGate()
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, _ in },
            diagnostics: diagnostics,
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            },
            benchmarkProbeEvaluator: { _, _ in
                Self.longTermWorkloadPayload(
                    token: self.tokenA,
                    enabled: Self.benchmarkMeasurementEnabledForTest
                )
            },
            livenessProbeTimeout: 0.01
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        for expectedCallCount in 1...2 {
            let timedOutCycle = Task { @MainActor in
                await bridge.debugRunLivenessCycle()
            }
            await probes.waitForCall(expectedCallCount)
            await timedOutCycle.value
        }
        // Two timed-out markers consume the physical budget; the next cycle
        // is suppressed and increments the bounded counter without a debug-only
        // event being required for Standard visibility.
        await bridge.debugRunLivenessCycle()

        let fields = await bridge.captureLongTermWorkloadDiagnosticFields(
            for: webView,
            runtimeIdentity: WebRuntimeDiagnosticIdentity(
                runtimeGeneration: 1,
                webViewInstanceID: UUID()
            ),
            navigationGeneration: 1,
            contextIsCurrent: { true }
        )
        XCTAssertEqual(
            fields["attention_liveness_timeout_count"],
            RuntimeDiagnosticValue.integer(2)
        )
        XCTAssertEqual(
            fields["attention_liveness_suppression_count"],
            RuntimeDiagnosticValue.integer(1)
        )

        diagnostics.record(
            event: "diagnostics.performance_checkpoint",
            level: .notice,
            subsystem: "diagnostics",
            fields: fields
        )
        let checkpoint = try XCTUnwrap(writer.events.last)
        XCTAssertEqual(checkpoint.event, "diagnostics.performance_checkpoint")
        XCTAssertEqual(
            checkpoint.fields["attention_liveness_timeout_count"],
            RuntimeDiagnosticValue.integer(2)
        )
        XCTAssertEqual(
            checkpoint.fields["attention_liveness_suppression_count"],
            RuntimeDiagnosticValue.integer(1)
        )
        XCTAssertTrue(writer.events.allSatisfy { $0.level != .debug })
        XCTAssertFalse(String(describing: checkpoint.fields).contains(tokenA))
    }

    func testStandardDiagnosticsExposeBoundedResyncBudgetCountersAcrossPhysicalReplacement() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let gate = CurrentDocumentResyncBudgetGate()
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, _ in },
            diagnostics: diagnostics,
            benchmarkProbeEvaluator: { _, _ in
                Self.longTermWorkloadPayload(
                    token: self.tokenA,
                    enabled: Self.benchmarkMeasurementEnabledForTest
                )
            },
            livenessProbeTimeout: 0.01,
            currentDocumentResyncEvaluator: { _, _ in try await gate.evaluate() },
            currentDocumentResyncTimeout: 0.01
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        let supportedURL = URL(string: "https://chatgpt.com/c/current")!

        bridge.handleRuntimeReplacement(committedURL: supportedURL)
        await gate.waitUntilStarted(1)
        try await Task.sleep(nanoseconds: 30_000_000)

        bridge.handleRuntimeReplacement(committedURL: supportedURL)
        await gate.waitUntilStarted(2)
        bridge.handleRuntimeReplacement(committedURL: supportedURL)
        XCTAssertEqual(gate.callCount, 2)

        bridge.handleWebContentProcessReplacement()
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: false
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        let fields = await bridge.captureLongTermWorkloadDiagnosticFields(
            for: webView,
            runtimeIdentity: WebRuntimeDiagnosticIdentity(
                runtimeGeneration: 1,
                webViewInstanceID: UUID()
            ),
            navigationGeneration: 1,
            contextIsCurrent: { true }
        )

        XCTAssertEqual(
            fields["attention_resync_timeout_count"],
            RuntimeDiagnosticValue.integer(1)
        )
        XCTAssertEqual(
            fields["attention_resync_suppression_count"],
            RuntimeDiagnosticValue.integer(1)
        )
        diagnostics.record(
            event: "diagnostics.performance_checkpoint",
            level: .notice,
            subsystem: "diagnostics",
            fields: fields
        )
        let checkpoint = try XCTUnwrap(writer.events.last)
        XCTAssertEqual(
            checkpoint.fields["attention_resync_timeout_count"],
            RuntimeDiagnosticValue.integer(1)
        )
        XCTAssertEqual(
            checkpoint.fields["attention_resync_suppression_count"],
            RuntimeDiagnosticValue.integer(1)
        )
        XCTAssertTrue(writer.events.allSatisfy { $0.level != .debug })

        gate.resolveAll([
            "version": 1,
            "kind": ChatGPTBridgePayload.baselineKind,
            "token": tokenA!,
            "generating": false
        ] as [String: Any])
        await Task.yield()
    }

    func testBenchmarkMeasurementEnableResetSnapshotAndLivenessCounters() async {
        var measurementEnabled = false
        var javascriptCounters = Self.benchmarkCounterPayload
        let harness = ChatGPTAttentionBridgeHarness(
            probeValues: [
                Self.probePayload(token: tokenA, generating: false),
                Self.probePayload(token: tokenA, generating: false),
            ],
            benchmarkProbeEvaluator: { _, script in
                if script.contains("BenchmarkConfigureV1") {
                    let reset = script.hasSuffix(", true)")
                    if reset { javascriptCounters = Self.zeroBenchmarkCounterPayload }
                    if script.contains("(true,") { measurementEnabled = true }
                    if script.contains("(false,") { measurementEnabled = false }
                    return [
                        "version": 1,
                        "token": self.tokenA!,
                        "enabled": measurementEnabled,
                    ] as [String: Any]
                }
                var payload = Self.benchmarkDocumentPayload(
                    token: self.tokenA!,
                    enabled: measurementEnabled
                )
                payload.merge(javascriptCounters) { _, new in new }
                return payload
            }
        )
        harness.accept(false, token: tokenA)
        let runtimeIdentity = WebRuntimeDiagnosticIdentity(
            runtimeGeneration: 7,
            webViewInstanceID: UUID()
        )
        let enabled = await harness.bridge.configureBenchmarkMeasurement(
            enabled: true,
            reset: true,
            for: harness.webView,
            runtimeIdentity: runtimeIdentity,
            navigationGeneration: 12,
            contextIsCurrent: { true }
        )
        XCTAssertEqual(enabled["status"] as? String, "ok")
        XCTAssertEqual(enabled["measurement_enabled"] as? Bool, true)
        XCTAssertEqual(enabled["runtime_generation"] as? UInt64, 7)
        XCTAssertEqual(enabled["navigation_generation"] as? Int, 12)
        XCTAssertNil(enabled["document_token"])

        harness.accept(true, token: tokenA)
        await harness.bridge.debugRunLivenessCycle()
        let snapshot = await harness.bridge.captureBenchmarkSnapshot(
            for: harness.webView,
            runtimeIdentity: runtimeIdentity,
            navigationGeneration: 12,
            contextIsCurrent: { true }
        )
        XCTAssertEqual(snapshot["status"] as? String, "ok")
        XCTAssertEqual(snapshot["measurement_enabled"] as? Bool, true)
        XCTAssertEqual(snapshot["liveness_probe_count"] as? Int64, 2)
        XCTAssertEqual(snapshot["confirmation_probe_count"] as? Int64, 1)
        XCTAssertEqual(snapshot["recovered_completion_count"] as? Int64, 1)
        XCTAssertEqual(snapshot["document_epoch"] as? UInt64, 1)
        XCTAssertNil(snapshot["token"])
        XCTAssertNil(snapshot["document_token"])
        XCTAssertFalse(String(describing: snapshot).contains(tokenA))
        XCTAssertEqual(snapshot["mutation_callback_batch_count"] as? Int64, 0)

        let reset = await harness.bridge.configureBenchmarkMeasurement(
            enabled: true,
            reset: true,
            for: harness.webView,
            runtimeIdentity: runtimeIdentity,
            navigationGeneration: 12,
            contextIsCurrent: { true }
        )
        XCTAssertEqual(reset["status"] as? String, "ok")
        let resetSnapshot = await harness.bridge.captureBenchmarkSnapshot(
            for: harness.webView,
            runtimeIdentity: runtimeIdentity,
            navigationGeneration: 12,
            contextIsCurrent: { true }
        )
        XCTAssertEqual(resetSnapshot["liveness_probe_count"] as? Int64, 0)
        XCTAssertEqual(resetSnapshot["recovered_completion_count"] as? Int64, 0)
    }

    func testBenchmarkSnapshotRejectsNavigationDocumentAndWebViewReplacement() async {
        let documentGate = IncidentHealthProbeGate()
        let documentHarness = ChatGPTAttentionBridgeHarness(
            benchmarkProbeEvaluator: { _, _ in try await documentGate.evaluate() }
        )
        documentHarness.accept(false, token: tokenA)
        let runtimeIdentity = WebRuntimeDiagnosticIdentity(
            runtimeGeneration: 1,
            webViewInstanceID: UUID()
        )
        let documentTask = Task {
            await documentHarness.bridge.captureBenchmarkSnapshot(
                for: documentHarness.webView,
                runtimeIdentity: runtimeIdentity,
                navigationGeneration: 1,
                contextIsCurrent: { true }
            )
        }
        await documentGate.waitUntilStarted()
        documentHarness.bridge.handleRuntimeReplacement()
        documentHarness.accept(false, token: tokenB)
        documentGate.resolve(Self.benchmarkDocumentPayload(token: tokenA, enabled: false))
        let documentResult = await documentTask.value
        XCTAssertEqual(documentResult["status"] as? String, "stale")
        XCTAssertNil(documentResult["generating"])
        XCTAssertNil(documentResult["token"])

        let navigationGate = IncidentHealthProbeGate()
        let navigationHarness = ChatGPTAttentionBridgeHarness(
            benchmarkProbeEvaluator: { _, _ in try await navigationGate.evaluate() }
        )
        navigationHarness.accept(false, token: tokenA)
        var navigationIsCurrent = true
        let navigationTask = Task {
            await navigationHarness.bridge.captureBenchmarkSnapshot(
                for: navigationHarness.webView,
                runtimeIdentity: runtimeIdentity,
                navigationGeneration: 4,
                contextIsCurrent: { navigationIsCurrent }
            )
        }
        await navigationGate.waitUntilStarted()
        navigationIsCurrent = false
        navigationGate.resolve(Self.benchmarkDocumentPayload(token: tokenA, enabled: false))
        let navigationResult = await navigationTask.value
        XCTAssertEqual(navigationResult["status"] as? String, "stale")
        XCTAssertNil(navigationResult["generating"])

        let webViewGate = IncidentHealthProbeGate()
        let webViewHarness = ChatGPTAttentionBridgeHarness(
            benchmarkProbeEvaluator: { _, _ in try await webViewGate.evaluate() }
        )
        webViewHarness.accept(false, token: tokenA)
        let webViewTask = Task {
            await webViewHarness.bridge.captureBenchmarkSnapshot(
                for: webViewHarness.webView,
                runtimeIdentity: runtimeIdentity,
                navigationGeneration: 1,
                contextIsCurrent: { true }
            )
        }
        await webViewGate.waitUntilStarted()
        webViewHarness.bridge.attach(to: WKWebView())
        webViewGate.resolve(Self.benchmarkDocumentPayload(token: tokenA, enabled: false))
        let webViewResult = await webViewTask.value
        XCTAssertEqual(webViewResult["status"] as? String, "stale")
        XCTAssertNil(webViewResult["generating"])
    }
#endif

    func testLongTermWorkloadTimeoutCompletesOnceAndBoundsLateCallbackBudget() async {
        let gate = IncidentHealthProbeGate()
        var evaluationCount = 0
        var lateEvaluationReturned = false
        let harness = ChatGPTAttentionBridgeHarness(
            benchmarkProbeEvaluator: { _, _ in
                evaluationCount += 1
                if evaluationCount == 1 {
                    let value = try await gate.evaluate()
                    lateEvaluationReturned = true
                    return value
                }
                return Self.longTermWorkloadPayload(
                    token: self.tokenA,
                    enabled: Self.benchmarkMeasurementEnabledForTest
                )
            },
            longTermWorkloadTimeout: 0.02
        )
        harness.accept(false, token: tokenA)
        let runtimeIdentity = WebRuntimeDiagnosticIdentity(
            runtimeGeneration: 1,
            webViewInstanceID: UUID()
        )

        let firstTask = Task {
            await harness.bridge.captureLongTermWorkloadDiagnosticFields(
                for: harness.webView,
                runtimeIdentity: runtimeIdentity,
                navigationGeneration: 1,
                contextIsCurrent: { true }
            )
        }
        await gate.waitUntilStarted()
        let timedOut = await firstTask.value
        XCTAssertEqual(
            timedOut["attention_workload_probe_status"],
            RuntimeDiagnosticValue.string("timeout")
        )
        XCTAssertEqual(
            timedOut["attention_workload_probe_reason"],
            RuntimeDiagnosticValue.string("deadline_exceeded")
        )
        XCTAssertEqual(evaluationCount, 1)

        for _ in 0..<4 {
            let suppressed = await harness.bridge.captureLongTermWorkloadDiagnosticFields(
                for: harness.webView,
                runtimeIdentity: runtimeIdentity,
                navigationGeneration: 1,
                contextIsCurrent: { true }
            )
            XCTAssertEqual(
                suppressed["attention_workload_probe_status"],
                RuntimeDiagnosticValue.string("suppressed")
            )
            XCTAssertEqual(
                suppressed["attention_workload_probe_reason"],
                RuntimeDiagnosticValue.string("pending_request_budget")
            )
        }
        XCTAssertEqual(evaluationCount, 1)

        gate.resolve(Self.longTermWorkloadPayload(
            token: tokenA,
            enabled: Self.benchmarkMeasurementEnabledForTest
        ))
        let lateEvaluationFinished = await waitUntil { lateEvaluationReturned }
        XCTAssertTrue(lateEvaluationFinished)

        var lateResult: [String: RuntimeDiagnosticValue] = [:]
        for _ in 0..<100 {
            lateResult = await harness.bridge.captureLongTermWorkloadDiagnosticFields(
                for: harness.webView,
                runtimeIdentity: runtimeIdentity,
                navigationGeneration: 1,
                contextIsCurrent: { true }
            )
            if lateResult["attention_workload_probe_status"] == RuntimeDiagnosticValue.string("ok") {
                break
            }
            await Task.yield()
        }
        XCTAssertEqual(
            lateResult["attention_workload_probe_status"],
            RuntimeDiagnosticValue.string("ok")
        )
        XCTAssertEqual(evaluationCount, 2)
    }

    func testLongTermWorkloadLateRuntimeDocumentCompletionRemainsStale() async {
        let gate = IncidentHealthProbeGate()
        let harness = ChatGPTAttentionBridgeHarness(
            benchmarkProbeEvaluator: { _, _ in try await gate.evaluate() },
            longTermWorkloadTimeout: 0.5
        )
        harness.accept(false, token: tokenA)
        let runtimeIdentity = WebRuntimeDiagnosticIdentity(
            runtimeGeneration: 1,
            webViewInstanceID: UUID()
        )
        let task = Task {
            await harness.bridge.captureLongTermWorkloadDiagnosticFields(
                for: harness.webView,
                runtimeIdentity: runtimeIdentity,
                navigationGeneration: 1,
                contextIsCurrent: { true }
            )
        }
        await gate.waitUntilStarted()

        harness.bridge.handleRuntimeReplacement()
        harness.accept(false, token: tokenB)
        gate.resolve(Self.longTermWorkloadPayload(
            token: tokenA,
            enabled: Self.benchmarkMeasurementEnabledForTest
        ))

        let stale = await task.value
        XCTAssertEqual(
            stale["attention_workload_probe_status"],
            RuntimeDiagnosticValue.string("stale")
        )
        XCTAssertEqual(
            stale["attention_workload_probe_reason"],
            RuntimeDiagnosticValue.string("stale_context")
        )
    }

    func testLongTermCoordinatorSchedulesLaterCheckpointAfterTimedOutWorkloadSample() async {
        let suiteName = "FloatTabsTests.LongTermWorkloadTimeout.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.longTermPerformanceObservationEnabled = true

        let gate = IncidentHealthProbeGate()
        var evaluationCount = 0
        let harness = ChatGPTAttentionBridgeHarness(
            benchmarkProbeEvaluator: { _, _ in
                evaluationCount += 1
                return try await gate.evaluate()
            },
            longTermWorkloadTimeout: 0.02
        )
        harness.accept(false, token: tokenA)
        let runtimeIdentity = WebRuntimeDiagnosticIdentity(
            runtimeGeneration: 1,
            webViewInstanceID: UUID()
        )
        let sleeper = ChatGPTLongTermObservationSleeper()
        var sampleCount = 0
        let coordinator = LongTermPerformanceObservationCoordinator(
            preferencesStore: preferences,
            interval: 60,
            sleeper: { try await sleeper.sleep($0) },
            observe: { isCurrent, completion in
                sampleCount += 1
                Task { @MainActor in
                    _ = await harness.bridge.captureLongTermWorkloadDiagnosticFields(
                        for: harness.webView,
                        runtimeIdentity: runtimeIdentity,
                        navigationGeneration: 1,
                        contextIsCurrent: isCurrent
                    )
                    completion()
                }
            }
        )
        defer { coordinator.stop() }

        coordinator.start()
        await waitUntil { sleeper.pendingCount == 1 }
        sleeper.advanceNext()
        await waitUntil { sampleCount == 1 && !coordinator.isObservationInFlight }
        XCTAssertEqual(evaluationCount, 1)

        await waitUntil { sleeper.pendingCount == 1 }
        sleeper.advanceNext()
        await waitUntil { sampleCount == 2 && !coordinator.isObservationInFlight }
        XCTAssertEqual(evaluationCount, 1)

        gate.resolve(Self.longTermWorkloadPayload(
            token: tokenA,
            enabled: Self.benchmarkMeasurementEnabledForTest
        ))
    }

    private func captureHealthProbe(
        _ harness: ChatGPTAttentionBridgeHarness
    ) async -> ChatGPTIncidentHealthProbeResult {
        await withCheckedContinuation { continuation in
            harness.bridge.captureIncidentHealthSnapshot(
                for: harness.webView,
                contextIsCurrent: { true }
            ) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private func capturePageAppProbe(
        _ harness: ChatGPTAttentionBridgeHarness
    ) async -> ChatGPTIncidentPageAppProbeResult {
        await withCheckedContinuation { continuation in
            harness.bridge.captureIncidentPageAppDiagnostics(
                for: harness.webView,
                contextIsCurrent: { true }
            ) { result in
                continuation.resume(returning: result)
            }
        }
    }

    private static func pageAppEvent(index: Int = 0) -> [String: Any] {
        let samples: [[String: Any]] = [
            ["kind": "javascript_error", "category": "global_error", "resource_type": "none",
             "http_status": NSNull(), "duration_bucket": NSNull(), "age_ms": 10],
            ["kind": "unhandled_rejection", "category": "unhandled_rejection", "resource_type": "none",
             "http_status": NSNull(), "duration_bucket": NSNull(), "age_ms": 20],
            ["kind": "resource_http_error", "category": "http_error", "resource_type": "script",
             "http_status": 503, "duration_bucket": NSNull(), "age_ms": 30]
        ]
        return samples[index % samples.count]
    }

    private static func pageAppPayload(
        token: String,
        hostile: Bool = false,
        eventCount: Int = 3
    ) -> [String: Any] {
        var fields: [String: Any] = [
            "version": 1,
            "document_identity": token,
            "events": (0..<eventCount).map { pageAppEvent(index: $0) },
            "dropped_events": 0,
            "javascript_error_count": 1,
            "unhandled_rejection_count": 1,
            "resource_load_failure_count": 0,
            "resource_http_error_count": 1,
            "slow_resource_count": 1,
            "lifecycle_event_count": 0,
            "resource_timing_available": true,
            "response_status_available": false
        ]
        if hostile {
            fields["message"] = "SECRET_ERROR_TEXT"
            fields["stack"] = "Bearer private-token"
            fields["url"] = "https://example.invalid/private?token=secret"
            fields["headers"] = ["Authorization": "Bearer secret"]
            fields["requestBody"] = "private request"
            fields["prompt"] = "private prompt"
            fields["answer"] = "private answer"
            var firstEvent = pageAppEvent()
            firstEvent["message"] = "SECRET_ERROR_TEXT"
            firstEvent["stack"] = "private stack"
            firstEvent["request_url"] = "https://example.invalid/private"
            fields["events"] = [firstEvent] + (1..<eventCount).map { pageAppEvent(index: $0) }
        }
        return fields
    }

    private static func healthProbePayload() -> [String: Any] {
        [
            "version": 1,
            "document_ready_state": "complete",
            "visibility_state": "visible",
            "conversation_shell_present": true,
            "composer_present": true,
            "loading_indicator_present": false,
            "loading_indicator_visible": false,
            "conversation_load_error_present": false
        ]
    }

    private static var benchmarkMeasurementEnabledForTest: Bool {
#if DEBUG
        false
#else
        true
#endif
    }

    private static func longTermWorkloadPayload(
        token: String,
        enabled: Bool
    ) -> [String: Any] {
        [
            "version": 1,
            "token": token,
            "enabled": enabled,
            "visibility_state": "visible",
            "generating": false,
            "mutation_callback_batch_count": 0,
            "detector_schedule_count": 0,
            "detector_evaluate_count": 0,
            "detector_evaluate_total_ms": 0.0,
            "detector_evaluate_max_ms": 0.0,
            "response_identity_resolution_count": 0,
            "response_identity_resolution_total_ms": 0.0,
            "response_identity_resolution_max_ms": 0.0
        ]
    }

#if DEBUG
    private static let benchmarkCounterPayload: [String: Any] = [
        "mutation_callback_batch_count": 9,
        "detector_schedule_count": 8,
        "detector_evaluate_count": 7,
        "detector_evaluate_total_ms": 6.5,
        "detector_evaluate_max_ms": 2.5,
        "response_identity_resolution_count": 5,
        "response_identity_resolution_total_ms": 4.5,
        "response_identity_resolution_max_ms": 1.5,
    ]

    private static let zeroBenchmarkCounterPayload: [String: Any] = [
        "mutation_callback_batch_count": 0,
        "detector_schedule_count": 0,
        "detector_evaluate_count": 0,
        "detector_evaluate_total_ms": 0.0,
        "detector_evaluate_max_ms": 0.0,
        "response_identity_resolution_count": 0,
        "response_identity_resolution_total_ms": 0.0,
        "response_identity_resolution_max_ms": 0.0,
    ]

    private static func probePayload(token: String, generating: Bool) -> [String: Any] {
        [
            "version": 1,
            "kind": "baseline",
            "token": token,
            "generating": generating,
            "responseIdentity": NSNull(),
        ]
    }

    private static func benchmarkDocumentPayload(
        token: String,
        enabled: Bool
    ) -> [String: Any] {
        [
            "version": 1,
            "token": token,
            "enabled": enabled,
            "visibility_state": "visible",
            "generating": false,
        ].merging(zeroBenchmarkCounterPayload) { _, new in new }
    }
#endif

    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return predicate()
    }

    // MARK: - Shared host policy

    func testChatGPTHostIsAccepted() throws {
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedHost("chatgpt.com"))
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedChatGPTURL(URL(string: "https://chatgpt.com/c/abc")!))
    }

    func testChatGPTSubdomainHostsAreAccepted() throws {
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedHost("www.chatgpt.com"))
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedHost("new.chatgpt.com"))
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedChatGPTURL(URL(string: "https://new.chatgpt.com/")!))
    }

    func testLegacyOpenAIChatHostIsAccepted() throws {
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedHost("chat.openai.com"))
        XCTAssertTrue(ChatGPTSitePolicy.isSupportedChatGPTURL(URL(string: "https://chat.openai.com/c/1")!))
    }

    func testLookalikeAndUnrelatedHostsAreRejected() throws {
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost("evilchatgpt.com"))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost("chatgpt.com.evil.example"))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost("notchatgpt.com"))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost("openai.com"))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost("platform.openai.com"))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedHost(""))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedChatGPTURL(URL(string: "ftp://chatgpt.com/")!))
        XCTAssertFalse(ChatGPTSitePolicy.isSupportedChatGPTURL(URL(string: "about:blank")!))
    }

    func testChatGPTAutomaticMobileCompatibilityIdentityIsUnchanged() throws {
        let mobile = WebRenderingProfile.canonicalDefault.settingWebsiteMode(.mobile)

        XCTAssertEqual(
            SiteCompatibilityPolicy.runtimeRendering(
                for: mobile,
                navigationURL: URL(string: "https://chatgpt.com/")!
            ),
            mobile.settingBrowserIdentity(.macosSafari)
        )
        XCTAssertEqual(
            SiteCompatibilityPolicy.runtimeRendering(
                for: mobile,
                navigationURL: URL(string: "https://new.chatgpt.com/")!
            ),
            mobile.settingBrowserIdentity(.macosSafari)
        )
        XCTAssertEqual(
            SiteCompatibilityPolicy.runtimeRendering(
                for: mobile,
                navigationURL: URL(string: "https://chat.openai.com/")!
            ),
            mobile.settingBrowserIdentity(.macosSafari)
        )

        // Unrelated and lookalike hosts keep the user-selected identity.
        XCTAssertEqual(
            SiteCompatibilityPolicy.runtimeRendering(
                for: mobile,
                navigationURL: URL(string: "https://evilchatgpt.com/")!
            ),
            mobile
        )
        // The override remains Automatic+Mobile only.
        XCTAssertEqual(
            SiteCompatibilityPolicy.runtimeRendering(
                for: WebRenderingProfile.canonicalDefault,
                navigationURL: URL(string: "https://chatgpt.com/")!
            ),
            WebRenderingProfile.canonicalDefault
        )
    }

    // MARK: - Installation

    func testInstalledUserScriptInjectsAtDocumentStart() throws {
        let controller = WKUserContentController()
        let harness = ChatGPTAttentionBridgeHarness()

        harness.bridge.install(into: controller)

        XCTAssertEqual(controller.userScripts.count, 1)
        XCTAssertEqual(controller.userScripts.first?.injectionTime, .atDocumentStart)
    }

    func testInstalledUserScriptIsMainFrameOnly() throws {
        let controller = WKUserContentController()
        let harness = ChatGPTAttentionBridgeHarness()

        harness.bridge.install(into: controller)

        XCTAssertEqual(controller.userScripts.first?.isForMainFrameOnly, true)
    }

    func testInstalledUserScriptUsesNamedContentWorld() throws {
        // pageWorld/defaultClientWorld carry no name; a named client world is
        // distinct from both, and one instance is shared by script, handler,
        // and invalidation.
        XCTAssertEqual(
            ChatGPTAttentionBridge.contentWorld.name,
            ChatGPTAttentionBridge.contentWorldName
        )
        XCTAssertFalse(ChatGPTAttentionBridge.contentWorld.name?.isEmpty == true)
    }

    func testInstalledScriptExposesOnlyTheNarrowNamedWorldResyncEntry() throws {
        XCTAssertTrue(
            ChatGPTAttentionBridge.scriptSource.contains(
                "globalThis.__floatTabsAttentionResyncV1"
            )
        )
        XCTAssertEqual(
            ChatGPTAttentionBridge.contentWorld.name,
            ChatGPTAttentionBridge.contentWorldName
        )
    }

    func testInstalledScriptExposesReadOnlyLivenessProbeContract() throws {
        let source = ChatGPTAttentionBridge.scriptSource
        let marker = "globalThis.__floatTabsAttentionProbeV1 = () => {"
        let start = try XCTUnwrap(source.range(of: marker)?.lowerBound)
        let end = try XCTUnwrap(source.range(of: "};", range: start..<source.endIndex)?.upperBound)
        let probe = String(source[start..<end])

        XCTAssertTrue(probe.contains("version: 1"))
        XCTAssertTrue(probe.contains("kind: \"baseline\""))
        XCTAssertTrue(probe.contains("token: TOKEN"))
        XCTAssertTrue(probe.contains("generating: generating"))
        XCTAssertTrue(probe.contains("isGenerating()"))
        XCTAssertFalse(probe.contains("lastSent"))
        XCTAssertFalse(probe.contains("postMessage"))
        XCTAssertFalse(probe.contains("setTimeout"))
        XCTAssertFalse(probe.contains("MutationObserver"))
    }

    func testAttentionScriptUsesSharedResponseIdentityAndStopButtonPolicy() {
        let source = ChatGPTAttentionBridge.scriptSource
        XCTAssertTrue(source.contains("RESPONSE_STABLE_ATTRIBUTE_NAMES"))
        XCTAssertTrue(source.contains("data-message-id"))
        XCTAssertTrue(source.contains("data-message-uuid"))
        XCTAssertTrue(source.contains("canonicalResponseIdentityFor"))
        XCTAssertTrue(source.contains("const responseIdentity = generating"))
        XCTAssertTrue(source.contains("latestAssistantResponseRoot"))
        XCTAssertTrue(source.contains("STOP_SELECTORS"))
        XCTAssertTrue(source.contains("fruitjuice-stop-button"))
        XCTAssertTrue(
            source.contains(
                "'button[aria-label],button[title],[role=\"button\"][aria-label],[role=\"button\"][title]'"
            )
        )
        XCTAssertTrue(source.contains("const responseIdentity = generating"))
    }

    func testBridgeConfiguredBeforeInitialLoad() throws {
        var hadBridgeScriptAtFirstLoad = false
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { webView, _ in
                hadBridgeScriptAtFirstLoad = webView.configuration.userContentController.userScripts
                    .contains { $0.isForMainFrameOnly }
            }
        )

        _ = try pool.webView(for: makeChatGPTProfile())

        // The Factory-owned hidden-scrollbar script is document-start but
        // not main-frame-only, so the flag can only be set by the bridge.
        XCTAssertTrue(hadBridgeScriptAtFirstLoad)
    }

    func testInvalidationKeepsUnrelatedUserScripts() throws {
        let controller = WKUserContentController()
        controller.addUserScript(
            WKUserScript(
                source: "/* unrelated */",
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )
        let harness = ChatGPTAttentionBridgeHarness()
        harness.bridge.install(into: controller)
        XCTAssertEqual(controller.userScripts.count, 2)

        harness.bridge.invalidate()

        XCTAssertEqual(controller.userScripts.count, 2)
        XCTAssertTrue(controller.userScripts.contains { $0.source == "/* unrelated */" })
    }

    // MARK: - Message validation

    func testPayloadValidationRejectsMalformedBodies() throws {
        XCTAssertNil(ChatGPTBridgePayload.parse([:]))
        XCTAssertNil(ChatGPTBridgePayload.parse([
            "version": 2, "kind": "baseline", "token": "12345678", "generating": true,
        ]))
        XCTAssertNil(ChatGPTBridgePayload.parse([
            "version": 1, "kind": "unexpected", "token": "12345678", "generating": true,
        ]))
        XCTAssertNil(ChatGPTBridgePayload.parse([
            "version": 1, "kind": "baseline", "token": "short", "generating": true,
        ]))
        XCTAssertNil(ChatGPTBridgePayload.parse([
            "version": 1, "kind": "baseline", "token": "12345678", "generating": "yes",
        ]))
        XCTAssertEqual(
            ChatGPTBridgePayload.parse([
                "version": 1, "kind": "state", "token": "12345678", "generating": false,
            ]),
            ChatGPTBridgePayload(
                version: 1, kind: "state", token: "12345678", generating: false
            )
        )
        let identity = try XCTUnwrap(
            ChatGPTResponseIdentity(rawValue: "message:attention-response")
        )
        XCTAssertEqual(
            ChatGPTBridgePayload.parse([
                "version": 1,
                "kind": "state",
                "token": "12345678",
                "generating": false,
                "responseIdentity": identity.rawValue
            ])?.responseIdentity,
            identity
        )
        XCTAssertNil(ChatGPTBridgePayload.parse([
            "version": 1,
            "kind": "state",
            "token": "12345678",
            "generating": false,
            "responseIdentity": "response-without-prefix"
        ]))
        XCTAssertNil(ChatGPTBridgePayload.parse([
            "version": 1,
            "kind": "state",
            "token": "12345678",
            "generating": false,
            "responseIdentity": 7
        ]))
    }

    func testMessageFromOtherWebViewIsRejected() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        let otherWebView = WKWebView()

        harness.accept(true, token: tokenA, messageWebView: otherWebView)
        XCTAssertTrue(harness.observations.isEmpty)

        harness.accept(true, token: tokenA)
        XCTAssertEqual(harness.observations, [.generationStarted])
    }

    func testNonMainFrameMessageIsRejected() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1, kind: "baseline", token: tokenA, generating: true
            ),
            messageWebView: harness.webView,
            isMainFrame: false,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        XCTAssertTrue(harness.observations.isEmpty)
    }

    func testUnsupportedOriginEmitsNothing() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA, host: "evilchatgpt.com")
        harness.accept(true, token: tokenA, host: "openai.com")
        harness.accept(true, token: tokenA, host: "chatgpt.com.evil.example")
        harness.accept(true, token: tokenA, host: "chatgpt.com", originProtocol: "about")

        XCTAssertTrue(harness.observations.isEmpty)
    }

    // MARK: - Baseline and transition semantics

    func testIdleBaselineEmitsNoFinish() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(false, token: tokenA)

        XCTAssertTrue(harness.observations.isEmpty)
    }

    func testGeneratingBaselineEmitsOneStart() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA)

        XCTAssertEqual(harness.observations, [.generationStarted])
    }

    func testDuplicateGeneratingEmitsNothing() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA)
        harness.accept(true, token: tokenA)

        XCTAssertEqual(harness.observations, [.generationStarted])
    }

    func testIdleBaselineDoesNotActivateLivenessWatchdog() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(false, token: tokenA)

        XCTAssertFalse(harness.bridge.debugLivenessWatchdogActive)
        XCTAssertEqual(harness.bridge.debugLivenessWatchdogStartCount, 0)
    }

    func testGeneratingBaselineActivatesOneLivenessWatchdogAndDuplicateStartDoesNotDuplicateIt() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA)
        harness.accept(true, token: tokenA, kind: ChatGPTBridgePayload.stateKind)

        XCTAssertTrue(harness.bridge.debugLivenessWatchdogActive)
        XCTAssertEqual(harness.bridge.debugLivenessWatchdogStartCount, 1)
    }

    func testTrueLivenessProbeKeepsGenerationActiveWithoutDuplicateStart() async throws {
        let trueProbe: [String: Any] = [
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": true
        ]
        let harness = ChatGPTAttentionBridgeHarness(probeValues: [trueProbe])

        harness.accept(true, token: tokenA)
        await harness.bridge.debugRunLivenessCycle()

        XCTAssertEqual(harness.observations, [.generationStarted])
        XCTAssertTrue(harness.bridge.debugLivenessWatchdogActive)
        XCTAssertEqual(harness.probeCount(), 1)
    }

    func testFalseFalseLivenessProbeEmitsOneFinishAndStopsWatchdog() async throws {
        let falseProbe: [String: Any] = [
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ]
        let harness = ChatGPTAttentionBridgeHarness(probeValues: [falseProbe, falseProbe])

        harness.accept(true, token: tokenA)
        await harness.bridge.debugRunLivenessCycle()

        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
        XCTAssertFalse(harness.bridge.debugLivenessWatchdogActive)
        XCTAssertEqual(harness.probeCount(), 2)
    }

    func testTimedOutLivenessProbeCannotReopenReplacedEpoch() async throws {
        let probes = LivenessProbeGate()
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            },
            livenessProbeTimeout: 0.01
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        let oldCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await probes.waitForCall(1)
        _ = try await oldCycle.value

        bridge.handleRuntimeReplacement()
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenB,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false],
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false]
        ])

        await bridge.debugRunLivenessCycle()
        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted, .generationFinished]
        )

        // This is the late callback from the timed-out old epoch. It only
        // releases the physical request marker and cannot alter observations.
        probes.resumeSuspended(nil)
        await Task.yield()
        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted, .generationFinished]
        )
    }

    func testWATCHDOG_COMPLETION_IDENTITY() async throws {
        let identity = try XCTUnwrap(
            ChatGPTResponseIdentity(rawValue: "message:watchdog-r1")
        )
        let falseProbe: [String: Any] = [
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false,
            "responseIdentity": identity.rawValue
        ]
        var events: [ChatGPTAttentionEvent] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, _ in },
            livenessProbe: { _ in falseProbe },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            },
            onAttentionEvent: { _, event in
                events.append(event)
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        await bridge.debugRunLivenessCycle()

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].observation, .generationStarted)
        XCTAssertNil(events[0].responseIdentity)
        XCTAssertEqual(events[1].observation, .generationFinished)
        XCTAssertEqual(events[1].responseIdentity, identity)
    }

    func testFalseThenTrueLivenessProbeDoesNotFinishOrStopWatchdog() async throws {
        let falseProbe: [String: Any] = [
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ]
        let trueProbe: [String: Any] = [
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": true
        ]
        let harness = ChatGPTAttentionBridgeHarness(probeValues: [falseProbe, trueProbe])

        harness.accept(true, token: tokenA)
        await harness.bridge.debugRunLivenessCycle()

        XCTAssertEqual(harness.observations, [.generationStarted])
        XCTAssertTrue(harness.bridge.debugLivenessWatchdogActive)
        XCTAssertEqual(harness.probeCount(), 2)
    }

    func testNaturalFinishBeforeManualCycleRemainsSingleEmission() async throws {
        let falseProbe: [String: Any] = [
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ]
        let harness = ChatGPTAttentionBridgeHarness(probeValues: [falseProbe, falseProbe])

        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA, kind: ChatGPTBridgePayload.stateKind)
        await harness.bridge.debugRunLivenessCycle()

        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
        XCTAssertFalse(harness.bridge.debugLivenessWatchdogActive)
    }

    func testOldProbeDoesNotBlockNewEpochLivenessCycle() async throws {
        let probes = LivenessProbeGate()
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        let oldCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await probes.waitForCall(1)

        bridge.handleRuntimeReplacement()
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenB,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false],
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false]
        ])

        await bridge.debugRunLivenessCycle()
        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted, .generationFinished]
        )

        probes.resumeSuspended([
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ])
        await oldCycle.value
        XCTAssertEqual(observations.filter { $0 == .generationFinished }.count, 1)
    }

    func testStaleProbeCannotClearNewCycleOwnerDuringConfirmation() async throws {
        let probes = LivenessProbeGate()
        let confirmation = LivenessConfirmationGate()
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                await confirmation.sleep(nanoseconds)
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        let oldCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await probes.waitForCall(1)
        bridge.handleRuntimeReplacement()
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenB,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false],
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false]
        ])

        let newCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        for _ in 0..<32 where !confirmation.isWaiting {
            await Task.yield()
        }
        XCTAssertTrue(confirmation.isWaiting)

        probes.resumeSuspended([
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ])
        confirmation.resume()
        await newCycle.value
        await oldCycle.value

        XCTAssertEqual(observations.filter { $0 == .generationFinished }.count, 1)
        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted, .generationFinished]
        )
    }

    func testStaleConfirmationFirstThenNewFinish() async throws {
        let probes = LivenessProbeGate()
        let confirmation = LivenessConfirmationGate()
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                await confirmation.sleep(nanoseconds)
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([["version": 1, "kind": "baseline", "token": tokenA!, "generating": false]])

        let oldCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await confirmation.waitForCall(1)

        bridge.handleRuntimeReplacement()
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenB,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false],
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false]
        ])

        let newCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await confirmation.waitForCall(2)

        confirmation.resume(call: 1)
        await oldCycle.value
        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted]
        )

        confirmation.resume(call: 2)
        await newCycle.value

        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted, .generationFinished]
        )
        XCTAssertFalse(bridge.debugLivenessWatchdogActive)
    }

    func testNewFinishFirstThenStaleCallback() async throws {
        let probes = LivenessProbeGate()
        let confirmation = LivenessConfirmationGate()
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            diagnostics: diagnostics,
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                await confirmation.sleep(nanoseconds)
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([["version": 1, "kind": "baseline", "token": tokenA!, "generating": false]])

        let oldCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await confirmation.waitForCall(1)

        bridge.handleRuntimeReplacement()
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenB,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false],
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false]
        ])

        let newCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await confirmation.waitForCall(2)

        confirmation.resume(call: 2)
        await newCycle.value
        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted, .generationFinished]
        )
        XCTAssertFalse(bridge.debugLivenessWatchdogActive)

        confirmation.resume(call: 1)
        await oldCycle.value

        XCTAssertEqual(
            observations,
            [.generationStarted, .runtimeReset, .generationStarted, .generationFinished]
        )
        XCTAssertEqual(
            writer.events.filter { $0.event == "attention.liveness_probe.recovered_completion" }.count,
            1
        )
    }

    func testNaturalFinishWinsWatchdogRaceWithSingleEmission() async throws {
        let probes = LivenessProbeGate()
        let confirmation = LivenessConfirmationGate()
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        var observations: [ChatGPTAttentionObservation] = []
        var completionCallbackCount = 0
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
                if observation == .generationFinished {
                    completionCallbackCount += 1
                }
            },
            diagnostics: diagnostics,
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                await confirmation.sleep(nanoseconds)
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([
            ["version": 1, "kind": "baseline", "token": tokenA!, "generating": false],
            ["version": 1, "kind": "baseline", "token": tokenA!, "generating": false]
        ])

        let cycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        for _ in 0..<32 where !confirmation.isWaiting {
            await Task.yield()
        }
        XCTAssertTrue(confirmation.isWaiting)

        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.stateKind,
                token: tokenA,
                generating: false
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        confirmation.resume()
        await cycle.value

        XCTAssertEqual(observations, [.generationStarted, .generationFinished])
        XCTAssertEqual(completionCallbackCount, 1)
        XCTAssertFalse(bridge.debugLivenessWatchdogActive)
        XCTAssertFalse(writer.events.contains { $0.event == "attention.liveness_probe.recovered_completion" })
    }

    func testAttachmentReplacementRejectsStaleProbeBeforeNewDocumentCompletes() async throws {
        let probes = LivenessProbeGate()
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            }
        )
        let webViewA = WKWebView()
        let webViewB = WKWebView()
        bridge.attach(to: webViewA)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webViewA,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        let oldCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await probes.waitForCall(1)

        bridge.attach(to: webViewB)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenB,
                generating: true
            ),
            messageWebView: webViewB,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        probes.enqueue([
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false],
            ["version": 1, "kind": "baseline", "token": tokenB!, "generating": false]
        ])
        await bridge.debugRunLivenessCycle()
        probes.resumeSuspended([
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ])
        await oldCycle.value

        XCTAssertEqual(observations.filter { $0 == .generationFinished }.count, 1)
        XCTAssertEqual(observations.last, .generationFinished)
    }

    func testStaleNavigationProbeRejectedAfterCommittedBoundary() async throws {
        let probes = LivenessProbeGate()
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            diagnostics: diagnostics,
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        let staleCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await probes.waitForCall(1)

        bridge.handleRuntimeReplacement(
            committedURL: URL(string: "https://chatgpt.com/new")
        )
        probes.resumeSuspended([
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ])
        await staleCycle.value

        XCTAssertEqual(observations, [.generationStarted, .runtimeReset])
        XCTAssertFalse(writer.events.contains { $0.event == "attention.liveness_probe.recovered_completion" })
    }

    func testContentProcessBoundaryRejectsStaleProbeWithoutSyntheticFinish() async throws {
        let probes = LivenessProbeGate()
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            diagnostics: diagnostics,
            livenessProbe: { _ in await probes.next() },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        let staleCycle = Task { @MainActor in
            await bridge.debugRunLivenessCycle()
        }
        await probes.waitForCall(1)

        bridge.handleRuntimeReplacement()
        probes.resumeSuspended([
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ])
        await staleCycle.value

        XCTAssertEqual(observations, [.generationStarted, .runtimeReset])
        XCTAssertFalse(writer.events.contains { $0.event == "attention.liveness_probe.recovered_completion" })
    }

    func testProbeFailureIsDebugOnlyAndLeavesWatchdogRecoverable() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        let harness = ChatGPTAttentionBridgeHarness()
        let bridge = ChatGPTAttentionBridge(
            slotID: harness.slotID,
            onObservation: { _, _ in },
            diagnostics: diagnostics,
            livenessProbe: { _ in nil },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            }
        )
        bridge.attach(to: harness.webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: harness.webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        await bridge.debugRunLivenessCycle()

        let failure = try XCTUnwrap(
            writer.events.last { $0.event == "attention.liveness_probe.failed" }
        )
        XCTAssertEqual(failure.level, .debug)
        XCTAssertTrue(bridge.debugLivenessWatchdogActive)
    }

    func testPendingInstantBackKeepsCurrentDocumentWatchdogAuthoritative() async throws {
        let falseProbe: [String: Any] = [
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": false
        ]
        let harness = ChatGPTAttentionBridgeHarness(probeValues: [falseProbe, falseProbe])

        harness.accept(true, token: tokenA)
        harness.bridge.beginInstantBackHandoff()
        await harness.bridge.debugRunLivenessCycle()

        XCTAssertTrue(harness.bridge.isInstantBackHandoffPending)
        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
    }

    func testRuntimeReplacementAndInvalidationCancelLivenessWatchdog() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)
        harness.bridge.handleRuntimeReplacement()
        XCTAssertFalse(harness.bridge.debugLivenessWatchdogActive)

        harness.accept(true, token: tokenB)
        XCTAssertTrue(harness.bridge.debugLivenessWatchdogActive)
        harness.bridge.invalidate()
        XCTAssertFalse(harness.bridge.debugLivenessWatchdogActive)
    }

    func testRecoveredVisibleCompletionUsesExistingAttentionRouterAsIdle() async throws {
        let coordinator = WebAttentionCoordinator()
        let slotID = UUID()
        let router = WebAttentionObservationRouter(
            attentionCoordinator: coordinator,
            isUserVisible: { _ in true }
        )
        let probes = [
            [
                "version": 1,
                "kind": "baseline",
                "token": tokenA!,
                "generating": false
            ],
            [
                "version": 1,
                "kind": "baseline",
                "token": tokenA!,
                "generating": false
            ]
        ]
        var remaining = probes
        var completionCallbackCount = 0
        let bridge = ChatGPTAttentionBridge(
            slotID: slotID,
            onObservation: { _, observation in
                router.handle(observation, for: slotID)
                if observation == .generationFinished {
                    completionCallbackCount += 1
                }
            },
            livenessProbe: { _ in
                guard !remaining.isEmpty else { return nil }
                return remaining.removeFirst()
            },
            livenessSleeper: { nanoseconds in
                nanoseconds == ChatGPTAttentionBridge.livenessConfirmationDelayNanoseconds
            }
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        await bridge.debugRunLivenessCycle()

        XCTAssertEqual(coordinator.state(for: slotID), .idle)
        XCTAssertTrue(coordinator.readySlotIDs.isEmpty)
        XCTAssertEqual(completionCallbackCount, 1)
    }

    func testGeneratingToIdleEmitsOneFinish() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA)

        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
    }

    func testDuplicateIdleEmitsNothing() throws {
        let harness = ChatGPTAttentionBridgeHarness()

        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA)
        harness.accept(false, token: tokenA)

        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
    }

    func testTrackerDirectlyMatchesBridgeSemantics() throws {
        var tracker = ChatGPTDocumentGenerationTracker()
        XCTAssertNil(tracker.observe(false))
        XCTAssertNil(tracker.observe(false))
        XCTAssertEqual(tracker.observe(true), .generationStarted)
        XCTAssertNil(tracker.observe(true))
        XCTAssertEqual(tracker.observe(false), .generationFinished)
        XCTAssertNil(tracker.observe(false))
    }

    func testCOMPLETION_IDENTITY_ATOMIC() throws {
        let identity = try XCTUnwrap(
            ChatGPTResponseIdentity(rawValue: "message:atomic-finish")
        )
        var tracker = ChatGPTDocumentGenerationTracker()

        XCTAssertNil(tracker.observeEvent(false, responseIdentity: nil))
        XCTAssertEqual(
            tracker.observeEvent(true, responseIdentity: identity)?.observation,
            .generationStarted
        )
        XCTAssertNil(
            tracker.observeEvent(true, responseIdentity: nil)
        )
        let finish = try XCTUnwrap(
            tracker.observeEvent(false, responseIdentity: identity)
        )
        XCTAssertEqual(finish.observation, .generationFinished)
        XCTAssertEqual(finish.responseIdentity, identity)
        XCTAssertNil(tracker.observeEvent(false, responseIdentity: nil))
    }

    func testAttentionEventCallbackCarriesFinishIdentityButNeverStartIdentity() throws {
        let identity = try XCTUnwrap(
            ChatGPTResponseIdentity(rawValue: "message:event-finish")
        )
        let webView = WKWebView()
        var events: [ChatGPTAttentionEvent] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, _ in },
            onAttentionEvent: { _, event in
                events.append(event)
            }
        )
        bridge.attach(to: webView)
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true,
                responseIdentity: identity
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.stateKind,
                token: tokenA,
                generating: false,
                responseIdentity: identity
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        XCTAssertEqual(
            events,
            [
                ChatGPTAttentionEvent(
                    observation: .generationStarted,
                    responseIdentity: nil
                ),
                ChatGPTAttentionEvent(
                    observation: .generationFinished,
                    responseIdentity: identity
                )
            ]
        )
    }

    // MARK: - Navigation lifecycle

    func testProvisionalStartDoesNotResetCurrentDocumentObservations() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA)

        XCTAssertEqual(
            harness.observations,
            [.generationStarted, .generationFinished]
        )
    }

    func testProvisionalFailureRequiresNoReplayOrRuntimeReset() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA)

        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
        XCTAssertFalse(harness.observations.contains(.runtimeReset))
    }

    func testCommittedReplacementEmitsRuntimeResetAndClearsEpoch() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)

        harness.bridge.handleRuntimeReplacement()

        XCTAssertEqual(harness.observations.last, .runtimeReset)
    }

    func testUnsupportedCurrentDocumentClosesAdmissionUntilSupportedCommitResync() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        let unsupportedURL = URL(string: "https://example.com/document")!
        let supportedURL = URL(string: "https://chatgpt.com/c/fresh")!

        harness.accept(true, token: tokenA)
        harness.bridge.handleRuntimeReplacement(committedURL: unsupportedURL)
        XCTAssertEqual(harness.observations, [.generationStarted, .runtimeReset])

        // Neither a late baseline nor a late state from the old ChatGPT
        // runtime can reopen attention while the current document is
        // unsupported.
        harness.accept(false, token: tokenB)
        harness.accept(false, token: tokenA, kind: ChatGPTBridgePayload.stateKind)
        XCTAssertEqual(harness.observations, [.generationStarted, .runtimeReset])

        // A supported ordinary commit now enters the same authorization
        // barrier used by confirmed Instant Back. The detached harness cannot
        // return a named-world resync result, so neither the old document's
        // queued baseline nor the replacement document's natural baseline may
        // claim the epoch by racing the direct current-document read.
        harness.bridge.handleRuntimeReplacement(committedURL: supportedURL)
        harness.accept(true, token: tokenA)
        harness.accept(true, token: tokenB)
        XCTAssertEqual(harness.observations, [.generationStarted, .runtimeReset])
    }

    func testStaleOldDocumentMessageIsRejectedAfterUnknownCommitBoundary() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)
        harness.bridge.handleRuntimeReplacement()
        let observationsAfterReset = harness.observations.count

        // A late in-flight state message from the superseded document cannot
        // re-baseline the replacement epoch when no committed URL is available.
        harness.accept(false, token: tokenA, kind: ChatGPTBridgePayload.stateKind)
        XCTAssertEqual(harness.observations.count, observationsAfterReset)

        // Unknown/runtime-recovery boundaries retain natural-baseline recovery.
        harness.accept(true, token: tokenB)
        XCTAssertEqual(harness.observations.last, .generationStarted)
    }

    func testRestoredDocumentReestablishesBaselineWithSameToken() throws {
        // BFCache/history restore re-reports with the original token; after a
        // committed replacement that token becomes a fresh baseline again.
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(false, token: tokenA)
        harness.bridge.handleRuntimeReplacement()

        harness.accept(true, token: tokenA)

        XCTAssertEqual(harness.observations, [.runtimeReset, .generationStarted])

        // The re-established epoch de-duplicates like any other document.
        harness.accept(true, token: tokenA)
        XCTAssertEqual(harness.observations, [.runtimeReset, .generationStarted])
    }

    func testCurrentDocumentStateContinuesDuringPendingInstantBack() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenB)
        harness.bridge.beginInstantBackHandoff()

        // The current document remains authoritative until confirmation. Its
        // own completion must not be frozen or buffered by the pending request.
        harness.accept(false, token: tokenB, kind: ChatGPTBridgePayload.stateKind)

        XCTAssertTrue(harness.bridge.isInstantBackHandoffPending)
        XCTAssertEqual(harness.observations, [.generationStarted, .generationFinished])
    }

    func testPreconfirmDifferentTokenBaselineIsRejectedUntilResync() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(false, token: tokenB)
        harness.bridge.beginInstantBackHandoff()

        // A different-token baseline before current-history confirmation is
        // not a candidate epoch and is never replayed by native code.
        harness.accept(true, token: tokenA)
        XCTAssertEqual(harness.observations, [])

        harness.bridge.confirmInstantBackHandoff()
        XCTAssertEqual(harness.observations, [.runtimeReset])

        // Without a known supported target, the generic handoff test seam
        // retains natural-baseline recovery after its reset boundary.
        harness.accept(true, token: tokenA)
        XCTAssertEqual(
            harness.observations,
            [.runtimeReset, .generationStarted]
        )
    }

    func testSameURLStaleHistoricalBaselineIsRejectedBeforeConfirmation() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        // A1 and A2 intentionally share a URL; token identity must still keep
        // the stale A1 baseline from becoming the current epoch.
        harness.accept(false, token: "instant-back-current-b")
        harness.bridge.beginInstantBackHandoff(
            targetURL: URL(string: "https://chatgpt.com/c/123")!
        )
        harness.accept(true, token: "instant-back-a1")
        harness.bridge.confirmInstantBackHandoff()
        XCTAssertEqual(harness.observations, [.runtimeReset])

        // The direct resync is unavailable on this detached harness, so the
        // identity barrier remains closed rather than accepting A2 by token
        // guesswork.
        harness.accept(true, token: "instant-back-a2")
        XCTAssertEqual(harness.observations, [.runtimeReset])
    }

    func testTimedOutCurrentDocumentResyncDoesNotOpenAdmissionOnLateBaseline() async throws {
        let gate = CurrentDocumentResyncGate()
        var observations: [ChatGPTAttentionObservation] = []
        let bridge = ChatGPTAttentionBridge(
            slotID: UUID(),
            onObservation: { _, observation in
                observations.append(observation)
            },
            currentDocumentResyncEvaluator: { _, _ in
                try await gate.evaluate()
            },
            currentDocumentResyncTimeout: 0.01
        )
        let webView = WKWebView()
        bridge.attach(to: webView)
        bridge.handleRuntimeReplacement(
            committedURL: URL(string: "https://chatgpt.com/c/current")!
        )
        await gate.waitUntilStarted()
        try await Task.sleep(nanoseconds: 50_000_000)

        gate.resolve([
            "version": 1,
            "kind": ChatGPTBridgePayload.baselineKind,
            "token": tokenA!,
            "generating": true
        ])
        await Task.yield()

        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1,
                kind: ChatGPTBridgePayload.baselineKind,
                token: tokenA,
                generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        XCTAssertTrue(observations.isEmpty)
    }

    func testCancelledInstantBackCannotRebaselineOldRuntime() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenB)
        harness.bridge.beginInstantBackHandoff()
        harness.accept(false, token: tokenA)
        harness.bridge.cancelInstantBackHandoff()

        XCTAssertFalse(harness.bridge.isInstantBackHandoffPending)
        harness.accept(false, token: tokenA)
        XCTAssertEqual(harness.observations, [.generationStarted])
    }

    func testReleaseClearsPendingInstantBackHandoff() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(false, token: tokenB)
        harness.bridge.beginInstantBackHandoff()

        harness.bridge.invalidate()

        XCTAssertFalse(harness.bridge.isInstantBackHandoffPending)
        XCTAssertTrue(harness.bridge.isInvalidated)
    }

    // MARK: - WebContent termination

    func testWebContentTerminationEmitsResetBeforeRecoveryReload() throws {
        var timeline: [String] = []
        let pool = WebViewPool(
            onURLChange: { _, _ in },
            initialLoad: { _, _ in timeline.append("load") },
            isSlotActive: { _ in true }
        )
        pool.onAttentionObservation = { _, observation in
            if case .runtimeReset = observation {
                timeline.append("reset")
            }
        }
        let profile = makeChatGPTProfile()
        _ = try pool.webView(for: profile)
        let bridge = pool.attentionBridge(for: profile.id)!
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1, kind: "baseline", token: tokenA, generating: true
            ),
            messageWebView: pool.existingWebView(for: profile.id),
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
        let boundary = timeline.count

        pool.handleContentProcessTermination(slotID: profile.id)

        XCTAssertEqual(Array(timeline[boundary...]), ["reset", "load"])
    }

    // MARK: - Release / rebuild / remove

    func testReleaseInvalidatesBridgeAndForwardsResetBoundary() throws {
        var observations: [ChatGPTAttentionObservation] = []
        let pool = WebViewPool(onURLChange: { _, _ in })
        pool.onAttentionObservation = { _, observation in
            observations.append(observation)
        }
        let profile = makeChatGPTProfile()
        let webView = try pool.webView(for: profile)
        let bridge = pool.attentionBridge(for: profile.id)!
        bridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1, kind: "baseline", token: tokenA, generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        pool.release(slotID: profile.id)

        XCTAssertTrue(bridge.isInvalidated)
        XCTAssertNil(pool.attentionBridge(for: profile.id))
        XCTAssertEqual(observations.last, .runtimeReset)
    }

    func testStaleCallbackAfterInvalidationIsIgnored() throws {
        let harness = ChatGPTAttentionBridgeHarness()
        harness.accept(true, token: tokenA)
        harness.bridge.invalidate()
        let countAfterInvalidation = harness.observations.count

        harness.accept(true, token: tokenA)
        harness.accept(false, token: tokenA)
        harness.bridge.handleRuntimeReplacement()

        XCTAssertEqual(harness.observations.count, countAfterInvalidation)
    }

    func testRenderingRebuildInvalidatesOldBridgeAndCreatesNewBridge() throws {
        var residentSetChangeCount = 0
        let pool = WebViewPool(onURLChange: { _, _ in })
        pool.onResidentSetChange = { residentSetChangeCount += 1 }
        var profile = makeChatGPTProfile()
        _ = try pool.webView(for: profile)
        let oldBridge = pool.attentionBridge(for: profile.id)!

        profile.renderingProfile = profile.renderingProfile.settingBrowserIdentity(.windowsChrome)
        _ = try pool.webView(for: profile)
        let newBridge = pool.attentionBridge(for: profile.id)!

        XCTAssertFalse(oldBridge === newBridge)
        XCTAssertTrue(oldBridge.isInvalidated)
        XCTAssertFalse(newBridge.isInvalidated)
        // Rebuilding a resident Slot must not fake a resident-set transition.
        XCTAssertEqual(residentSetChangeCount, 1)
    }

    func testRemovingOneSlotLeavesTheOtherBridgeIntact() throws {
        let pool = WebViewPool(onURLChange: { _, _ in })
        let chatGPTProfile = makeChatGPTProfile()
        let otherProfile = WebAppProfile(
            order: 1,
            name: "Docs",
            homeURL: URL(string: "https://chatgpt.com/")!
        )
        _ = try pool.webView(for: chatGPTProfile)
        let otherWebView = try pool.webView(for: otherProfile)
        let chatGPTBridge = pool.attentionBridge(for: chatGPTProfile.id)!
        let otherBridge = pool.attentionBridge(for: otherProfile.id)!

        pool.release(slotID: chatGPTProfile.id)

        XCTAssertTrue(chatGPTBridge.isInvalidated)
        XCTAssertNil(pool.attentionBridge(for: chatGPTProfile.id))
        XCTAssertFalse(otherBridge.isInvalidated)
        XCTAssertTrue(pool.attentionBridge(for: otherProfile.id) === otherBridge)

        // The surviving bridge still processes its own document.
        otherBridge.accept(
            payload: ChatGPTBridgePayload(
                version: 1, kind: "baseline", token: tokenB, generating: true
            ),
            messageWebView: otherWebView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )
    }

    func testPoolForwardsNormalizedObservationsThroughTransientSeam() throws {
        var received: [(UUID, ChatGPTAttentionObservation)] = []
        let pool = WebViewPool(onURLChange: { _, _ in })
        pool.onAttentionObservation = { slotID, observation in
            received.append((slotID, observation))
        }
        let profile = makeChatGPTProfile()
        let webView = try pool.webView(for: profile)

        pool.attentionBridge(for: profile.id)?.accept(
            payload: ChatGPTBridgePayload(
                version: 1, kind: "baseline", token: tokenA, generating: true
            ),
            messageWebView: webView,
            isMainFrame: true,
            originHost: "chatgpt.com",
            originProtocol: "https"
        )

        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(received.first?.0, profile.id)
        XCTAssertEqual(received.first?.1, .generationStarted)
    }

    // MARK: - SlotNavigationObserver forwarding (HTTP fallback interaction)

    func testObserverKeepsHTTPFallbackIndependentOfAttentionLifecycle() throws {
        var events: [String] = []
        let webView = WKWebView()
        let entryURL = URL(string: "https://chat.example.com:8443/")!
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            onNavigationCommit: { _, _ in
                events.append("commit")
            },
            loadHandler: { _, url in
                events.append("fallback:\(url.scheme ?? "")")
            }
        )
        observer.configureHTTPEntryFallback(for: entryURL, allowed: true)

        observer.webView(webView, didStartProvisionalNavigation: nil)
        XCTAssertTrue(events.isEmpty)

        let failure = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost,
            userInfo: ["NSErrorFailingURLStringKey": entryURL.absoluteString]
        )
        observer.webView(
            webView,
            didFailProvisionalNavigation: nil,
            withError: failure
        )
        XCTAssertEqual(events, ["fallback:http"])

        // The fallback request receives its own provisional boundary normally.
        observer.webView(webView, didStartProvisionalNavigation: nil)
        observer.webView(webView, didCommit: nil)
        XCTAssertEqual(events, [
            "fallback:http", "commit",
        ])
    }

    // MARK: - Helpers

    private func makeChatGPTProfile() -> WebAppProfile {
        WebAppProfile(
            order: 0,
            name: "ChatGPT",
            homeURL: URL(string: "https://chatgpt.com/")!
        )
    }
}
