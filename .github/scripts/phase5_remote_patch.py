from pathlib import Path
import re


def sub1(text: str, pattern: str, replacement: str, label: str, flags: int = 0) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    return updated


source_path = Path("FloatTabs/Web/ChatGPTAttentionBridge.swift")
source = source_path.read_text()

source = sub1(
    source,
    r"(?m)^(    static let livenessWatchdogIntervalNanoseconds: UInt64 = 2_000_000_000\n)",
    r"\1    static let longRunningGenerationThreshold: TimeInterval = 30\n"
    r"    static let hiddenLongRunningWatchdogIntervalNanoseconds: UInt64 = 5_000_000_000\n",
    "cadence constants",
)

source = sub1(
    source,
    r'(?m)^(    static let benchmarkSnapshotScript = "globalThis\.__floatTabsAttentionBenchmarkSnapshotV1\?\.\(\)"\n)',
    r'''\1
    static func nextLivenessWatchdogIntervalNanoseconds(
        elapsed: TimeInterval,
        documentIsHidden: Bool?
    ) -> UInt64 {
        guard documentIsHidden == true,
              elapsed >= longRunningGenerationThreshold else {
            return livenessWatchdogIntervalNanoseconds
        }
        return hiddenLongRunningWatchdogIntervalNanoseconds
    }
''',
    "cadence selector",
)

source = sub1(
    source,
    r'(globalThis\.__floatTabsAttentionProbeV1 = \(\) => \{.*?\n\s+generating: generating,\n)(\s+responseIdentity: responseIdentity\n\s+\};\n\s+\};)',
    r'''\1              visibility_state: ["visible", "hidden", "prerender", "unloaded"].includes(document.visibilityState)
                ? document.visibilityState : "other",
\2''',
    "liveness visibility metadata",
    re.S,
)

source = sub1(
    source,
    r"(?m)^(    private var livenessGeneration: UInt64 = 0\n)",
    r"\1    private var lastLivenessDocumentWasHidden: Bool?\n",
    "visibility scheduling state",
)

source = sub1(
    source,
    r'(private func startLivenessWatchdog\(\) \{.*?\n\s+let webViewIdentity = ObjectIdentifier\(webView\)\n)',
    r'''\1        let watchdogStartedAt = ProcessInfo.processInfo.systemUptime
        lastLivenessDocumentWasHidden = nil
''',
    "watchdog start timestamp",
    re.S,
)

source = sub1(
    source,
    r'(diagnostics\.record\(event: "attention\.liveness_watchdog\.started".*?"watchdog_interval_ms": \.integer\(2_000\))(\n\s+\]\))',
    r'''\1,
            "long_running_threshold_ms": .integer(30_000),
            "hidden_long_running_interval_ms": .integer(5_000)\2''',
    "watchdog start diagnostics",
    re.S,
)

source = sub1(
    source,
    r'(?m)^(\s*)guard await self\.livenessSleeper\(Self\.livenessWatchdogIntervalNanoseconds\) else \{ return \}$',
    r'''\1let elapsed = max(ProcessInfo.processInfo.systemUptime - watchdogStartedAt, 0)
\1let interval = Self.nextLivenessWatchdogIntervalNanoseconds(
\1    elapsed: elapsed,
\1    documentIsHidden: self.lastLivenessDocumentWasHidden
\1)
\1guard await self.livenessSleeper(interval) else { return }''',
    "adaptive watchdog sleep",
)

source = sub1(
    source,
    r'(private func stopLivenessWatchdog\(\) \{.*?\n\s+livenessWatchdogTask = nil\n)',
    r'''\1        lastLivenessDocumentWasHidden = nil
''',
    "watchdog visibility reset",
    re.S,
)

source = sub1(
    source,
    r'    private func parseLivenessProbe\(_ value: Any\?\) -> ChatGPTBridgePayload\? \{.*?\n    \}\n\n    /// Bounds the physical WebKit callback budget',
    '''    private struct LivenessProbeSnapshot {
        let payload: ChatGPTBridgePayload
        let documentIsHidden: Bool?

        var token: String { payload.token }
        var generating: Bool { payload.generating }
        var responseIdentity: ChatGPTResponseIdentity? { payload.responseIdentity }
    }

    private func parseLivenessProbe(_ value: Any?) -> LivenessProbeSnapshot? {
        guard let body = value as? [String: Any],
              let payload = ChatGPTBridgePayload.parse(body),
              payload.kind == ChatGPTBridgePayload.baselineKind else { return nil }
        let documentIsHidden: Bool?
        switch body["visibility_state"] as? String {
        case "hidden":
            documentIsHidden = true
        case "visible", "prerender", "unloaded", "other":
            documentIsHidden = false
        default:
            documentIsHidden = nil
        }
        return LivenessProbeSnapshot(
            payload: payload,
            documentIsHidden: documentIsHidden
        )
    }

    /// Bounds the physical WebKit callback budget''',
    "liveness probe parser",
    re.S,
)

