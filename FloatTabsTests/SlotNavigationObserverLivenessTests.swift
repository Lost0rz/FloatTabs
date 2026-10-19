import AppKit
import WebKit
import XCTest
@testable import FloatTabs

@MainActor
final class SlotNavigationObserverLivenessTests: XCTestCase {
    private var retainedWindows: [NSWindow] = []

    func testCrossWorldLivenessDistinguishesMainPageFromFloatTabsIsolatedWorld() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let webView = makeWebView()
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            diagnostics: diagnostics,
            crossWorldLivenessInterval: 300,
            livenessProbeEvaluator: { _, world in
                switch world {
                case .mainPage:
                    return .success(
                        readyState: "complete",
                        visibilityState: "visible",
                        latencyMilliseconds: 1.25
                    )
                case .floatTabsIsolated:
                    return .terminal(.timeout, latencyMilliseconds: 5_000)
                }
            }
        )
        loadChatGPTHTML("<main>Cross-world probe</main>", in: webView)
        await settle(webView)
        XCTAssertEqual(observer.currentNavigationDiagnosticFields["navigation_phase"], .string("finished"))

        await observer.captureCrossWorldLivenessOnce()

        let event = try XCTUnwrap(
            writer.events.last { $0.event == "web_runtime.cross_world_liveness" }
        )
        XCTAssertEqual(event.fields["main_world_probe_outcome"], .string("success"))
        XCTAssertEqual(event.fields["isolated_world_probe_outcome"], .string("timeout"))
        XCTAssertEqual(event.fields["navigation_finished"], .bool(true))
        XCTAssertEqual(event.fields["post_finish_dual_timeout_count"], .integer(0))
        XCTAssertEqual(event.fields["webcontent_resource_attribution"], .string("unavailable_public_api"))
        XCTAssertNotNil(event.fields["host_resident_size_bytes"])
        XCTAssertNil(event.fields["page_text"])
        XCTAssertNil(event.fields["prompt"])
        XCTAssertNil(event.fields["response_text"])
        XCTAssertNil(event.fields["document_token"])
        XCTAssertNil(writer.events.last { $0.event == "web_runtime.post_finish_stall_candidate" })
        XCTAssertNil(writer.events.last { $0.event == "web_runtime.post_finish_stall_detected" })
    }

    func testDualTimeoutNeedsTwoFinishedSamplesBeforeConfirmedPostFinishStall() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let webView = makeWebView()
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            diagnostics: diagnostics,
            crossWorldLivenessInterval: 300,
            livenessProbeEvaluator: { _, _ in
                .terminal(.timeout, latencyMilliseconds: 5_000)
            }
        )
        loadChatGPTHTML("<main>Dual timeout</main>", in: webView)
        await settle(webView)
        XCTAssertEqual(observer.currentNavigationDiagnosticFields["navigation_phase"], .string("finished"))

        await observer.captureCrossWorldLivenessOnce()
        let candidate = try XCTUnwrap(
            writer.events.last { $0.event == "web_runtime.post_finish_stall_candidate" }
        )
        XCTAssertEqual(candidate.fields["stall_class"], .string("POST_FINISH_RUNTIME_STALL"))
        XCTAssertEqual(candidate.fields["stall_confirmation_state"], .string("candidate"))
        XCTAssertEqual(candidate.fields["post_finish_dual_timeout_count"], .integer(1))

        await observer.captureCrossWorldLivenessOnce()
        let confirmed = try XCTUnwrap(
            writer.events.last { $0.event == "web_runtime.post_finish_stall_detected" }
        )
        XCTAssertEqual(confirmed.fields["stall_class"], .string("POST_FINISH_RUNTIME_STALL"))
        XCTAssertEqual(confirmed.fields["stall_confirmation_state"], .string("confirmed"))
        XCTAssertEqual(confirmed.fields["post_finish_dual_timeout_count"], .integer(2))
        XCTAssertEqual(confirmed.fields["navigation_phase"], .string("finished"))
    }

    func testCrossWorldLivenessMarksResultsStaleWhenRuntimeContextIsInvalidated() async throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let webView = makeWebView()
        let gate = CrossWorldLivenessProbeTestGate()
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            diagnostics: diagnostics,
            crossWorldLivenessInterval: 300,
            livenessProbeEvaluator: { _, _ in
                await gate.evaluate()
            }
        )
        loadChatGPTHTML("<main>Stale probe</main>", in: webView)
        await settle(webView)
        XCTAssertEqual(observer.currentNavigationDiagnosticFields["navigation_phase"], .string("finished"))

        let capture = Task { @MainActor in
            await observer.captureCrossWorldLivenessOnce()
        }
        await gate.waitUntilStarted(count: 2)
        observer.invalidateDiagnosticNavigation()
        gate.resolveAll(
            .success(
                readyState: "complete",
                visibilityState: "visible",
                latencyMilliseconds: 1
            )
        )
        await capture.value

        let event = try XCTUnwrap(
            writer.events.last { $0.event == "web_runtime.cross_world_liveness" }
        )
        XCTAssertEqual(event.fields["runtime_context_current"], .bool(false))
        XCTAssertEqual(event.fields["main_world_probe_outcome"], .string("stale"))
        XCTAssertEqual(event.fields["isolated_world_probe_outcome"], .string("stale"))
        XCTAssertEqual(event.fields["post_finish_dual_timeout_count"], .integer(0))
        XCTAssertNil(writer.events.last { $0.event == "web_runtime.post_finish_stall_detected" })
    }

    func testObservedContentProcessEpochAdvancesOnlyAtDocumentedTerminationCallback() throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .standard, writer: writer)
        let webView = makeWebView()
        let identity = WebRuntimeDiagnosticIdentity(
            runtimeGeneration: 42,
            webViewInstanceID: UUID()
        )
        let observer = SlotNavigationObserver(
            slotID: UUID(),
            webView: webView,
            runtimeDiagnosticIdentity: identity,
            websiteMode: .desktop,
            onURLChange: { _, _ in },
            diagnostics: diagnostics,
            crossWorldLivenessInterval: 300
        )

        XCTAssertEqual(
            observer.currentContentProcessDiagnosticFields["observed_content_process_epoch"],
            .integer(1)
        )
        XCTAssertEqual(
            observer.currentContentProcessDiagnosticFields["observed_content_process_termination_count"],
            .integer(0)
        )

        observer.webViewWebContentProcessDidTerminate(webView)
        let first = try XCTUnwrap(
            writer.events.last { $0.event == "web_content_process_terminated" }
        )
        XCTAssertEqual(first.fields["observed_content_process_epoch"], .integer(2))
        XCTAssertEqual(first.fields["observed_content_process_termination_count"], .integer(1))
        XCTAssertEqual(first.fields["runtime_generation"], .integer(42))
        XCTAssertEqual(
            first.fields["webview_instance_id"],
            .string(identity.webViewInstanceID.uuidString)
        )

        observer.webViewWebContentProcessDidTerminate(webView)
        XCTAssertEqual(
            observer.currentContentProcessDiagnosticFields["observed_content_process_epoch"],
            .integer(3)
        )
        XCTAssertEqual(
            observer.currentContentProcessDiagnosticFields["observed_content_process_termination_count"],
            .integer(2)
        )
    }

    private func makeWebView() -> WKWebView {
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.orderFrontRegardless()
        retainedWindows.append(window)
        return webView
    }

    private func loadChatGPTHTML(_ body: String, in webView: WKWebView) {
        webView.loadHTMLString(
            "<!doctype html><html><body>\(body)</body></html>",
            baseURL: URL(string: "https://chatgpt.com/")
        )
    }

    private func settle(_ webView: WKWebView) async {
        for _ in 0..<80 {
            if !webView.isLoading {
                try? await Task.sleep(nanoseconds: 150_000_000)
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("WKWebView did not finish loading test document")
    }
}

@MainActor
private final class CrossWorldLivenessProbeTestGate {
    private var continuations: [CheckedContinuation<WebRuntimeLivenessProbeResult, Never>] = []

    func evaluate() async -> WebRuntimeLivenessProbeResult {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilStarted(count: Int) async {
        while continuations.count < count {
            await Task.yield()
        }
    }

    func resolveAll(_ result: WebRuntimeLivenessProbeResult) {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume(returning: result) }
    }
}
