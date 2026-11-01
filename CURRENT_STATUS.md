# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 6 PERCEIVED-FAST RESTORE**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `PHASE_6_AUDIT_COMPLETE / DESIGN_PROPOSED / IMPLEMENTATION_NOT_AUTHORIZED`.

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
PHASE_6_RECOMMENDATION=TWO-STAGE NATIVE RESTORE SHELL
PHASE_6_IMPLEMENTATION=NOT_AUTHORIZED
PHASE_6_OPEN_EVIDENCE=REAL-MAC INTERACTIONSTATE READINESS SEQUENCE
TASK_RECONCILIATION_REQUIRED=YES
PROGRAM_HUMAN_ACCEPTANCE=PENDING
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
```

## Phase 5 closeout

PR #183 is merged. Long-running hidden generation keeps Runtime protection but reduces FloatTabs-owned fallback liveness probing from 2s to 5s after 30s. Visible/unknown/short generation keeps the existing 2s cadence. Browser Profile/session/persistence and lifecycle ownership remain unchanged.

## Phase 6 audit verdict

Phase 1 restore correctness is already structurally sound and should not be rewritten. Reclamation stores one opaque, memory-local `WKWebView.interactionState` snapshot and recreates a fresh Runtime against the same Browser Profile datastore; incompatible state falls back to the safe URL path.

The strongest verified Phase 6 UX bottleneck is presentation ordering:

- `PanelController.synchronizeSlotState()` synchronously calls `WebViewPool.webView(for:)` for a non-resident selected Slot;
- fresh Runtime creation performs datastore resolution, bridge/script/observer setup, `WKWebView` allocation and restore-state application before returning;
- on hidden → visible summon, `showFloatTabs` performs this synchronization before `panel.orderFrontRegardless()`;
- therefore even the native FloatTabs shell can wait behind WebKit Runtime materialization;
- after materialization there is no explicit native restoring presentation state or product-owned first-usable-content boundary.

## Proposed Phase 6 architecture

**Selected recommendation: two-stage native restore shell + deferred materialization.**

```text
select/summon reclaimed Slot
→ native FloatTabs shell + lightweight restoring surface immediately
→ return to AppKit run loop
→ next bounded main-actor turn: revalidate current request
→ existing WebViewPool materializes fresh WKWebView
→ attach WebView under restoring surface
→ existing navigation/focus ownership establishes readiness/input
→ remove restoring surface on a proven current-Runtime readiness boundary
```

This keeps the Phase 4 Runtime budget intact and does not retain extra WebViews.

Rejected for Phase 6 V1:

- page screenshot cache as default continuity mechanism — asynchronous capture, page-content/privacy/memory/staleness cost;
- predictive prewarm or larger resident Runtime budget — conflicts with the memory objective and can create churn;
- rewriting `interactionState` / Browser Profile restore — no evidence it is the current bottleneck.

## Open evidence before implementation freeze

One bounded Real-Mac probe is still required to freeze the exact overlay-dismiss/readiness signal for a real `interactionState` restore. Current structural tests inject interaction-state provider/applier seams; they do not prove which navigation/loading callbacks every relevant real restore emits.

Required public-fact sequence to observe:

```text
selection/summon request
→ shell ordered
→ fresh WKWebView allocated
→ interactionState applied
→ navigation provisional/commit/finish callbacks, if any
→ isLoading transition
→ bounded renderer/page readiness
→ focus success
```

No page content may be logged.

## Durable audit record

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase6_Perceived_Fast_Restore_Audit_V1.md`

Status: `AUDIT COMPLETE / PROPOSED DESIGN / NOT IMPLEMENTATION AUTHORITY`.

## Non-negotiable boundaries

- `WebViewPool` remains live Runtime mechanism owner;
- `SlotLifecycleCoordinator` remains sole Runtime lifecycle executor;
- `PanelController` remains product/presentation visibility authority;
- `WebAttentionCoordinator` remains Attention authority;
- Browser Profile/session/persistent user data are not reset/deleted/recreated as a restore shortcut;
- no private WebKit API;
- no Runtime budget expansion to hide restore latency;
- no Phase 6 product implementation until task reconciliation and explicit authorization.

## Next action

Wait for explicit Phase 6 implementation authorization. If authorized, first reconcile `CURRENT_TASK.md` into a bounded implementation contract and freeze the final readiness signal using the Real-Mac evidence gate, then implement only the selected two-stage native restore presentation path.