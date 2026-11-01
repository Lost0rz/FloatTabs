# FloatTabs Runtime Lifecycle — Phase 5 Background Generation Thrift Plan V1

**Status:** `ACTIVE / ACCEPTED / FROZEN FOR PHASE 5 EXECUTION`  
**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Program contract:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V4.md`

## 1. Objective

Reduce FloatTabs-owned work during long-running background ChatGPT generation while preserving provider generation, Attention correctness, Runtime protection and Browser Profile/session data.

Phase 5 is intentionally narrower than a generic WebView background scheduler. It optimizes FloatTabs' own ChatGPT liveness fallback only.

## 2. Focused audit findings

### 2.1 Generation ownership and protection are already correct

`WebAttentionCoordinator` owns the native Attention state map. Only `.generating` is Attention-protected. `SlotLifecycleCoordinator` receives that fact through a read-only query and protects Generating Runtime from automatic hibernate.

Phase 5 must not move either ownership boundary.

### 2.2 Product visibility and page visibility are different facts

`PanelController.isAttentionUserVisible(slotID:)` is derived from actual FloatTabs presentation topology and remains authoritative for user-visible completion semantics.

`document.visibilityState` describes the current Web document and is useful as a local scheduling hint inside the bridge. It must never become canonical product visibility, unread acknowledgement truth or lifecycle policy.

### 2.3 The primary detector is already thrift-oriented

The injected ChatGPT detector is event-driven through `MutationObserver`, uses trailing coalescing, and intentionally excludes `characterData` so streamed token text does not itself produce observer pressure.

Rewriting this detector into periodic polling would be a regression. Phase 5 leaves its primary detection semantics unchanged.

### 2.4 The fixed native watchdog is the bounded optimization target

On `generationStarted`, `ChatGPTAttentionBridge` starts a native watchdog. Current behavior sleeps for a fixed 2 seconds and performs a small isolated-world liveness probe; if that probe says generation ended, it waits 250ms and requires a second false probe before synthesizing `generationFinished`.

The watchdog is a recovery safety net for missed natural completion. It can therefore be less frequent for a long-running hidden document without suspending the provider page.

## 3. Frozen design

### 3.1 Scheduling metadata

Extend the read-only liveness probe result with current `document.visibilityState`.

This value is consumed only by the bridge's watchdog-cadence selector.

Compatibility rule: if visibility metadata is missing, invalid or unknown, treat the probe as **not eligible for background thrift** and keep the 2s cadence.

### 3.2 Cadence policy

Use a small pure decision function inside `ChatGPTAttentionBridge`:

```text
Inputs:
- generation elapsed time
- most recent liveness-probe page visibility hint

Output:
- next watchdog sleep interval
```

Initial values:

```text
BASE_INTERVAL = 2 seconds
LONG_RUNNING_THRESHOLD = 30 seconds
HIDDEN_LONG_RUNNING_INTERVAL = 5 seconds
```

Decision:

```text
if visibility != hidden:
    2s
else if elapsed < 30s:
    2s
else:
    5s
```

The first watchdog cycle remains 2s because no probe-derived page visibility hint exists yet.

### 3.3 Completion safety remains unchanged

The cadence selector changes only time between fallback cycles.

When a fallback probe reports `generating=false`, Phase 5 keeps the existing sequence:

```text
first false current probe
→ 250ms confirmation delay
→ second false current probe
→ generationFinished
```

All existing current-document token, semantic generation, physical-runtime epoch, watchdog generation, WebView identity, timeout and stale-callback guards remain required.

### 3.4 Natural completion dominates

Natural bridge completion continues to call `stopLivenessWatchdog()` immediately. A later scheduled callback must not reopen or duplicate completion.

## 4. Authorized source scope

Production:

- `FloatTabs/Web/ChatGPTAttentionBridge.swift`

Tests:

- `FloatTabsTests/ChatGPTAttentionBridgeTests.swift`

Control/documentation:

- `CURRENT_STATUS.md`
- `CURRENT_TASK.md`
- `docs/README.md`
- `docs/architecture/README.md`
- `docs/architecture/DOMAIN_MAP.md`
- current V4 contract / this Phase 5 plan

No `WebViewPool`, `SlotLifecycleCoordinator`, persistence, Browser Profile, settings UI or release/version mutation is expected.

## 5. Required focused tests

Add/adjust tests proving:

1. cadence decision returns 2s for visible metadata at any elapsed time;
2. cadence decision returns 2s for unknown/missing metadata;
3. hidden metadata before 30s remains 2s;
4. hidden metadata at/after 30s returns 5s;
5. installed liveness probe exposes visibility metadata without page content;
6. true hidden probe updates only scheduling metadata and does not emit Attention transitions;
7. false→false still emits exactly one finish and stops watchdog;
8. false→true still does not finish;
9. natural finish remains single emission;
10. Runtime/document replacement and stale callbacks remain harmless.

Existing bridge/lifecycle/cross-feature tests remain regression gates.

## 6. Diagnostics

Diagnostics may report the chosen watchdog cadence/phase using bounded metadata such as:

- base interval;
- long-running threshold;
- hidden long-running interval;
- selected next interval;
- whether the last probe classified the document as hidden.

Do not log URLs, prompt/response content, DOM text or other page content for this feature.

Diagnostics must not drive the decision.

## 7. Acceptance gates

Before merge:

- focused Phase 5 tests PASS;
- full existing XCTest PASS;
- Debug arm64 PASS;
- Release arm64 PASS;
- exact diff/scope/data-safety audit PASS;
- no new lifecycle/Attention writer;
- literal-head `Build & Test (Apple Silicon arm64)` PASS on `macmini-floattabs-01`.

No separate human UI acceptance or formal independent program audit is required for this intermediate structural phase under Contract V4.

## 8. Explicit non-scope

- pausing/suspending/cancelling ChatGPT generation;
- automatic hibernate of Generating Runtime;
- changing Hot/Warm/Cold policy;
- Phase 4 performance-settings UI;
- Phase 6 restore/perceived-speed work;
- Browser Profile/session/persistence changes;
- page-detector architecture rewrite;
- general browser background-tab freezing;
- exact per-Slot memory attribution;
- private WebKit APIs;
- release/version bump.

## 9. STOP conditions

STOP and reconcile if Phase 5 requires:

- product visibility truth to move from Panel/presentation ownership into page JavaScript;
- lifecycle mutation from the bridge;
- weakened Generating protection;
- provider-generation control;
- `WebViewPool` hibernate/restore contract changes;
- persistence/schema/data deletion;
- broad site-specific detector rewrite unrelated to the cadence target;
- Phase 6 work.
