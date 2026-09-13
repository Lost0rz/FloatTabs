# Runtime Diagnostics V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local, privacy-sanitized Runtime Diagnostics V1 system that reconstructs critical FloatTabs runtime transactions without becoming a business-state authority.

**Architecture:** `AppCoordinator` composes one `RuntimeDiagnostics` instance and injects the narrow `RuntimeDiagnosticRecording` protocol into runtime owners. `RuntimeDiagnosticEvent` and `RuntimeDiagnosticPrivacy` define the contract at the recording boundary; `RuntimeDiagnosticWriter` owns a dedicated serial queue for buffered JSONL append, rotation, retention, export reads, and bounded best-effort final flush. Snapshots are assembled on demand from existing owners and never cached.

**Tech Stack:** Swift, AppKit, WebKit, OSLog, Foundation JSON Codable, XCTest, Xcode project targets.

**Spec:** `docs/product/FloatTabs_Runtime_Diagnostics_Contract_V1.md`

## Global Constraints

- `schema_version = 1`.
- Default logging mode is `Standard`.
- Runtime Diagnostics is `OBSERVATION ONLY` and never owns active-tab, focus, attention, fullscreen, visibility, lifecycle, or WebView state.
- `RuntimeDiagnosticPrivacy` is the mandatory sanitizer for every persisted diagnostic event.
- `RuntimeDiagnosticWriter` uses an independent serial execution environment; MainActor only performs fast enqueue and never synchronous file I/O.
- `RuntimeDiagnosticSnapshot` only reads current owner facts and never caches or copies business state.
- `trace_id` is transaction correlation only and never replaces `presentationFocusGeneration`, `SlotLifecycleCoordinator`’s `InactivePlan.token`, `fullscreen restoreGeneration`, `WebAttentionCoordinator` state, or existing identities/generations.
- Termination is `record termination event → request final drain / flush → bounded best-effort completion → terminate normally`; logging failure cannot change termination outcome.
- `BenchmarkControlServer` remains strictly DEBUG-only; no Release network listener, telemetry endpoint, or remote logging is added.
- Storage is `~/Library/Application Support/FloatTabs/Diagnostics/Logs/`, one segment `<= 10 MiB`, maximum 10 segments, retention `<= 7 days`, directory mode `0700` where supported, file mode `0600` where supported.
- Standard never records `mouseMoved`, continuous `mouseDragged`, animation frames, resize frames, DOM mutation callbacks, 50 ms fullscreen watchdog polls, or per-frame WebView/UI callbacks.
- Existing business state transitions, focus handshakes, restore decisions, and lifecycle authorities remain unchanged.

---

### Task 1: Add failing core contract tests

**Files:**
- Create: `FloatTabsTests/RuntimeDiagnosticsTests.swift`
- Create: `FloatTabsTests/RuntimeDiagnosticsPrivacyTests.swift`
- Create: `FloatTabsTests/RuntimeDiagnosticsTraceTests.swift`
- Create: `FloatTabsTests/RuntimeDiagnosticsRotationTests.swift`
- Modify: `FloatTabs.xcodeproj/project.pbxproj` to add the four test files to the `FloatTabsTests` target.

**Interfaces:**
- Tests refer to the not-yet-implemented `RuntimeDiagnosticEvent`, `RuntimeDiagnosticMode`, `RuntimeDiagnosticLevel`, `RuntimeDiagnosticTrace`, `RuntimeDiagnostics`, `RuntimeDiagnosticPrivacy`, `RuntimeDiagnosticWriter`, and `RuntimeDiagnosticInMemoryWriter` interfaces defined in later tasks.

- [ ] **Step 1: Write the failing event and gating tests**