source = sub1(
    source,
    r"(?m)^(        if firstProbe\.generating \{)$",
    r"        lastLivenessDocumentWasHidden = firstProbe.documentIsHidden\n\1",
    "first probe scheduling hint",
)

source = sub1(
    source,
    r"(?m)^(        guard !secondProbe\.generating, livenessGeneration == generation else \{)$",
    r"        lastLivenessDocumentWasHidden = secondProbe.documentIsHidden\n\1",
    "confirmation probe scheduling hint",
)

source = sub1(
    source,
    r"(?m)^(    var debugLivenessWatchdogActive: Bool \{ livenessWatchdogTask != nil \}\n)",
    r"\1    var debugLastLivenessDocumentWasHidden: Bool? { lastLivenessDocumentWasHidden }\n",
    "debug visibility seam",
)

source_path.write_text(source)

test_path = Path("FloatTabsTests/ChatGPTAttentionBridgeTests.swift")
tests = test_path.read_text()

tests = sub1(
    tests,
    r'(?m)^(        XCTAssertTrue\(probe\.contains\("generating: generating"\)\)\n)',
    r'''\1        XCTAssertTrue(probe.contains("visibility_state:"))
        XCTAssertTrue(probe.contains("document.visibilityState"))
''',
    "probe visibility assertions",
)

insertion = '''
    func testLongRunningHiddenWatchdogCadenceSelection() {
        let base = ChatGPTAttentionBridge.livenessWatchdogIntervalNanoseconds
        let thrift = ChatGPTAttentionBridge.hiddenLongRunningWatchdogIntervalNanoseconds

        XCTAssertEqual(
            ChatGPTAttentionBridge.nextLivenessWatchdogIntervalNanoseconds(
                elapsed: 0,
                documentIsHidden: true
            ),
            base
        )
        XCTAssertEqual(
            ChatGPTAttentionBridge.nextLivenessWatchdogIntervalNanoseconds(
                elapsed: ChatGPTAttentionBridge.longRunningGenerationThreshold - 0.001,
                documentIsHidden: true
            ),
            base
        )
        XCTAssertEqual(
            ChatGPTAttentionBridge.nextLivenessWatchdogIntervalNanoseconds(
                elapsed: ChatGPTAttentionBridge.longRunningGenerationThreshold,
                documentIsHidden: true
            ),
            thrift
        )
        XCTAssertEqual(
            ChatGPTAttentionBridge.nextLivenessWatchdogIntervalNanoseconds(
                elapsed: 120,
                documentIsHidden: false
            ),
            base
        )
        XCTAssertEqual(
            ChatGPTAttentionBridge.nextLivenessWatchdogIntervalNanoseconds(
                elapsed: 120,
                documentIsHidden: nil
            ),
            base
        )
    }

    func testHiddenLivenessProbeUpdatesSchedulingHintWithoutAttentionTransition() async throws {
        let hiddenProbe: [String: Any] = [
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": true,
            "visibility_state": "hidden"
        ]
        let harness = ChatGPTAttentionBridgeHarness(probeValues: [hiddenProbe])

        harness.accept(true, token: tokenA)
        await harness.bridge.debugRunLivenessCycle()

        XCTAssertEqual(harness.observations, [.generationStarted])
        XCTAssertEqual(harness.bridge.debugLastLivenessDocumentWasHidden, true)
        XCTAssertTrue(harness.bridge.debugLivenessWatchdogActive)
    }

    func testMissingLivenessVisibilityMetadataKeepsConservativeCadenceHint() async throws {
        let probe: [String: Any] = [
            "version": 1,
            "kind": "baseline",
            "token": tokenA!,
            "generating": true
        ]
        let harness = ChatGPTAttentionBridgeHarness(probeValues: [probe])

        harness.accept(true, token: tokenA)
        await harness.bridge.debugRunLivenessCycle()

        XCTAssertNil(harness.bridge.debugLastLivenessDocumentWasHidden)
        XCTAssertEqual(
            ChatGPTAttentionBridge.nextLivenessWatchdogIntervalNanoseconds(
                elapsed: 120,
                documentIsHidden: harness.bridge.debugLastLivenessDocumentWasHidden
            ),
            ChatGPTAttentionBridge.livenessWatchdogIntervalNanoseconds
        )
    }

'''

tests = sub1(
    tests,
    r"(?m)^(    func testTrueLivenessProbeKeepsGenerationActiveWithoutDuplicateStart\(\) async throws \{)$",
    insertion + r"\1",
    "cadence regression tests",
)

test_path.write_text(tests)
