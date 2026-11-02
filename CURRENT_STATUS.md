# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 8 PRESSURE + EFFICIENCY RE-SCOPE COMPLETE / R5 PASS / PR #191 MERGE AUTHORIZED**

Current task: `FT-RUNTIME-LIFECYCLE-MEMORY-001-PHASE8-PRESSURE-EFFICIENCY`.

The user selected `D_COMBINE` on 2026-11-02: execute the measurement-independent work now (`B`) and defer the aggregate-memory-budget track until a supported deterministic attribution capability exists (`A`). Best-effort/correlation attribution (`C`) remains rejected.

## Repository / delivery state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PHASE_7_PR=#188_MERGED
PHASE_7_DELIVERY=COMPLETE
PROGRAM_CONTRACT=V6_ACCEPTED_FROZEN
ORIGINAL_PHASE8_BUDGET_CONTRACT=STOPPED_AT_GATE0
PHASE8_WP0=COMPLETE_2026-11-02
PHASE8_GATE0=FAIL_AGGREGATE_ATTRIBUTION_NOT_PROVABLE
USER_RECONCILIATION=D_COMBINE
BUDGET_TRACK=DEFERRED_PLATFORM_BLOCKED
BEST_EFFORT_ATTRIBUTION=FORBIDDEN
RESCOPE_CONTRACT=ACCEPTED_FROZEN
RESCOPE_SCOPE=PRESSURE_LADDER_PLUS_BACKGROUND_EFFICIENCY
PR_190=MERGED_AT_MAIN_065D2923
SUCCESSOR_PR=#191
SUCCESSOR_BRANCH=codex/ft-pressure-efficiency-phase8-rescope-001
RESCOPE_GATE_R0=PASS
RESCOPE_GATE_R1=PASS
RESCOPE_GATE_R2=PASS
RESCOPE_GATE_R3=PASS
RESCOPE_GATE_R4=PASS_ON_IMPLEMENTATION_HEAD
RESCOPE_GATE_R5=PASS_INDEPENDENT_WEB_AUDIT
R1_SUSTAINED_PRESSURE_CORRECTIVE=PASS
NORMAL_TARGET_2=PRESERVED
NORMAL_30S_GRACE=PRESERVED
WARNING_KEEP_LOADED=PRESERVED
CRITICAL_ORDER=AUTOMATIC_THEN_KEEP_LOADED
PRIVATE_SPI=NOT_ADDED
PRODUCT_DATA_MUTATION=NONE
HUMAN_UI_ACCEPTANCE=PENDING_PROGRAM_FINAL
PR_191_MERGE_READINESS=YES
NEXT_GATE=LITERAL_CONTROL_CLOSEOUT_HEAD_CI_THEN_SQUASH_MERGE
```

Current re-scope contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md`

WP0 evidence report:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`

## Phase 8 re-scope implementation result

### R1 — progressive system-memory-pressure ladder

The fixed Phase 7 pressure count targets were retired. Healthy-state policy remains unchanged.

```text
normal
→ Automatic resident target = 2
→ Automatic inactive release = 30s

warning
→ progressively reclaim eligible inactive/unprotected Automatic
→ one Runtime at a time
→ Keep Loaded preserved
→ revalidate latest pressure + current ownership between steps

critical
→ reclaim eligible Automatic first
→ then inactive/unprotected Keep Loaded
→ active/hard-protected Runtime remains untouched
→ one Runtime at a time