```swift
import XCTest
@testable import FloatTabs

@MainActor
final class RuntimeDiagnosticsTests: XCTestCase {
    func testEventsEncodeAsIndependentJSONLObjectsWithSessionAndMonotonicSequence() throws {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(
            mode: .verbose,
            writer: writer,
            sessionID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            uptime: { 42 }
        )

        diagnostics.record(
            event: "test.first",
            level: .notice,
            subsystem: "tests",
            fields: ["value": .integer(1)]
        )
        diagnostics.record(
            event: "test.second",
            level: .warning,
            subsystem: "tests",
            fields: ["value": .integer(2)]
        )

        let lines = writer.lines
        XCTAssertEqual(lines.count, 2)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = try lines.map {
            try decoder.decode(RuntimeDiagnosticEvent.self, from: $0)
        }
        XCTAssertEqual(events.map(\.schemaVersion), [1, 1])
        XCTAssertEqual(Set(events.map(\.sessionID)).count, 1)
        XCTAssertEqual(events.map(\.sequence), [1, 2])
    }

    func testStandardSuppressesDebugAndOffSuppressesEverything() {
        let standardWriter = RuntimeDiagnosticInMemoryWriter()
        let standard = RuntimeDiagnostics(mode: .standard, writer: standardWriter)
        standard.record(event: "test.debug", level: .debug, subsystem: "tests")
        standard.record(event: "test.notice", level: .notice, subsystem: "tests")
        XCTAssertEqual(standardWriter.events.map(\.event), ["test.notice"])

        let offWriter = RuntimeDiagnosticInMemoryWriter()
        let off = RuntimeDiagnostics(mode: .off, writer: offWriter)
        off.record(event: "test.notice", level: .notice, subsystem: "tests")
        XCTAssertTrue(offWriter.events.isEmpty)
    }
}
```

- [ ] **Step 2: Write the failing privacy tests**

```swift
import XCTest
@testable import FloatTabs

final class RuntimeDiagnosticsPrivacyTests: XCTestCase {
    func testURLsRemoveUserInfoQueryAndFragmentAndRedactConversationLikePath() {
        let url = URL(string: "https://user:password@example.com/c/secret-conversation?token=abc#message")!
        XCTAssertEqual(
            RuntimeDiagnosticPrivacy.safeURLString(url, mode: .standard),
            "https://example.com"
        )
        XCTAssertEqual(
            RuntimeDiagnosticPrivacy.safeURLString(url, mode: .verbose),
            "https://example.com/c/<redacted>"
        )
    }

    func testSensitiveFieldsAreDroppedBeforePersistence() {
        let fields = RuntimeDiagnosticPrivacy.sanitize(fields: [
            "token": .string("secret"),
            "Authorization": .string("Bearer secret"),
            "inputValue": .string("private text"),
            "safeState": .string("ready")
        ], mode: .verbose)

        XCTAssertNil(fields["token"])
        XCTAssertNil(fields["Authorization"])
        XCTAssertNil(fields["inputValue"])
        XCTAssertEqual(fields["safeState"], .string("ready"))
    }
}
```

- [ ] **Step 3: Write the failing trace tests**

```swift
import XCTest
@testable import FloatTabs

@MainActor
final class RuntimeDiagnosticsTraceTests: XCTestCase {
    func testOneSemanticTraceIsSharedAndIndependentEventsMayHaveNoTrace() {
        let writer = RuntimeDiagnosticInMemoryWriter()
        let diagnostics = RuntimeDiagnostics(mode: .verbose, writer: writer)
        let trace = diagnostics.beginTrace(root: "presentation", fields: ["source": .string("hotkey")])

        diagnostics.record(event: "panel.presentation.begin", level: .notice, subsystem: "panel", trace: trace)
        diagnostics.record(event: "panel.presentation.completed", level: .notice, subsystem: "panel", trace: trace)
        diagnostics.record(event: "background.cleanup", level: .info, subsystem: "storage")

        XCTAssertEqual(writer.events.prefix(2).map(\.traceID), [trace.id, trace.id])
        XCTAssertNil(writer.events.last?.traceID)
        XCTAssertEqual(Set(writer.events.prefix(2).map(\.traceID)).count, 1)
    }
}
```

- [ ] **Step 4: Write the failing rotation and failure-isolation tests**

```swift
import XCTest
@testable import FloatTabs

final class RuntimeDiagnosticsRotationTests: XCTestCase {
    func testWriterRotatesAtConfiguredLimitAndRetainsOnlyConfiguredSegments() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatTabsDiagnostics-\(UUID().uuidString)")
        let writer = RuntimeDiagnosticWriter(
            directory: directory,
            maxSegmentBytes: 220,
            maxSegments: 2,
            retention: 7 * 24 * 60 * 60
        )
        for sequence in 1...12 {
            writer.enqueue(RuntimeDiagnosticEvent.test(sequence: UInt64(sequence)))
        }
        let flushed = expectation(description: "writer flushed")
        writer.requestFinalFlush(timeout: 1) { flushed.fulfill() }
        wait(for: [flushed], timeout: 2)

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
        XCTAssertLessThanOrEqual(files.count, 2)
        XCTAssertTrue(files.allSatisfy { (try? Data(contentsOf: $0)) != nil })
    }

    func testWriterFailureDoesNotThrowOrInvokeBusinessError() {
        let writer = RuntimeDiagnosticWriter(directory: URL(fileURLWithPath: "/dev/null/impossible"))
        writer.enqueue(RuntimeDiagnosticEvent.test(sequence: 1))
        writer.requestFinalFlush(timeout: 0.1) {}
    }
}

private extension RuntimeDiagnosticEvent {
    static func test(sequence: UInt64) -> RuntimeDiagnosticEvent {
        RuntimeDiagnosticEvent(
            schemaVersion: 1,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(sequence)),
            uptime: Double(sequence),
            sequence: sequence,
            sessionID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            traceID: nil,
            level: .notice,
            subsystem: "tests",
            event: "test.event",
            fields: ["payload": .string(String(repeating: "x", count: 80))]
        )
    }
}
```

