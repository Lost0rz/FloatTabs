# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 6 PERCEIVED-FAST RESTORE**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `PHASE_6_CONTRACT_FROZEN / IMPLEMENTATION_NOT_STARTED / WAITING_FOR_FUTURE_USER_START`.

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
PHASE_6_GATE0=REAL-MAC INTERACTIONSTATE READINESS / REQUIRED BEFORE PRODUCT MUTATION
PHASE_6_IMPLEMENTATION=NOT_STARTED
PHASE_6_CURRENT_SESSION_PRODUCT_MUTATION=FORBIDDEN
PHASE_6_NEXT_USER_START_REQUIRED=YES
TASK_RECONCILIATION_REQUIRED=NO AFTER CONTRACT FREEZE
PROGRAM_HUMAN_ACCEPTANCE=PENDING
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
```

## Phase 6 frozen implementation direction

The Phase 6 detailed audit is complete. The accepted/frozen implementation architecture is now:

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

## Gate 0 readiness freeze

The final callback name is intentionally **not guessed** from structural tests.

Before any Phase 6 product-source mutation, the next execution session must run the frozen Gate 0 Real-Mac observation against an actually hibernated existing Slot and classify the real public behavior as one of:

- **Outcome A — navigation-backed readiness:** compatible interaction-state restore exposes usable current-Runtime navigation/loading callbacks;
- **Outcome B — non-navigation readiness:** compatible interaction-state restore does not reliably emit the same navigation sequence, but current Runtime readiness is provable through a bounded public renderer/page observation;
- **STOP:** no bounded public readiness fact exists, or correctness requires private API, arbitrary delays/polling, reload/double-navigation, persistence mutation, screenshots, extra resident WebViews or ownership changes.

Gate 0 records only content-free timestamps/events. It must not log page text, screenshots, DOM content, cookies, session values or opaque interaction state.

The native restoring state may be removed only when the materialization generation, selected Slot and exact current Runtime still match and Gate 0 has established an approved public bounded readiness fact. `web_runtime.restore.completed` alone is not readiness truth.

## Frozen ownership / safety boundaries

- `WebViewPool` remains live Runtime creation/hibernate/restore owner;
- `SlotLifecycleCoordinator` remains sole Runtime lifecycle/budget executor;
- `PanelController` remains presentation authority and owns Phase 6 materialization orchestration;
- `WebPanelContainerView` may own only lightweight native restoring presentation;
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

Do not construct Phase 6 in the current session.

When the user explicitly starts Phase 6 construction in a later conversation, refresh Authority/repository state and execute **Gate 0 first**. If Gate 0 produces Outcome A or B and no STOP condition fires, continue directly through the frozen contract. If Gate 0 produces the STOP outcome, stop before product mutation and reconcile evidence.