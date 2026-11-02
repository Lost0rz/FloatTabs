# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 8 PRESSURE + EFFICIENCY RE-SCOPE MERGED / MACHINE + INDEPENDENT AUDIT COMPLETE / PROGRAM-FINAL HUMAN ACCEPTANCE PENDING**

Current task: `FT-RUNTIME-LIFECYCLE-MEMORY-001-PHASE8-PRESSURE-EFFICIENCY` — **CLOSED / MERGED**.

The user selected `D_COMBINE` on 2026-11-02: execute measurement-independent lifecycle improvements now and defer aggregate-memory-budget work until supported deterministic WebKit helper attribution exists. Best-effort/correlation attribution remains rejected.

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
PR_191=MERGED
PR_191_HEAD=1C86E62B
PR_191_SQUASH_MERGE=5BD54EF6
RESCOPE_GATE_R0=PASS
RESCOPE_GATE_R1=PASS
RESCOPE_GATE_R2=PASS
RESCOPE_GATE_R3=PASS
RESCOPE_GATE_R4=PASS_LITERAL_HEAD_1C86E62B
RESCOPE_GATE_R5=PASS_INDEPENDENT_WEB_AUDIT
R1_SUSTAINED_PRESSURE_CORRECTIVE=PASS
NORMAL_TARGET_2=PRESERVED
NORMAL_30S_GRACE=PRESERVED
WARNING_KEEP_LOADED=PRESERVED
CRITICAL_ORDER=AUTOMATIC_THEN_KEEP_LOADED
PRIVATE_SPI=NOT_ADDED
PRODUCT_DATA_MUTATION=NONE
HUMAN_UI_ACCEPTANCE=PENDING_PROGRAM_FINAL
NEXT_GATE=PROGRAM_FINAL_HUMAN_RUNTIME_UI_ACCEPTANCE
```

Current re-scope contract:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md`

WP0 evidence report:

`docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`

## Phase 8 re-scope merged result

### R1 — progressive system-memory-pressure ladder

Healthy-state Phase 7 policy is preserved:

```text
normal
→ Automatic resident target = 2
→ Automatic inactive release = 30s
```

Pressure behavior now is:

```text
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

The independent audit found one blocking sustained-pressure `no_candidate` re-entry defect. PR #191 corrected it with an idempotent eligibility re-entry seam. Regressions prove sustained warning/critical re-entry, warning→critical takeover, stale-normal clearing and single reclaim-chain behavior.

### R2 — bounded background efficiency

The verified host-side cost center was sustained hidden-generation watchdog cadence:

```text
hidden generation <30s    → 2s fallback interval
hidden generation 30–120s → 5s fallback interval
hidden generation >=120s  → 10s fallback interval
```

The event bridge remains the primary completion signal. No WebContent-memory reduction is claimed from this host-side scheduling change.

## Verification / audit closeout

PR #191 literal merge head `1c86e62b7169407ec9cbf242eb29e31c9db3da2e` passed:

- focused R1 lifecycle tests;
- focused R2 watchdog/backoff tests;
- full XCTest;
- Debug arm64 build;
- Release arm64 build;
- native arm64 architecture verification;
- package-lock unchanged check;
- self-hosted `Build & Test (Apple Silicon arm64)` run `41389550011`;
- QA DMG run `41389550006`;
- fresh independent exact-diff / ownership audit.

Independent audit final verdict before merge:

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
```

PR #191 was squash-merged to `main` as `5bd54ef63266dafff8f1a36f4b883367f2158516` on 2026-11-02.

## Source / ownership truth

- `SlotLifecycleCoordinator` remains the sole lifecycle writer.
- `WebViewPool` owns hibernate/release/runtime mechanics.
- `PanelController` constructs/wires the coordinator; it is not a second lifecycle writer.
- `ChatGPTAttentionBridge` owns bounded provider sensing/liveness fallback.
- `RuntimeDiagnostics` remains evidence-only.

## Deferred / blocked work

Still platform-blocked until a supported deterministic aggregate measurement capability exists:

- aggregate FloatTabs/WebKit memory monitor as lifecycle-budget input;
- Auto/Custom/Unlimited aggregate memory-budget scheduler;
- memory-budget Settings UI/persistence projection;
- aggregate-memory A/B claims requiring attributable FloatTabs/WebKit working-set evidence.

Do not substitute transition correlation, guessed per-tab memory, Runtime count, private WebKit SPI, root-only tooling, restricted entitlements or destructive website/session operations.

## Next gate

No further product mutation is authorized by the closed Phase 8 re-scope task.

The next lifecycle-program gate is:

```text
PROGRAM_FINAL_HUMAN_RUNTIME_UI_ACCEPTANCE
```

Human validation should exercise normal Slot switching/restoration, Automatic/Keep Loaded behavior, generation protection, background media protection and sustained use under ordinary system conditions. Aggregate memory-budget claims remain explicitly out of scope.