- [ ] **Step 5: Run the new tests to verify they fail for missing production APIs**

Run: `xcodebuild -project FloatTabs.xcodeproj -scheme FloatTabs -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/FloatTabsDiagnosticsDerivedData -clonedSourcePackagesDirPath /private/tmp/FloatTabsBaselineSourcePackages CODE_SIGNING_ALLOWED=NO -only-testing:FloatTabsTests/RuntimeDiagnosticsTests -only-testing:FloatTabsTests/RuntimeDiagnosticsPrivacyTests -only-testing:FloatTabsTests/RuntimeDiagnosticsTraceTests -only-testing:FloatTabsTests/RuntimeDiagnosticsRotationTests test`

Expected: FAIL with missing `RuntimeDiagnostics` production symbols, not a test syntax failure.

- [ ] **Step 6: Commit the red tests**

```bash
git add FloatTabsTests/RuntimeDiagnosticsTests.swift FloatTabsTests/RuntimeDiagnosticsPrivacyTests.swift FloatTabsTests/RuntimeDiagnosticsTraceTests.swift FloatTabsTests/RuntimeDiagnosticsRotationTests.swift FloatTabs.xcodeproj/project.pbxproj
git commit -m "test: define runtime diagnostics contract"
```

### Task 2: Implement event model, privacy boundary, and core recorder

**Files:**
- Create: `FloatTabs/Diagnostics/RuntimeDiagnosticEvent.swift`
- Create: `FloatTabs/Diagnostics/RuntimeDiagnosticPrivacy.swift`
- Create: `FloatTabs/Diagnostics/RuntimeDiagnostics.swift`
- Modify: `FloatTabs.xcodeproj/project.pbxproj` to add the Diagnostics source group and files to the app target.

**Interfaces:**
- Produces `RuntimeDiagnosticEvent`, `RuntimeDiagnosticValue`, `RuntimeDiagnosticMode`, `RuntimeDiagnosticLevel`, `RuntimeDiagnosticTrace`, `RuntimeDiagnosticRecording`, `RuntimeDiagnosticNoopRecorder`, and `RuntimeDiagnostics`.
- `RuntimeDiagnostics.record(event:level:subsystem:trace:fields:)` always sanitizes fields before OSLog or writer delivery.
- `RuntimeDiagnostics.beginTrace(root:fields:)` creates one UUID for a semantic transaction; it does not create IDs per event.

- [ ] **Step 1: Implement the smallest Codable value and envelope types required by the red tests**

```swift
enum RuntimeDiagnosticValue: Codable, Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case integer(Int64)
    case double(Double)
    case null
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
}
```

- [ ] **Step 2: Implement the central privacy sanitizer before connecting the writer**

Implement `RuntimeDiagnosticPrivacy.safeURLString(_:mode:)`, `sanitize(fields:mode:)`, `sanitizedErrorCategory(_:)`, and `safeBundleIdentifier(_:)`. Drop keys containing `token`, `cookie`, `authorization`, `password`, `body`, `html`, `input`, `value`, `content`, `title`, `query`, `fragment`, `userInfo`, `username`, `home`, `serial`, `hardware`, `ip`, or `location`. For verbose URLs, preserve only static-looking path segments and replace dynamic/conversation-like segments with `<redacted>`; always remove user info, query, and fragment.

- [ ] **Step 3: Implement `RuntimeDiagnostics` with process session and sequence state**

Use `ProcessInfo.processInfo.systemUptime` for the default uptime provider, `Date()` for wall-clock time, and `UUID()` once per instance for session ID. Sequence increments only after mode gating accepts an event. Send the sanitized event to OSLog and the injected writer; no file API is called here.

