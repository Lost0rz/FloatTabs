# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 5 long-running background generation thrift  
**Status:** `ACTIVE / PHASE_5_AUDIT_AND_IMPLEMENTATION`  
**Mode:** `AUDIT → DESIGN FREEZE → IMPLEMENT → VERIFY`  
**Task class:** `WEB RUNTIME / ATTENTION OBSERVATION THRIFT`  
**JSC root cause:** `UNKNOWN`

## Authorization

The user authorized Phase 5 remote execution on 2026-11-01 after Phase 4 merged.

This task first reconciles stale Runtime Lifecycle documentation, then implements the smallest Phase 5 change that reduces **FloatTabs-owned** work during long-running background ChatGPT generation without interrupting provider generation or weakening Runtime/data-safety boundaries.

## Verified Phase 5 audit baseline

Current production facts:

- `WebAttentionCoordinator` is the sole Attention state authority; only `generating` is Runtime-protecting.
- `SlotLifecycleCoordinator` consumes that read-only protection and must continue to protect Generating Runtime from automatic hibernate.
- `PanelController` remains the authoritative product/presentation visibility owner.
- `WebViewPool` owns the `ChatGPTAttentionBridge` lifetime together with each live Runtime.
- `ChatGPTAttentionBridge` starts a native liveness watchdog on `generationStarted` and currently probes the current WebKit document every **2 seconds** until completion/reset.
- the page detector is already event-driven, coalesces DOM mutation work, and intentionally excludes token-stream `characterData`; Phase 5 does not replace that detector with polling.
- the liveness watchdog is a completion-recovery safety net; the ordinary page detector remains the primary generation-state sensor.

## Selected Phase 5 design

### Product invariant

`generating` remains Runtime-protected for the entire generation. Phase 5 must **not**:

- hibernate/release/reload a Generating Runtime;
- pause, suspend, cancel or otherwise control the provider generation;
- change Browser Profile/session/persistence semantics;
- use private WebKit APIs;
- make Diagnostics a product-state owner.

### Thrift mechanism

Reduce only the native liveness-watchdog fallback frequency for a long-running **page-hidden** generation.

Use the ChatGPT document's `document.visibilityState` only as a **local bridge scheduling hint**. It is not canonical product visibility and must not replace `PanelController` presentation truth.

Initial conservative policy:

```text
page visible / unknown
→ watchdog interval 2s

page hidden + generation age < 30s
→ watchdog interval 2s

page hidden + generation age >= 30s
→ watchdog interval 5s

any probe reports not-generating
→ keep existing 250ms second confirmation
→ only two current-epoch false probes may emit generationFinished
```

The 30s / 5s values are initial engineering defaults, not measured optimum. Later Settings-backed performance tuning may revise them under a separate task.

### Scope

Authorized product paths are bounded to:

- `FloatTabs/Web/ChatGPTAttentionBridge.swift`;
- focused tests in `FloatTabsTests/ChatGPTAttentionBridgeTests.swift`;
- task/control and architecture-routing documents needed for Phase 5 authority alignment.

A narrowly required project-file change is allowed only if source/test membership actually requires it.

## Acceptance / verification

Phase 5 must prove:

1. Generating remains Attention-protected and is never hibernated by the thrift mechanism.
2. foreground/visible or unknown document state keeps the existing 2s watchdog cadence.
3. hidden generation does not back off before the 30s long-running threshold.
4. hidden generation at/after the threshold selects the 5s cadence.
5. page visibility is scheduling metadata only; no product visibility or lifecycle writer moves into the bridge.
6. false→false completion confirmation remains 250ms and preserves current epoch/token/stale-callback guards.
7. natural completion still stops the watchdog immediately and emits no duplicate completion.
8. Runtime replacement/invalidation cancels old watchdog work and late callbacks remain harmless.
9. existing full XCTest, Debug arm64 and Release arm64 builds pass.
10. literal PR head passes required `Build & Test (Apple Silicon arm64)` on `macmini-floattabs-01`.
11. no Browser Profile/session/configuration/user-data mutation is introduced.

## STOP conditions

STOP/reconcile if implementation would require:

- changing `WebViewPool` hibernate/restore semantics;
- a second Runtime lifecycle or Attention-state writer;
- using logical active state as canonical physical visibility;
- provider-generation pause/cancel semantics;
- private WebKit API;
- persistence/schema migration;
- user-data reset/delete;
- Phase 6 perceived-fast restore work;
- release/version work.

## Delivery boundary

Remote implementation may proceed on the single Phase 5 branch/PR after this authority reconciliation. Do not merge Phase 5 or begin Phase 6 without the next merge decision unless the user explicitly authorizes it.