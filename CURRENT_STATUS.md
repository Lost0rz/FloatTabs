# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — ARCHITECTURE-FIRST EXECUTION**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `ACTIVE / PHASE 2 IMPLEMENTATION — MACHINE VERIFIED / MERGE-READY AFTER LITERAL-HEAD CI`.

Phase 1 Safe Hibernate + Restore is complete. Phase 2 decouples transient Runtime `ready` state from durable unread truth so completed unseen work can remain unread after its `WKWebView` Runtime is reclaimed.

The program now uses V3 cadence: finish the remaining architecture sequence with phase-local machine verification and CI, then run one unified independent audit across the integrated final architecture, then one user-owned full human acceptance pass.

## Canonical / current state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PROGRAM_CONTRACT_V2=SUPERSEDED_FOR_CURRENT_EXECUTION
PROGRAM_CONTRACT_V3=ACCEPTED_FROZEN
PROGRAM_UNIFIED_INDEPENDENT_AUDIT=DEFERRED_UNTIL_PHASES_1_6_COMPLETE
PROGRAM_HUMAN_ACCEPTANCE=PENDING / DEFERRED_UNTIL_UNIFIED_AUDIT_PASS

PHASE_1_SAFE_HIBERNATE_RESTORE=COMPLETE
PHASE_2_FOCUSED_READ_ONLY_AUDIT=COMPLETE
PHASE_2_PLAN_V1=SUPERSEDED_FOR_CURRENT_EXECUTION
PHASE_2_PLAN_V2=ACCEPTED_FOR_PHASE_2_SEMANTICS / ACCEPTANCE_CADENCE_SUPERSEDED_BY_PROGRAM_V3
PHASE_2_IMPLEMENTATION=MACHINE_VERIFIED / PR_176_OPEN
PHASE_2_SCOPE_RECONCILIATION_001=ACCEPTED_TEST_ONLY
PHASE_2_MACHINE_VERIFICATION=TARGETED/FOCUSED/FULL TESTS + DEBUG/RELEASE + SCOPE PASS
PHASE_2_MENU_UNREAD_PROJECTION_CORRECTIVE=IMPLEMENTED / TARGETED REGRESSION PASS
PHASE_2_PRIOR_INDEPENDENT_AUDIT=PASS ON PRE-V3 SEMANTIC PRODUCT HEAD / EXTRA EVIDENCE ONLY
PHASE_2_HUMAN_ACCEPTANCE=DEFERRED_TO_PROGRAM_FINAL
PHASE_3=NOT_STARTED / NOT_AUTHORIZED
PHASE_4=NOT_STARTED / NOT_AUTHORIZED
PHASE_5=NOT_STARTED / NOT_AUTHORIZED
PHASE_6=NOT_STARTED / NOT_AUTHORIZED
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
```

## Current Authority

Read in this order:

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ docs/README.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Phase2_Ready_Unread_Decoupling_Plan_V2.md
→ docs/architecture/FT_RUNTIME_LIFECYCLE_PHASE2_SCOPE_RECONCILIATION_001.md
→ docs/architecture/DOMAIN_MAP.md
→ current source/tests/fresh evidence
```

Program Contract V3 supersedes V2 for current execution cadence. Phase 2 Plan V2 remains the accepted bounded semantic/implementation reference for Ready / Unread decoupling, but any per-phase independent-audit or human-acceptance requirement in older material yields to Program Contract V3.

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

## Authorized Phase 2 scope

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

No Browser Profile production code, unread persistence schema, lifecycle timer/policy, WebViewPool, detector/bridge, Phase 3+ product expansion or release expansion is authorized inside Phase 2.

## Phase 2 implementation evidence

```text
AFFECTED_BROWSER_PROFILE_TEST=1 executed / 0 failures
TARGETED_MENU_UNREAD_REGRESSION=4 executed / 0 failures
FOCUSED_TESTS=241 executed / 3 skipped / 0 failures
FULL_XCTEST=1073 executed / 3 skipped / 0 failures
DEBUG_BUILD=PASS
RELEASE_BUILD=PASS
IMPLEMENTATION_SCOPE_AUDIT=PASS / 11 AUTHORIZED PR PATHS INCLUDING STATUS/TASK
PRE_V3_LITERAL_HEAD=654eaef06b8c9e919a47bbe3842866033d9b69ea
PRE_V3_REQUIRED_CI_RUN=41263638003 / PASS
PRE_V3_QA_DMG_RUN=41263637956 / PASS
```

The V3 Authority update is control/docs-only. It does not change the previously audited product/test blobs. The final literal #176 head must still pass the required self-hosted CI before merge because repository-host gates apply to the current PR identity.

## Verification / acceptance cadence

Per-phase merge gates under Program Contract V3:

1. frozen scope/ownership/STOP boundary;
2. focused tests PASS;
3. full XCTest PASS;
4. Debug arm64 build PASS;
5. Release arm64 build PASS;
6. exact diff/scope/data-safety review PASS;
7. phase-specific machine decision evidence when required by that phase;
8. literal-head required CI PASS on `macmini-floattabs-01`;
9. merge and continue to the next architecture phase after normal control alignment.

Not required as routine intermediate-phase blockers:

- per-phase human UI/runtime acceptance;
- per-phase AI/CUA live smoke;
- per-phase formal independent web audit.

After Phases 1–6 are structurally complete and merged:

```text
UNIFIED_PROGRAM_INDEPENDENT_AUDIT
→ corrective work if needed
→ AUDIT PASS
→ ONE USER-OWNED FULL HUMAN ACCEPTANCE PASS
→ final program closeout / release decision
```

Phase 4 remains responsible for the scale/performance benchmark evidence needed to choose the Runtime Budget/policy; that machine evidence is not deferred because it directly determines the architecture decision.

## Explicit Phase 2 non-scope

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

Do not perform Phase 2 human acceptance now. Keep PR #176 product semantics unchanged, allow the V3 Authority/docs-only update to obtain its literal-head required CI, then merge #176. After merge, begin Phase 3 with the normal focused read-only audit → scope freeze → construction sequence. Continue the architecture program through Phase 6 before the unified independent audit and final human acceptance.