- [ ] **Step 4: Run the four new test files and verify they pass**

Run: `xcodebuild -project FloatTabs.xcodeproj -scheme FloatTabs -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/FloatTabsDiagnosticsDerivedData -clonedSourcePackagesDirPath /private/tmp/FloatTabsBaselineSourcePackages CODE_SIGNING_ALLOWED=NO -only-testing:FloatTabsTests/RuntimeDiagnosticsTests -only-testing:FloatTabsTests/RuntimeDiagnosticsPrivacyTests -only-testing:FloatTabsTests/RuntimeDiagnosticsTraceTests -only-testing:FloatTabsTests/RuntimeDiagnosticsRotationTests test`

Expected: event, privacy, and trace tests pass; rotation tests remain red until Task 3 supplies the writer.

- [ ] **Step 5: Commit the event/privacy/core implementation**

```bash
git add FloatTabs/Diagnostics FloatTabs.xcodeproj/project.pbxproj
git commit -m "feat: add runtime diagnostics event and privacy boundary"
```

### Task 3: Implement serial JSONL writer, rotation, retention, and export primitives

**Files:**
- Create: `FloatTabs/Diagnostics/RuntimeDiagnosticWriter.swift`
- Create: `FloatTabs/Diagnostics/RuntimeDiagnosticExporter.swift`
- Modify: `FloatTabs/Diagnostics/RuntimeDiagnostics.swift` to use the writer protocol and no-op/in-memory writer.
- Modify: `FloatTabs.xcodeproj/project.pbxproj`.

**Interfaces:**
- `RuntimeDiagnosticWriting.enqueue(_:)` performs no caller-thread file I/O.
- `RuntimeDiagnosticWriting.requestFinalFlush(timeout:completion:)` schedules a bounded best-effort drain and invokes completion asynchronously; it never blocks MainActor or throws into business code.
- `RuntimeDiagnosticWriter` owns a private serial `DispatchQueue`, a buffered `Data` append buffer, and fail-soft disable state.
- `RuntimeDiagnosticExporter.exportRecent(to:completion:)` reads retained segments and writes one JSONL export on the writer queue, prepending a sanitized environment/session header.

- [ ] **Step 1: Make the rotation test fail specifically on absent writer behavior**

Run the Task 1 rotation test and confirm the failure references the missing writer implementation rather than directory cleanup or test syntax.

- [ ] **Step 2: Implement the serial writer queue and buffered append**

Create directories with `FileManager.createDirectory` on the writer queue, create files with POSIX permissions where available, encode each event with an ISO-8601 `JSONEncoder`, append a newline, and flush when the buffer reaches 64 KiB or for warning/error/fault events. The queue is the only place that opens, appends, rotates, or closes files.

- [ ] **Step 3: Implement naming, size rotation, age retention, and fail-soft errors**

Use `runtime-YYYYMMDD-NNN.jsonl`, rotate before a flushed buffer would exceed `maxSegmentBytes`, remove oldest files beyond `maxSegments`, remove files older than `retention`, and call one non-recursive `Logger` fallback on failure before disabling the writer. Never throw from `enqueue` or `requestFinalFlush`.

- [ ] **Step 4: Implement no-op and in-memory writers for tests**

`RuntimeDiagnosticNoopWriter` discards events and calls final-flush completion asynchronously. `RuntimeDiagnosticInMemoryWriter` stores events and encoded lines under a lock for deterministic tests; it never touches Application Support.

- [ ] **Step 5: Implement export from retained events only**

Export must use the same `RuntimeDiagnosticPrivacy` boundary, include environment/session fields only from injected safe values, and write `FloatTabs-Diagnostics-<timestamp>.jsonl` without ZIP or third-party dependencies.

- [ ] **Step 6: Run core and rotation tests until green**

Run: `xcodebuild -project FloatTabs.xcodeproj -scheme FloatTabs -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/FloatTabsDiagnosticsDerivedData -clonedSourcePackagesDirPath /private/tmp/FloatTabsBaselineSourcePackages CODE_SIGNING_ALLOWED=NO -only-testing:FloatTabsTests/RuntimeDiagnosticsTests -only-testing:FloatTabsTests/RuntimeDiagnosticsPrivacyTests -only-testing:FloatTabsTests/RuntimeDiagnosticsTraceTests -only-testing:FloatTabsTests/RuntimeDiagnosticsRotationTests test`

Expected: all new core, privacy, trace, rotation, retention, final-flush, and failure-isolation assertions pass.

