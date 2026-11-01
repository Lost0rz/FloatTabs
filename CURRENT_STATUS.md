# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 6 PERCEIVED-FAST RESTORE**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `PHASE_6_EXECUTION_ACTIVE / WP0_GATE0_OUTCOME_A_COMPLETE / PRODUCT_MUTATION_RELEASED / WP1_ACTIVE`.

## Canonical state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PHASE_1_SAFE_HIBERNATE_RESTORE=COMPLETE / MERGED
PHASE_2_READY_UNREAD_DECOUPLING=COMPLETE / MERGED
PHASE_3_NATIVE_COMPLETION_NOTIFICATION=COMPLETE / MERGED
PHASE_4_REFERENCE_DERIVED_RUNTIME_MANAGEMENT=COMPLETE / MERGED
PHASE_5_BACKGROUND_GENERATION_THRIFT=COMPLETE / MERGED
PHASE_5_PR=#183
PHASE_5_MERGE_COMMIT=745d401bf9f282d19bc756c81be3f46f17161e4b
PHASE_5_LITERAL_HEAD=f9cef25f8eee47d9973bfd9bd9401af072b1b8e6
PHASE_5_REQUIRED_CI=PASS / RUN 1290
PHASE_5_QA_DMG=PASS / RUN 626

PHASE_6_AUDIT=COMPLETE
PHASE_6_AUDIT_RECORD=FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md
PHASE_6_CONTRACT=ACCEPTED / FROZEN
PHASE_6_CONTRACT_RECORD=FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md
PHASE_6_RECOMMENDATION=TWO-STAGE NATIVE RESTORE SHELL
PHASE_6_EXECUTION_START=AUTHORIZED BY USER / 2026-11-01
PHASE_6_GATE0=COMPLETE / OUTCOME_A / NAVIGATION_BACKED_READINESS
PHASE_6_GATE0_CORROBORATION=BOUNDED_CURRENT_RUNTIME_LIVENESS_SUCCESS
PHASE_6_IMPLEMENTATION=WP1 ACTIVE
PHASE_6_PRODUCT_MUTATION=RELEASED BY GATE0 OUTCOME_A
PHASE_6_NEXT_USER_START_REQUIRED=NO
TASK_RECONCILIATION_REQUIRED=NO
PROGRAM_HUMAN_ACCEPTANCE=PENDING
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
```

## Phase 6 frozen implementation direction

The accepted/frozen Phase 6 architecture remains:

```text
selected/summoned reclaimed Slot
→ native FloatTabs shell + lightweight restoring state immediately
→ return to AppKit run loop
→ revalidate current materialization request
→ existing WebViewPool creates/restores fresh WKWebView
→ attach fresh Runtime under restoring state
→ current-Runtime public readiness evidence
→ remove restoring state
→ existing focus/input ownership resumes
```

The resident Slot fast path remains direct and does not pass through restoring UI.

## Gate 0 result

WP0 / Gate 0 completed on a Real Mac using an actually hibernated existing ChatGPT Slot. The verification made no source changes and restored the temporary product state afterward.

Observed compatible `interactionState` restore:

- `web_runtime.hibernate.completed` reported `interaction_state_present=true` and the target Slot left the resident set;
- reactivation emitted `web_runtime.restore.begin` with `restore_source=interaction_state` and created a fresh Runtime identity;
- the exact fresh Runtime emitted `navigation.provisional_started → navigation.commit → navigation.finished` with `stale=false`;
- bounded cross-world liveness on that same Runtime later reported `runtime_context_current=true`, successful main/isolated-world probes, `ready_state=complete`, `is_loading=false`, `estimated_progress=1`, and finished-navigation facts;
- focus recognition succeeded before and after commit;
- no duplicate ordinary URL load, Browser Profile/session mutation, persistence reset, private API, arbitrary readiness timer or unbounded polling was required.

Therefore the frozen Gate 0 classification is **Outcome A — navigation-backed readiness**. Outcome B-style bounded observation also succeeded as corroboration, but Outcome A is the implementation trigger class.

`web_runtime.restore.completed` remains state-handoff evidence only; Phase 6 completion must use exact-current-Runtime navigation-backed readiness and current request/runtime revalidation.

## Frozen ownership / safety boundaries

- `WebViewPool` remains live Runtime creation/hibernate/restore owner;
- `SlotLifecycleCoordinator` remains sole Runtime lifecycle/budget executor;
- `PanelController` remains presentation authority and owns Phase 6 materialization orchestration;
- `WebPanelContainerView` may own only lightweight native restoring presentation;
- `SlotNavigationObserver` may expose only the narrow Outcome-A readiness seam needed by the current owner;
- `WebAttentionCoordinator` remains Attention authority;
- Browser Profile/session/persistent user data remain unchanged;
- Phase 4 Runtime budget remains unchanged;
- no persistent screenshot continuity cache;
- no private WebKit API;
- no release/version work in Phase 6 V1.

## Durable records

Audit/rationale:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md`

Frozen execution contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Implementation_Contract_V1.md`

The implementation contract owns Phase 6 execution scope; the audit remains evidence/rationale.

## Next action

Continue the same task and PR directly through:

1. WP1 — native restoring presentation in `WebPanelContainerView`;
2. WP2 — two-stage `PanelController` materialization with stale-request generation and AppKit run-loop yield;
3. WP3 — Outcome-A exact-current-Runtime navigation readiness completion;
4. WP4 — focused/full tests, Debug/Release arm64, literal-head required CI, bounded Real-Mac smoke and independent exact-diff audit.

The program-final human UI/runtime acceptance remains pending and is intentionally deferred until the integrated Phase 6 implementation and final independent audit are complete.
