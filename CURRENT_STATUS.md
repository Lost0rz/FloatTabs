# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 2 READY / UNREAD DECOUPLING**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `ACTIVE / PHASE 2 IMPLEMENTATION — TEST-SCOPE CORRECTIVE AUTHORIZED`.

Phase 1 Safe Hibernate + Restore is complete. Phase 2 now decouples transient Runtime `ready` state from durable unread truth so a completed unseen response can remain unread after its `WKWebView` Runtime is reclaimed.

## Canonical / current state

```text
PHASE_2_AUDIT_BASELINE=e61b932ae88460232eeb39b1538797c0b7f65359
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN
JSC_CRASH_ELIMINATED=NOT_CLAIMED

ACTIVE_PROGRAM=FT-RUNTIME-LIFECYCLE-MEMORY-001
PHASE_0_CONTRACT_FREEZE=COMPLETE
HISTORICAL_DOC_GATE=COMPLETE
PHASE_1_SAFE_HIBERNATE_RESTORE=COMPLETE
PHASE_1_MERGE_COMMIT=188c524fd02e1c31b8a152b2bec224c947526610
PHASE_2_FOCUSED_READ_ONLY_AUDIT=COMPLETE
PHASE_2_PLAN=ACCEPTED_FROZEN
PHASE_2_IMPLEMENTATION=AUTHORIZED
PHASE_2_SCOPE_RECONCILIATION_001=ACCEPTED_TEST_ONLY
PHASE_3=NOT_STARTED / NOT_AUTHORIZED
PHASE_4=NOT_STARTED / NOT_AUTHORIZED
STRICT_SCALE_BENCHMARK=DEFERRED_TO_PHASE_4
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
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V1.md
→ docs/architecture/FT_RUNTIME_LIFECYCLE_PHASE2_SCOPE_RECONCILIATION_001.md
→ docs/architecture/DOMAIN_MAP.md
→ current source/tests/fresh evidence
```

Phase 1 plans remain accepted historical Phase 1 evidence. They do not override the current Phase 2 plan.

## Phase 2 audit conclusion

Fresh read-only audit found that durable unread already has a separate canonical owner:

```text
ChatGPTUnreadResponseCoordinator
→ UnreadResponseStore
→ durable unread Slot IDs / response identity
```

Current Runtime Attention is separately owned by `WebAttentionCoordinator`, but `.ready` currently participates in `isAttentionProtected`, so an inactive hidden completion can remain resident indefinitely after its prior release timer was skipped while Generating.

The second coupling is presentation: the rail already renders durable unread, while the menu/status badge still counts transient `readySlotIDs` and can disappear after Runtime reset even when durable unread remains.

No new persistence schema, detector rewrite, WebView lifecycle redesign or notification mechanism is required.

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
→ existing Warm/Cold policy may later hibernate Runtime
```

The durable unread commit must happen before lifecycle reclaim resumes.

## Authorized production scope

Phase 2 implementation is bounded to:

- `FloatTabs/Web/WebAttentionCoordinator.swift`
- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/App/AppCoordinator.swift`
- `FloatTabs/MenuBar/StatusItemController.swift`

Expected test scope:

- `FloatTabsTests/WebAttentionCoordinatorTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebAttentionCrossFeatureTests.swift`
- `FloatTabsTests/WebAttentionPresentationTests.swift`
- `FloatTabsTests/UnreadResponseTests.swift` only for narrowly necessary durable-survival regression coverage
- `FloatTabsTests/BrowserProfileDuplicateTests.swift` only for the reconciled stale Ready-protection cross-domain regression assertion described in `FT_RUNTIME_LIFECYCLE_PHASE2_SCOPE_RECONCILIATION_001.md`

The exact contract, test matrix and STOP conditions are frozen in the Phase 2 plan plus the accepted test-only scope reconciliation.

## Phase 2 scope reconciliation 001

The first construction attempt remained inside the original frozen scope and passed focused Phase 2 coverage (`241 executed / 3 skipped / 0 failures`). Full XCTest then stopped on one assertion in `BrowserProfileDuplicateTests.swift` that still encoded the historical expectation that transient Ready is Runtime-protected.

Read-only reconciliation confirmed:

- Browser Profile duplication production behavior is not implicated;
- the affected test still correctly verifies that duplication leaves the source WebView, Attention bridge, Browser Profile identity, transient Ready state and residency untouched;
- only the assertion that Ready is Attention-protected conflicts with the already-frozen Phase 2 semantic;
- the adjacent protected-source duplication case uses `Generating`, whose protection remains required.

Therefore only `FloatTabsTests/BrowserProfileDuplicateTests.swift` is added to the authorized test scope. No Browser Profile production file, persistence/schema, lifecycle timer, WebViewPool, detector/bridge or unread-store expansion is authorized.

## Explicit non-scope

Do not modify without STOP/reconciliation:

- ChatGPT generation detector/Attention bridge/response bridge/extraction semantics;
- `ChatGPTUnreadResponseCoordinator` or `UnreadResponseStore` persistence schema/behavior;
- `SlotLifecycleCoordinator` timing/policy;
- `WebViewPool` hibernate/restore semantics;
- Browser Profile/session/configuration production behavior or persistence;
- Attention visual renderer/styles;
- native completion notifications (Phase 3);
- Runtime Budget/ranking or strict scale benchmark (Phase 4);
- release/version bump.

## Verification / acceptance gate

Before merge Phase 2 must prove:

1. Generating remains protected.
2. Ready is no longer Runtime-protected.
3. durable unread is committed before protection-ended lifecycle restart;
4. inactive unread Slot can hibernate under existing policy without losing unread;
5. runtimeReset/fresh Runtime recreation does not clear unread;
6. menu/status presentation uses durable unread and survives transient Ready reset;
7. acknowledgement/response-identity semantics remain unchanged;
8. active/fullscreen/supplemental-visible/media protections remain unchanged;
9. focused Phase 2 tests pass;
10. full XCTest passes;
11. Debug and Release arm64 builds pass;
12. bounded real-runtime smoke passes;
13. required exact-head GitHub CI passes on the dedicated self-hosted runner;
14. independent web audit passes;
15. `HUMAN_UI_ACCEPTANCE=PASS` from the user.

Automated UI evidence cannot replace the human acceptance gate.

## STOP conditions

Stop and reconcile if durable unread can be lost by Runtime reclamation, reclaim can begin before durable unread commit, Generating becomes reclaimable, implementation requires detector/persistence/lifecycle/WebView scope expansion, Browser Profile/session production behavior or data must change, Phase 3/4 work leaks in, required tests/build/CI fail after authorized stale-test reconciliation, human acceptance fails, or overlapping unique work appears.

## Next action

Resume the same Phase 2 implementation branch/workspace. Make only the authorized test-only correction in `BrowserProfileDuplicateTests.swift`, then continue the existing verification sequence. Do not discard the eight already-authorized uncommitted implementation files. Do not merge or release from the construction step. Stop after machine verification at `WAITING_FOR_INDEPENDENT_WEB_AUDIT` (or `WAITING_FOR_HUMAN_UI_ACCEPTANCE` when that is the only remaining gate).

## Non-claims

- Historical JSC root cause remains `UNKNOWN`.
- Phase 2 does not claim a final Runtime memory budget.
- Phase 2 does not add native completion notifications.
- No release newer than v0.5.8 is authorized by this task.