- [ ] **Step 7: Commit the writer/export implementation**

```bash
git add FloatTabs/Diagnostics FloatTabs.xcodeproj/project.pbxproj
git commit -m "feat: add fail-soft diagnostic JSONL writer"
```

### Task 4: Add preferences, composition root, snapshots, and App/Input instrumentation

**Files:**
- Create: `FloatTabs/Diagnostics/RuntimeDiagnosticSnapshot.swift`
- Modify: `FloatTabs/Persistence/AppPreferencesStore.swift`.
- Modify: `FloatTabs/App/AppCoordinator.swift`.
- Modify: `FloatTabs/App/AppDelegate.swift` only to request bounded final flush from `AppCoordinator` during the existing termination callback; do not add `applicationShouldTerminate` ownership or `terminateLater`.
- Modify: `FloatTabs/Hotkeys/GlobalHotkeyController.swift`.
- Modify: `FloatTabs/Hotkeys/AppCommandController.swift`.
- Modify: `FloatTabs/MenuBar/StatusItemController.swift`.
- Modify: `FloatTabs/Panel/PanelController.swift`.
- Modify: `FloatTabs.xcodeproj/project.pbxproj` if needed for the snapshot source.
- Test: extend `FloatTabsTests/AppPreferencesStoreTests.swift` and add `FloatTabsTests/RuntimeDiagnosticsInstrumentationTests.swift`.

**Interfaces:**
- `AppPreferencesStore.diagnosticsMode` persists `RuntimeDiagnosticMode` under `FloatTabs.diagnosticsMode`, defaults to `.standard`, and posts `.floatTabsDiagnosticsModeDidChange`.
- `RuntimeDiagnosticSnapshot` is a value assembled by `PanelController` from current window/owner facts.
- Hotkey, command, and menu callbacks carry an optional `RuntimeDiagnosticTrace` only where an existing callback already represents a semantic root; no keyboard stream is logged.

- [ ] **Step 1: Add failing preference and instrumentation assertions**

```swift
func testDiagnosticsModeDefaultsToStandardAndPersists() {
    let store = AppPreferencesStore(defaults: defaults)
    XCTAssertEqual(store.diagnosticsMode, .standard)
    store.diagnosticsMode = .verbose
    XCTAssertEqual(AppPreferencesStore(defaults: defaults).diagnosticsMode, .verbose)
}
```

Add in-memory instrumentation checks that a hotkey emits `hotkey.toggle.received`, a resolved command emits a semantic command event, and status-item presentation emits `menubar.toggle.intent` before `menubar.toggle.dispatch`.

- [ ] **Step 2: Run the focused tests and verify the new assertions fail**

Run: `xcodebuild -project FloatTabs.xcodeproj -scheme FloatTabs -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/FloatTabsDiagnosticsDerivedData -clonedSourcePackagesDirPath /private/tmp/FloatTabsBaselineSourcePackages CODE_SIGNING_ALLOWED=NO -only-testing:FloatTabsTests/AppPreferencesStoreTests -only-testing:FloatTabsTests/RuntimeDiagnosticsInstrumentationTests test`

Expected: FAIL only because the preference property and instrumentation events are not implemented.

- [ ] **Step 3: Implement preference mode and inject one recorder from AppCoordinator**

Construct `RuntimeDiagnostics` after resolving `AppPreferencesStore`, pass it to `TabStore`, `WebViewPool`, `PanelController`, `GlobalHotkeyController`, `AppCommandController`, `StatusItemController`, and the other owners in later tasks. Keep existing test initializers source-compatible with a fresh no-op recorder default.

- [ ] **Step 4: Instrument app launch/ready/termination and input roots**

Record `app.launch` with safe environment header fields, `app.ready`, `app.termination.begin`, and `app.termination.flush`. Record `hotkey.toggle.received`, `hotkey.primary_focus.received`, resolved `app_command.received`, `menubar.toggle.intent`, and `menubar.toggle.dispatch`. The termination path calls `requestFinalFlush(timeout: 0.25, completion:)` and returns immediately.

- [ ] **Step 5: Instrument PanelController presentation, focus, and previous-app observations**

Record requested/begin/completed/dismiss events and capture the existing values of `presentationFocusGeneration`, requested visibility, app active state, panel/source visibility/key state, active slot ID, fullscreen state, and display IDs. Correlate focus events with the generation’s trace, record stale/failed warnings, and preserve the existing one-settle-pass event-driven handshake.

