# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 2 READY / UNREAD DECOUPLING**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `ACTIVE / PHASE 2 IMPLEMENTATION — WAITING FOR INDEPENDENT WEB AUDIT`.

Phase 1 Safe Hibernate + Restore is complete. Phase 2 decouples transient Runtime `ready` state from durable unread truth so completed unseen work can remain unread after its `WKWebView` Runtime is reclaimed.

## Canonical / current state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PHASE_1_SAFE_HIBERNATE_RESTORE=COMPLETE
PHASE_2_FOCUSED_READ_ONLY_AUDIT=COMPLETE
PHASE_2_PLAN_V1=SUPERSEDED_FOR_CURRENT_EXECUTION
PHASE_2_PLAN_V2=ACCEPTED_FROZEN
PHASE_2_IMPLEMENTATION=ACTIVE
PHASE_2_SCOPE_RECONCILIATION_001=ACCEPTED_TEST_ONLY
PHASE_2_MACHINE_VERIFICATION=LOCAL_TESTS/BUILDS/SCOPE PASS; REQUIRED_CI PASS
PHASE_2_REAL_UI_RUNTIME_ACCEPTANCE=USER_OWNED / DEFERRED UNTIL MACHINE WORK + AUDIT COMPLETE
PHASE_3=NOT_STARTED / NOT_AUTHORIZED
PHASE_4=NOT_STARTED / NOT_AUTHORIZED
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
```

## Current Authority

Read in this order:

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ docs/README.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V2.md
→ docs/architecture/FT_RUNTIME_LIFECYCLE_PHASE2_SCOPE_RECONCILIATION_001.md
→ docs/architecture/DOMAIN_MAP.md
→ current source/tests/fresh evidence
```

Phase 2 V1 remains historical evidence for the original audit and verification rationale. V2 changes only the acceptance cadence, not architecture semantics or production scope.

## Frozen Phase 2 semantic target

```text
Runtime Attention:
  idle       -> not residency-protected
  generating -> residency-protected
  ready      -> transient only; NOT residency-protected

Durable Unread:
  ChatGPTUnreadResponseCoordinator + UnreadResponseStore
  -> survives hibernate/runtimeReset/recreation/relaunch
  -> canonical source for persistent rail/menu unread presentation
```

A valid hidden completion must keep this ordering:

```text
Generating
→ transient Ready
→ durable unread commit
→ durable unread presentation sync
→ protection-ended lifecycle restart
→ existing policy may later hibernate Runtime
```

Durable unread commit must precede reclaim.

## Authorized scope

Production:

- `FloatTabs/Web/WebAttentionCoordinator.swift`
- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/App/AppCoordinator.swift`
- `FloatTabs/MenuBar/StatusItemController.swift`

Tests:

- `FloatTabsTests/WebAttentionCoordinatorTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebAttentionCrossFeatureTests.swift`
- `FloatTabsTests/WebAttentionPresentationTests.swift`
- `FloatTabsTests/UnreadResponseTests.swift` only if narrowly needed
- `FloatTabsTests/BrowserProfileDuplicateTests.swift` only for the accepted stale Ready-protection assertion corrective

No Browser Profile production code, unread persistence schema, lifecycle timer/policy, WebViewPool, detector/bridge, Phase 3/4 or release expansion is authorized.

## Current implementation evidence

The current local implementation workspace reports:

```text
AUTHORIZED_DIRTY_FILES=9
AFFECTED_BROWSER_PROFILE_TEST=1 executed / 0 failures
FOCUSED_TESTS=241 executed / 3 skipped / 0 failures
FULL_XCTEST=1073 executed / 3 skipped / 0 failures
DEBUG_BUILD=PASS
RELEASE_BUILD=PASS
LIVE_SMOKE_FIRST_ATTEMPT=VISIBLE_COMPLETION / NOT A PRODUCT FAILURE
FRESH_ORIGIN_MAIN=36d5850a9a5bad01b24cffa9a4bd1e1fbf628d4d
IMPLEMENTATION_BRANCH=codex/ft-runtime-lifecycle-memory-001-phase2-implement-001
IMPLEMENTATION_SCOPE_AUDIT=PASS / 9 AUTHORIZED IMPLEMENTATION-TEST FILES
REQUIRED_CI_JOB=Build & Test (Apple Silicon arm64)
REQUIRED_CI_RUNNER=macmini-floattabs-01
REQUIRED_CI=PASS ON FINAL LITERAL PR HEAD
```

The previous CUA-driven smoke completed while the ChatGPT Slot was still visible, so durable unread was correctly skipped. Under Phase 2 V2 this is not a construction STOP and is not retried by the local executor. Timing-sensitive runtime/UI acceptance remains user-owned.

## Verification / acceptance cadence

Machine construction gates:

1. focused tests PASS;
2. full XCTest PASS;
3. Debug arm64 build PASS;
4. Release arm64 build PASS;
5. exact diff/scope/data-safety review PASS;
6. implementation commit/push/one PR;
7. literal-head required CI PASS on `macmini-floattabs-01`;
8. independent web audit PASS.

After required CI, stop at:

`WAITING_FOR_INDEPENDENT_WEB_AUDIT`

After independent web audit, stop at:

`WAITING_FOR_HUMAN_UI_ACCEPTANCE`

Timing-sensitive ChatGPT interaction/runtime acceptance is performed by the user in one concentrated pass. Local AI/CUA must not be used as the final acceptance operator.

Minimum human acceptance includes hidden completion → durable unread → normal Runtime reclaim → unread survives → restore/session continuity → acknowledgement, plus no obvious focus/fullscreen regression.

## Explicit non-scope

Do not modify without STOP/reconciliation:

- ChatGPT detector/Attention bridge/response bridge/extraction semantics;
- `ChatGPTUnreadResponseCoordinator` / `UnreadResponseStore` behavior/schema;
- `SlotLifecycleCoordinator` timing/policy;
- `WebViewPool` hibernate/restore semantics;
- Browser Profile/session/configuration production behavior;
- Attention visual styles;
- native completion notifications (Phase 3);
- Runtime Budget/ranking/scale benchmark (Phase 4);
- release/version metadata.

## Next action

The nine authorized local implementation/test changes are aligned with fresh Authority, committed, pushed, and covered by required CI run `41261953797` on `macmini-floattabs-01` at literal head `3c15c3555ca5c25bc88f0d592b9cbec89693993a`. Do not retry CUA/live-smoke automation. Stop for independent web audit; after the audit, hand the build to the user for concentrated human acceptance.