normal pressure restored
→ cancel pending pressure continuation
→ no mass restore
→ future restore remains demand-driven
```

The independent audit found one blocking R1 defect at the sustained-pressure `no_candidate` boundary: a Runtime that became eligible later could fail to re-enter the pressure ladder unless another same-level system pressure event arrived.

That finding was corrected on PR #191 with an idempotent sustained-pressure re-entry seam driven by current lifecycle eligibility changes. Focused regressions prove:

- warning + generation protection ends without another warning event → eligible Automatic is reclaimed;
- critical + Keep Loaded protection ends without another critical event → Keep Loaded is reclaimed after eligible Automatic is exhausted;
- warning → critical takeover cancels the stale warning continuation and preserves Automatic-before-Keep-Loaded ordering;
- normal pressure clears stale pressure state before later eligibility changes;
- repeated eligibility boundaries do not create duplicate reclaim chains.

### R2 — bounded background efficiency

The verified remaining host-side cost center was sustained hidden generation watchdog cadence. The event bridge remains the primary completion signal; only the bounded fallback cadence changes:

```text
hidden generation < 30s   → 2s fallback interval
hidden generation 30–120s → 5s fallback interval
hidden generation >=120s  → 10s fallback interval
```

No WebContent-memory claim is made from this host-side scheduling reduction. Generation protection, completion routing, unread/native notification behavior and document/runtime ownership remain unchanged.

## Verification / audit closeout

The implementation and corrective have passed:

- focused R1 lifecycle tests;
- focused R2 watchdog/backoff tests;
- full XCTest;
- Debug arm64 build;
- Release arm64 build;
- native arm64 architecture verification;
- package-lock unchanged check;
- self-hosted `Build & Test (Apple Silicon arm64)` on the implementation/corrective literal head;
- QA DMG on the same implementation/corrective literal head;
- fresh independent exact-diff / ownership audit.

Independent audit verdict after corrective:

```text
BLOCKING_FINDINGS=0
IMPORTANT_FINDINGS=0
R1_PRESSURE_LADDER=PASS
SUSTAINED_PRESSURE_REENTRY=PASS
ELIGIBILITY_BOUNDARY_COVERAGE=PASS
WARNING_TO_CRITICAL_TAKEOVER=PASS
SINGLE_TRANSACTION_INVARIANT=PASS
R2_BACKGROUND_EFFICIENCY=PASS
DIAGNOSTICS_SEMANTICS=PASS
CODE_MERGE_READY=YES
VERDICT=PASS_WITH_CONTROL_ALIGNMENT_FOLLOWUP
```

This control-plane update is that follow-up. Because it creates a new literal PR head, the required repository-host CI must pass again before merge. The earlier implementation-head PASS is evidence for the code diff, not a substitute for the new literal-head merge gate.

## Source / ownership truth

- `SlotLifecycleCoordinator` remains the sole lifecycle writer.
- `WebViewPool` owns hibernate/release/runtime mechanics; its product semantics were not redesigned by the corrective.
- `PanelController` constructs/wires the coordinator; it is not a second lifecycle writer.
- `ChatGPTAttentionBridge` owns bounded provider sensing/liveness fallback; the R1 corrective did not change R2 semantics.
- `RuntimeDiagnostics` remains evidence-only.

## Deferred / blocked work

Still blocked until a supported deterministic aggregate measurement capability exists:

- aggregate resource monitor as a lifecycle-budget input;
- Auto/Custom/Unlimited aggregate memory-budget scheduler;
- memory-budget Advanced UI/persistence projection;
- aggregate-memory A/B claims requiring attributable FloatTabs/WebKit working-set evidence.

Do not substitute transition correlation, guessed per-tab memory, Runtime count, private WebKit SPI, root-only tooling, restricted entitlements or destructive website/session operations.

## Merge boundary

PR #191 is authorized to merge after this control-only closeout head passes the required self-hosted repository-host gate and remains clean/mergeable.

Required sequence:

```text
1. literal control-closeout PR head required macOS CI = PASS
2. QA DMG = PASS if triggered for that head
3. fresh PR head/base/mergeability check = PASS
4. mark #191 Ready for Review if still Draft
5. squash merge #191 using expected literal head SHA
6. verify fresh main contains the merged Phase 8 re-scope
```

Human runtime/UI acceptance remains `PENDING_PROGRAM_FINAL`; under the accepted re-scope contract it is not an earlier blocker for PR #191 merge.