- [ ] **Step 6: Implement the read-only snapshot provider**

Build `RuntimeDiagnosticSnapshot` directly from the current `PanelController`, `TabStore`, `WebViewPool`, `WebAttentionCoordinator`, and `WebFocusRouter` values at record time. Do not add a cached snapshot property or a periodic timer.

- [ ] **Step 7: Run focused tests and commit**

Run: `xcodebuild -project FloatTabs.xcodeproj -scheme FloatTabs -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/FloatTabsDiagnosticsDerivedData -clonedSourcePackagesDirPath /private/tmp/FloatTabsBaselineSourcePackages CODE_SIGNING_ALLOWED=NO -only-testing:FloatTabsTests/AppPreferencesStoreTests -only-testing:FloatTabsTests/RuntimeDiagnosticsInstrumentationTests test`

Expected: focused preference and instrumentation tests pass with existing AppCommand, ScreenPositioning, and Panel tests unchanged.

```bash
git add FloatTabs FloatTabsTests FloatTabs.xcodeproj/project.pbxproj
git commit -m "feat: instrument app presentation and input roots"
```

### Task 5: Instrument fullscreen, WebFocus, tabs, WebView runtime, lifecycle, attention, and navigation

**Files:**
- Modify: `FloatTabs/Panel/FullscreenSourceHost.swift`.
- Modify: `FloatTabs/Web/WebFocusRouter.swift`.
- Modify: `FloatTabs/Tabs/TabStore.swift`.
- Modify: `FloatTabs/Web/WebViewPool.swift`.
- Modify: `FloatTabs/Web/SlotLifecycleCoordinator.swift`.
- Modify: `FloatTabs/Web/WebAttentionCoordinator.swift`.
- Modify: `FloatTabs/Web/SlotNavigationObserver.swift`.
- Modify: `FloatTabs/Web/DownloadCoordinator.swift` only if it is present in the same source file and only for sanitized navigation failure observation; do not expand diagnostics to downloaded content or file paths.
- Modify: `FloatTabs/Panel/PanelController.swift` for narrow recorder propagation only.
- Test: extend `FloatTabsTests/WebFocusAdapterTests.swift`, `FloatTabsTests/TabStoreTests.swift`, `FloatTabsTests/WebViewPoolTests.swift`, and add subsystem assertions to `RuntimeDiagnosticsInstrumentationTests.swift`.

**Interfaces:**
- Every modified owner receives `RuntimeDiagnosticRecording` by initializer injection and falls back to a fresh no-op recorder in test-only construction paths.
- Existing callbacks remain business-only; diagnostic calls are side effects after the existing decision/transition has occurred.
- URL fields use `RuntimeDiagnosticPrivacy.safeURLString`; errors use `sanitizedErrorCategory`; no raw `NSError.userInfo`, page body, DOM text/value, or tab name is passed.

- [ ] **Step 1: Add failing event assertions for each owner**

Add tests that exercise real owner transitions and assert these event names: `fullscreen.state.transition`, `fullscreen.restore.begin`, `fullscreen.restore.completed`, `fullscreen.source.rebuild_required`, `space.reconcile`, `source.order_front`, `source.focus.result`, `web_focus.webview_changed`, `web_focus.recognition`, `web_focus.toggle`, `web_focus.failed`, `tab.selection.requested`, `tab.selection.changed`, `tab.selection.failed`, `web_runtime.created`, `web_runtime.reused`, `web_runtime.rebuild.begin`, `web_runtime.rebuild.completed`, `web_runtime.released`, `web_runtime.content_process_terminated`, `web_runtime.recovery.reload_now`, `web_runtime.recovery.deferred`, `slot_lifecycle.activate`, `slot_lifecycle.deactivate`, `slot_lifecycle.inactive_plan.created`, `slot_lifecycle.inactive_plan.cancelled`, `slot_lifecycle.release`, `slot_lifecycle.memory_pressure`, `slot_lifecycle.media_protected`, `slot_lifecycle.attention_protected`, `slot_lifecycle.speech_protected`, `slot_lifecycle.hidden_active_grace`, `attention.transition`, `navigation.commit`, `navigation.failed`, and `web_content_process_terminated`.

- [ ] **Step 2: Run the focused tests and verify the event assertions fail**

