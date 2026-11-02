# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001-PHASE8-PRESSURE-EFFICIENCY`  
**Title:** Phase 8 measurement-independent continuation — pressure ladder + background efficiency  
**Status:** `ACTIVE / AUTHORIZED / WAITING PR #190 CLOSEOUT MERGE BEFORE PRODUCT MUTATION`  
**Mode:** `IMPLEMENTATION AFTER CLOSEOUT MERGE`  
**Task class:** `WEB RUNTIME / LIFECYCLE / PERFORMANCE`  
**Execution baseline:** `fresh main after PR #190 merge; must contain this task + re-scope contract`

## Authorization

The user selected `D_COMBINE` on 2026-11-02 and explicitly asked to update repository Authority and issue a local construction card.

This task authorizes the measurement-independent continuation only:

1. progressive system-memory-pressure reclaim in the existing lifecycle owner;
2. bounded host-side background observer/task/generation efficiency corrections.

The aggregate-memory-budget track remains deferred/platform-blocked by Phase 8 Gate 0.

## Frozen authority

- Project rules: `AGENTS.md`
- Program design: `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`
- Original Phase 8 budget contract: `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_Adaptive_Memory_Budget_Implementation_Contract_V1.md` — stopped at Gate 0 for budget construction
- Gate 0 evidence: `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`
- **Current implementation contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md`
- Navigation: `docs/architecture/DOMAIN_MAP.md`, `docs/README.md`

The current implementation contract owns the bounded re-scope where it differs from the original Phase 8 budget sequence. V6 remains the long-term design direction; blocked budget semantics are not current implementation authorization.

## Predecessor closeout gate

PR #190 remains the WP0/reconciliation closeout vehicle. Product mutation under this task MUST NOT begin on the #190 branch.

Required predecessor sequence:

```text
#190 literal new head required CI = PASS
fresh #190 exact-diff / base-head / mergeability check = PASS
#190 merge = COMPLETE
fresh main contains this CURRENT_TASK + re-scope contract
→ only then create/use one successor implementation branch/PR
```

The previous pre-reconciliation #190 head `b775975968f7eecc46940ed69e1b2fab0e41cab3` already passed macOS CI run `41380640917`, but that does not satisfy the literal-head gate after these control/doc commits.

## Scope A — progressive system-memory-pressure ladder

Primary lifecycle owner: `FloatTabs/Web/SlotLifecycleCoordinator.swift`.

Replace only the current pressure count targets (`warning=1`, `critical=0`) with progressive, one-at-a-time behavior driven by the existing supported memory-pressure state.

Required semantics:

### Warning

- eligible inactive/unprotected `Automatic` only;
- deterministic candidate ordering from current lifecycle facts;
- `Keep Loaded` preserved;
- active/presented, fullscreen, supplemental-visible, generating, protected background-media, restoring/materializing and other hard-protected Runtime untouched;
- at most one reclaim transaction in flight;
- after each completion, revalidate latest pressure + current Runtime/protection ownership before any continuation;
- no precomputed multi-Runtime purge from one stale signal.

### Critical

- eligible Automatic first;
- only after Automatic is exhausted may inactive/unprotected Keep Loaded be considered;
- active/hard-protected Runtime remains untouched;
- one Runtime at a time with current-state revalidation between steps.

### Return to normal pressure

- stop/cancel not-yet-started progressive continuation;
- do not mass-restore reclaimed Runtime;
- restore remains demand-driven through existing Slot materialization/restore behavior.

## Scope B — background lifecycle efficiency

Audit first; mutate only verified cost centers. Candidate areas include:

- hidden `ChatGPTAttentionBridge` liveness/fallback work;
- repeated detector scheduling/evaluation;
- redundant response-identity work;
- diagnostic/health probes continuing without need while hidden;
- navigation/observer tasks surviving document/runtime generation changes;
- presentation-only host work surviving detach/reclaim;
- duplicate observer registration or uncancelled Swift concurrency tasks across hibernate/restore/rebuild.

Allowed outcomes include event-first completion sensing, bounded/adaptive fallback, coalescing/suppressing redundant host work, prompt stale-task cancellation and exact-current ownership checks.

Do not redesign provider semantics.

## Explicitly out of scope / deferred

Do NOT implement in this task:

- aggregate FloatTabs/WebKit memory monitor as lifecycle input;
- Auto/Custom/Unlimited memory budget;
- budget watermarks;
- memory-budget settings UI or persistence/backup schema;
- aggregate-memory A/B acceptance claims;
- best-effort WebContent/GPU process attribution;
- healthy-state normal-policy redesign.

Healthy/normal production behavior remains:

```text
normal Automatic resident target = 2
Automatic inactive release path = 30s
```

Changing those two normal-policy semantics requires a new reconciliation.

## Expected source/test boundary

Inspect first:

```text
FloatTabs/Web/SlotLifecycleCoordinator.swift
FloatTabs/Web/WebViewPool.swift
FloatTabs/Web/ChatGPTAttentionBridge.swift
FloatTabsTests/WebViewPoolTests.swift
FloatTabsTests/WebAttentionLifecycleTests.swift
FloatTabsTests/ChatGPTAttentionBridgeTests.swift
```

Mechanically related files are allowed only when Gate R0 proves the dependency and the change remains inside the current Web/runtime/Attention ownership boundary. `PanelController.swift` is conditional wiring only; it must not become a lifecycle writer.

No Settings, Browser Profile, website-data, backup-schema or user-session migration path is authorized.

## Execution gates

### Gate R0 — focused source reconciliation before product mutation

Against fresh merged main:

- confirm `SlotLifecycleCoordinator` remains sole lifecycle writer;
- confirm current pressure source/state path and reclaim boundary;
- confirm current hard-protection/candidate facts;
- confirm hidden generation observer/task ownership and exact tests;
- compare against the WP0 owner map.

If the owner map materially differs, STOP and update Authority before mutation.

### Gate R1 — pressure ladder focused verification

Must prove deterministic warning/critical injection, progressive one-at-a-time reclaim, Keep Loaded warning protection, critical ordering, hard protection, current-state revalidation and normal-state cancellation.

### Gate R2 — background-efficiency focused verification

For each changed cost center, prove task/observer lifetime is bounded, stale work is cancelled/harmless, generation/completion routing remains correct, and intended probe/scheduling work is deterministically lower or bounded.

### Gate R3 — broad machine verification

Required:

- full XCTest PASS;
- Debug arm64 build PASS;
- Release arm64 build PASS;
- native arm64 architecture PASS;
- package lock unchanged unless separately authorized.

### Gate R4 — repository-host gate

Literal successor PR head must pass required `Build & Test (Apple Silicon arm64)` on `[self-hosted, macOS, ARM64, mac-mini-ci]`.

### Gate R5 — fresh exact-diff / ownership audit

Before merge readiness verify:

- no aggregate/best-effort attribution;
- no private WebKit SPI;
- no second lifecycle writer;
- healthy-state target=2 / 30s unchanged;
- no destructive website/session coupling;
- Phase 6 restore and generation protection preserved;
- performance claims match actual measured/tested host-side behavior.

Human final runtime/UI acceptance remains program-final unless Authority later changes that gate.

## STOP conditions

STOP and reconcile if:

- #190 is not merged cleanly with fresh required CI;
- fresh main does not contain this exact task/re-scope Authority;
- the current lifecycle owner map materially differs from WP0 evidence;
- implementation requires private SPI, root, restricted entitlement or guessed/correlated attribution;
- pressure progression cannot remain one-at-a-time with current-state revalidation;
- normal target=2 / 30s must change;
- generation correctness requires provider-semantic redesign;
- Browser Profile/session/site data would be reset/migrated/destructively cleaned;
- a required verification or repository-host gate fails.

## Current execution state

```text
USER_DECISION=D_COMBINE
BUDGET_TRACK=DEFERRED_PLATFORM_BLOCKED
CURRENT_SCOPE=PRESSURE_LADDER_PLUS_BACKGROUND_EFFICIENCY
AUTHORIZATION=GRANTED_AFTER_PR190_CLOSEOUT_MERGE
PRODUCT_MUTATION=NOT_STARTED
NORMAL_POLICY_TARGET2_30S=PRESERVE
BEST_EFFORT_ATTRIBUTION=FORBIDDEN
FIRST_PRODUCT_GATE=R0_FOCUSED_SOURCE_RECONCILIATION
NEXT_ACTION=PR190_LITERAL_HEAD_CI_AND_CLOSEOUT_MERGE
```