Run: `xcodebuild -project FloatTabs.xcodeproj -scheme FloatTabs -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/FloatTabsDiagnosticsDerivedData -clonedSourcePackagesDirPath /private/tmp/FloatTabsBaselineSourcePackages CODE_SIGNING_ALLOWED=NO -only-testing:FloatTabsTests/RuntimeDiagnosticsInstrumentationTests -only-testing:FloatTabsTests/WebFocusAdapterTests -only-testing:FloatTabsTests/TabStoreTests -only-testing:FloatTabsTests/WebViewPoolTests test`

Expected: FAIL because the owners do not yet record the new events.

- [ ] **Step 3: Instrument FullscreenSourceHostController and preserve state authority**

Record state transitions, lock/unlock, restore begin/completed/timeout, rebuild required, Space reconciliation, order-front, and focus result. Include old/new state, existing `restoreGeneration`, window/display numbers, and visibility/key facts. Do not log watchdog ticks or change idle/entering/fullscreen/exiting/restoring transitions.

- [ ] **Step 4: Instrument WebFocusRouter and navigation with privacy-safe fields**

Record WebView changes, adapter recognition, captured voice target, presentation request/completion, toggle, failure, navigation commit/failure/process termination, and verbose-only provisional/finished/instant-back/fallback events. Never serialize DOM content or raw URL strings.

- [ ] **Step 5: Instrument TabStore, WebViewPool, and lifecycle**

Record only UUID transitions and existing lifecycle facts. Include `InactivePlan.token` as a diagnostic field when it is already available, never use the trace ID as a lifecycle token, and preserve resident/runtime recovery decisions exactly.

- [ ] **Step 6: Instrument WebAttentionCoordinator transitions**

Record `attention.transition` after the existing state map transition, with slot UUID, event, old state, new state, and `user_visible` when applicable. Do not add another attention map or observer authority.

- [ ] **Step 7: Run focused tests, then commit subsystem instrumentation**

Run the command from Step 2 and expect all focused tests to pass. Then run the existing critical regression classes: `AppCommandControllerTests`, `ScreenPositioningTests`, `WebAttentionCoordinatorTests`, `WebAttentionCrossFeatureTests`, `WebAttentionLifecycleTests`, `WebAttentionIndicatorTests`, `ExternalShellTests`, and `WebViewPoolTests`.

```bash
git add FloatTabs FloatTabsTests
git commit -m "feat: instrument runtime lifecycle diagnostics"
```

### Task 6: Add Diagnostics Settings and asynchronous recent export

**Files:**
- Create: `FloatTabs/UI/DiagnosticsSettingsViewController.swift`.
- Modify: `FloatTabs/UI/GlobalSettingsController.swift` to add one minimal Diagnostics tab/section.
- Modify: `FloatTabs/App/AppCoordinator.swift` to provide log-folder opening and export callbacks.
- Test: create `FloatTabsTests/DiagnosticsSettingsTests.swift` for mode presentation and injected actions.
- Modify: `FloatTabs.xcodeproj/project.pbxproj`.

**Interfaces:**
- `DiagnosticsSettingsViewController` takes `AppPreferencesStore`, `openLogsFolder: () -> Void`, and `exportRecentDiagnostics: (URL, @escaping (Result<Void, Error>) -> Void) -> Void`.
- The save panel is opened on MainActor; retained-event reading and destination writing run through the writer queue.

- [ ] **Step 1: Add failing settings tests**

Assert the controller displays `Off`, `Standard`, and `Verbose`, reflects the stored mode, invokes the injected open-folder action, and invokes the export handler with the chosen destination without touching real Application Support.

- [ ] **Step 2: Run settings tests and verify they fail**

Run: `xcodebuild -project FloatTabs.xcodeproj -scheme FloatTabs -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/FloatTabsDiagnosticsDerivedData -clonedSourcePackagesDirPath /private/tmp/FloatTabsBaselineSourcePackages CODE_SIGNING_ALLOWED=NO -only-testing:FloatTabsTests/DiagnosticsSettingsTests test`

Expected: FAIL because the Diagnostics settings controller and Global Settings tab do not exist.

- [ ] **Step 3: Implement the minimal UI and callbacks**

Add one `Diagnostics` tab using the existing AppKit stack/document style. Add the logging popup, `Open Logs Folder`, and `Export Recent Diagnostics…` buttons. Show success/failure alerts without logging raw destination paths or error userInfo.

- [ ] **Step 4: Run settings tests and commit**

Run the command from Step 2 and expect PASS.

```bash
git add FloatTabs/UI FloatTabs/App/AppCoordinator.swift FloatTabsTests/DiagnosticsSettingsTests.swift FloatTabs.xcodeproj/project.pbxproj
git commit -m "feat: add diagnostics settings and export"
```

### Task 7: Full validation, self-audit, push, and Draft PR

**Files:**
- Modify only files required by failing validation or audit findings.
- Verify: `docs/product/FloatTabs_Runtime_Diagnostics_Contract_V1.md` describes the final behavior.

**Interfaces:**
- No new production interface is introduced in this task; this task proves the earlier contract and records limitations.

- [ ] **Step 1: Run the full XCTest suite**

Run:

```bash
xcodebuild -project FloatTabs.xcodeproj -scheme FloatTabs -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/FloatTabsDiagnosticsDerivedData -clonedSourcePackagesDirPath /private/tmp/FloatTabsBaselineSourcePackages -resultBundlePath /private/tmp/FloatTabsDiagnosticsTests.xcresult CODE_SIGNING_ALLOWED=NO test
```

Expected: all existing and new XCTest cases pass; report the exact executed count and failures.

- [ ] **Step 2: Run Debug and Release arm64 builds**

Run:

```bash
xcodebuild -project FloatTabs.xcodeproj -scheme FloatTabs -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/FloatTabsDiagnosticsDerivedData -clonedSourcePackagesDirPath /private/tmp/FloatTabsBaselineSourcePackages CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FloatTabs.xcodeproj -scheme FloatTabs -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/FloatTabsDiagnosticsDerivedData -clonedSourcePackagesDirPath /private/tmp/FloatTabsBaselineSourcePackages CODE_SIGNING_ALLOWED=NO build
```

Expected: both commands exit 0 and Release contains no new benchmark/network listener outside existing `#if DEBUG` code.

- [ ] **Step 3: Run static privacy and authority audits**

Run:

```bash
rg -n "print\\(|NSLog\\(|Logger\\(|absoluteString|window\.title|Cookie|Authorization|token|userInfo|innerHTML|textContent|inputValue|textarea|mouseMoved|mouseDragged|DispatchQueue\.sync|FileHandle|write\(" FloatTabs FloatTabsTests
git diff --check
git status --short
```

Review each result manually. Confirm all new persistent paths go through `RuntimeDiagnosticPrivacy`, no MainActor file write/rotation exists, no high-frequency event was added, no trace is stored as business state, and no retain cycle exists between diagnostics, writer, and AppCoordinator.

- [ ] **Step 4: Run available real-Mac acceptance and report unavailable cases honestly**

Attempt ordinary desktop summon/input/hide/restore, fullscreen third-party app, multi-Space, cross-display skip, menu-bar summon, global hotkey, external voice focus, tab switch, and WebKit fullscreen enter/exit. If the environment cannot provide reliable UI control, report `MANUAL REAL-MAC REQUIRED` with this exact checklist and do not claim PASS.

- [ ] **Step 5: Review final diff and commit audit fixes**

Run `git diff origin/main...HEAD --stat`, `git diff origin/main...HEAD -- FloatTabs/Diagnostics FloatTabs/App FloatTabs/Panel FloatTabs/Web FloatTabs/Tabs FloatTabs/UI FloatTabs/Persistence FloatTabsTests`, and `git log --oneline origin/main..HEAD`. Commit any audit fixes with a focused message and rerun the affected tests.

- [ ] **Step 6: Push the branch and create the Draft PR**

Run:

```bash
git push -u origin codex/runtime-diagnostics-v1
gh pr create --draft --base main --head codex/runtime-diagnostics-v1 --title "feat: add Runtime Diagnostics V1" --body-file /private/tmp/FloatTabs-runtime-diagnostics-pr.md
```

The PR body must include the contract summary, tests/build results, privacy audit, MainActor I/O audit, manual acceptance status, and known limitations. Do not merge and do not mark Ready.

- [ ] **Step 7: Final verification before reporting**

Run `git status --short --branch`, `git rev-parse HEAD`, `git rev-parse origin/main`, `gh pr view --json number,state,isDraft,headRefName,baseRefName,url`, and the full XCTest/build commands again if the final audit changed source. Report `BASELINE_HEAD`, `NEW_HEAD`, `REMOTE_HEAD`, `BRANCH`, `PR_NUMBER`, `PR_STATE`, all changed files, architecture, schema/mode/storage/rotation/retention, instrumentation, trace roots, privacy/MainActor/high-frequency/authority audits, test/build results, real-Mac status, limitations, and the eight final verdict questions from the request.
