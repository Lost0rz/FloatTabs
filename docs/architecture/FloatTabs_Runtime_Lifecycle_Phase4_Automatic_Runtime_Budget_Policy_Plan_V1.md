# FloatTabs Runtime Lifecycle — Phase 4 Automatic Runtime Budget / Policy Plan V1

**Status:** `ACCEPTED / FROZEN FOR PHASE 4 EXECUTION`  
**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Program contract:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md`  
**Baseline:** Phase 3 merged on `main` at `e182dd51a1bfd21a614e09f33643bf4acea551dc`.

## 1. Objective

Phase 4 replaces timer-only automatic residency with one deterministic, centrally evaluated Runtime-budget policy while preserving the existing Runtime ownership and user-data boundaries.

Target flow:

```text
persistent Slot/Profile/configuration
→ WebViewPool owns live Runtime cache
→ RuntimeBudgetPolicy receives read-only resident/protection/recency facts
→ pure ranked keep/evict decision
→ SlotLifecycleCoordinator remains the sole lifecycle executor
→ existing hibernate boundary releases eligible Runtime only
→ Browser Profile/session/unread/configuration remain untouched
```

The normal automatic budget is evidence-selected from a strict Real-Mac 1 / 2 / 4 / 8 loaded-Slot benchmark. The benchmark is a Phase 4 machine-design gate, not final human acceptance.

## 2. Focused audit findings

### 2.1 Existing ownership is sufficient

Current production already has the required mechanism boundaries:

- `WebViewPool` owns live `WKWebView` Runtime creation, hibernate/release and bounded restore snapshots;
- `SlotLifecycleCoordinator` is the single canonical lifecycle/release executor;
- `WebAttentionCoordinator` exposes Runtime protection, where Generating protects and Ready does not;
- `TabStore` persists `WebAppProfile.lastUsedAt` on selection and owns Slot configuration;
- `WebViewPool.onResidentSetChange` provides an event-driven resident-set change signal;
- Debug benchmark control already selects/configures Slots through product APIs and exposes actual resident Slot counts;
- existing benchmark tools already attribute aggregate FloatTabs/WebKit process-tree RSS/CPU without claiming exact per-Slot WebContent bytes.

Therefore Phase 4 must not add another object that directly hibernates/releases `WKWebView` instances.

### 2.2 Hot is an explicit user pin, not an automatic-budget candidate

Current persisted `SlotResidencyPolicy` is user-visible configuration. Historical accepted product behavior explicitly defined Hot as no proactive automatic release, while current source/UI still describes Hot as not automatically released.

Phase 4 preserves that explicit user intent:

```text
Hot = explicit Runtime pin after activation
```

Hot Runtime is excluded from normal automatic-budget eviction. Hot may therefore make total resident Runtime count exceed the automatic managed budget. Such oversubscription is recorded truthfully; it is not silently corrected by demoting Hot.

No persistence migration or enum/raw-value change is required.

### 2.3 Warm / Cold become automatically budget-managed

Warm and Cold remain persisted user choices but no longer rely solely on their timers.

Their timers become maximum retention boundaries:

- Warm may remain resident up to the configured Warm retention limit when budget permits;
- Cold may remain resident up to its configured Cold delay when budget permits;
- an over-budget decision may hibernate an eligible inactive Warm/Cold Runtime earlier;
- normal timer expiry may still hibernate an eligible Runtime even when the budget has spare capacity.

This keeps existing user knobs meaningful while adding bounded automatic residency.

### 2.4 Hard Runtime protection remains separate from residency preference

The following are non-evictable while true:

- active/actually presented Slot;
- fullscreen source;
- supplemental visible Web surface;
- active background media protection under existing media policy;
- Attention `generating` protection.

The following do **not** protect Runtime:

- Attention `ready`;
- durable unread;
- presence of a Phase 3 native notification;
- a Slot merely having a restorable snapshot.

If hard-protected managed Slots exceed the normal budget, the policy reports oversubscription and evicts no protected Runtime.

### 2.5 Memory pressure must use the same decision engine

The existing critical-memory-pressure path directly enumerates eligible Warm plans. Phase 4 folds this into the same policy/evaluation boundary so there is still one decision model and one lifecycle executor.

Frozen pressure semantics:

- normal: use the evidence-selected normal managed budget;
- warning: trigger/report policy evaluation but do not tighten below the normal budget merely because of warning;
- critical: managed budget becomes `0`, so every eligible inactive Warm/Cold Runtime may be hibernated while Hot and hard protections remain intact.

No private WebKit memory attribution is introduced.

## 3. Frozen policy model

### 3.1 Pure policy owner

Add a pure deterministic policy/value type, expected path:

`FloatTabs/Web/RuntimeBudgetPolicy.swift`

It owns only decision logic. It does not touch AppKit, WebKit, persistence, timers, diagnostics writers or system memory-pressure APIs.

Conceptual input per resident Slot:

```text
slotID
residencyPolicy
lastUsedAt
isActiveOrPresented
isFullscreenSource
isSupplementalVisible
isMediaProtected
isAttentionProtected
hasInactiveLifecyclePlan
```

Global input includes:

```text
normalManagedBudget
pressureMode = normal | warning | critical
resident Slot set
```

Conceptual output includes:

```text
managedResidentCount
protectedOrPinnedCount
targetManagedBudget
ranked eligible eviction Slot IDs
remaining oversubscription after all eligible candidates
per-Slot decision/reason
```

### 3.2 Candidate eligibility

Normal/critical budget eviction candidate requires all of:

```text
resident
AND residency in {Warm, Cold}
AND inactive lifecycle plan exists
AND not active/presented
AND not fullscreen source
AND not supplemental visible
AND not media protected
AND not Attention-protected
```

Hot is never a normal/critical automatic-budget candidate in Phase 4.

### 3.3 Deterministic ranking

Eligible candidates rank in this order:

1. Cold before Warm;
2. older `lastUsedAt` before newer `lastUsedAt`;
3. stable `slotID.uuidString` lexical order as final tie-breaker.

The ranking is deliberately independent of guessed per-Slot memory usage because public WebKit APIs do not provide trustworthy exact per-WebContent-process-to-Slot attribution.

### 3.4 Budget accounting

The Phase 4 number is an **automatic managed-resident budget** for Warm/Cold Runtime, not a permission to violate explicit Hot pins or hard foreground protections.

For a selected normal budget `B`:

```text
managed resident Warm/Cold count <= B
```

is the target when sufficient eligible candidates exist.

Temporary or persistent oversubscription is allowed only when caused by:

- Hot explicit pins;
- hard Runtime protections;
- a lifecycle state that is not yet safely eligible for hibernate.

Diagnostics must distinguish target, actual resident count, pinned/protected count, eligible candidate count and remaining oversubscription.

## 4. Lifecycle execution boundary

`SlotLifecycleCoordinator` remains the single writer that performs Runtime lifecycle mutation.

Phase 4 may add a method conceptually equivalent to:

```text
evaluateRuntimeBudget(reason)
```

The method:

1. gathers current read-only facts;
2. asks `RuntimeBudgetPolicy` for a pure decision;
3. records privacy-safe decision evidence;
4. executes ranked hibernation through the existing deterministic release preparation/container removal/`WebViewPool.hibernate` boundary;
5. re-evaluates only when a state-changing event requires it.

No second coordinator may directly call `WebViewPool.hibernate/release` for budget purposes.

## 5. Evaluation triggers

Use event-driven reevaluation, not high-frequency polling.

Required triggers include, where relevant:

- resident Runtime added/removed (`WebViewPool.onResidentSetChange` or equivalent bounded handoff);
- Slot deactivation / hidden-active grace completion;
- Slot/Profile residency policy change;
- Attention protection ending;
- media protection state becoming releasable;
- fullscreen/supplemental visibility ending;
- memory-pressure warning/critical;
- lifecycle reconciliation after configuration changes.

Implement a re-entrancy/coalescing guard if resident-set callbacks caused by budget hibernation would otherwise recursively produce duplicate release work.

## 6. Existing timers and UI semantics

No persistence key/schema is removed in Phase 4.

Existing:

- `WarmWebViewRetentionOption`;
- `ColdWebViewReleaseOption`;
- persisted Hot/Warm/Cold raw values

remain compatible.

User-facing copy must be made truthful:

- Hot: explicit pin / no automatic budget eviction;
- Warm: retained when budget permits, with configured Warm duration as maximum normal retention;
- Cold: first automatic eviction priority, with configured Cold delay as maximum normal retention;
- automatic budget or critical pressure may reclaim eligible Warm/Cold earlier.

Do not rename enum raw values or migrate stored profiles.

## 7. Phase 4 benchmark gate

### 7.1 Why benchmark is required

The normal managed budget value must not be guessed in code review. It must be selected from fresh Real-Mac evidence on the Phase 4 implementation branch.

### 7.2 Benchmark implementation

Add a dedicated benchmark harness, expected path:

`tools/benchmark/floattabs_runtime_budget_benchmark.py`

Reuse existing:

- Debug loopback benchmark control;
- responsible-PID WebKit attribution;
- aggregate process-tree RSS/CPU sampling;
- resident Slot count/status;
- product-path Slot selection/configuration;
- `.benchmark-results/` output convention.

Do not edit profile JSON directly.

A bounded DEBUG-only in-memory budget override/control action may be added so the same production policy kernel can be exercised with candidate budgets without adding a persisted user preference.

### 7.3 Required fixture safety

The strict matrix requires at least 8 safe configured test Slots.

The harness may temporarily change selected Slot residency/media through existing product APIs and must restore:

- exact original residency/media settings;
- original active Slot;
- original panel visibility;
- any DEBUG-only budget override

in `finally`/closeout behavior.

It must not automatically create, clone, delete or reset persisted Slots, Browser Profiles, cookies or website sessions to satisfy the matrix.

If fewer than 8 safe Slots are available:

`STOP_RECONCILE: PHASE_4_EVIDENCE_FIXTURE_INSUFFICIENT`

### 7.4 Required scale matrix

Capture aggregate process-tree evidence for loaded Warm Runtime counts:

```text
1
2
4
8
```

Budget is disabled/unbounded for the raw scale curve. Each scenario must prove actual resident count from product status rather than infer from configured Slot count.

Capture at least:

- host RSS / CPU;
- attributed WebContent / Networking / GPU RSS and CPU where available;
- total FloatTabs process-tree RSS / CPU;
- WebContent/helper counts;
- actual resident Slot count;
- hard-protected/pinned/managed counts once Phase 4 policy exists;
- environment metadata and exact commit.

Never label aggregate helper RSS as exact per-Slot memory.

### 7.5 Control/no-op drift

Before using reclaimed-memory numbers, collect at least 3 repeated no-op control windows at a stable 8-resident Warm state.

Compute the median absolute process-tree RSS drift between paired stable windows.

### 7.6 Candidate budgets

Evaluate candidate normal managed budgets in descending order:

```text
4
3
2
```

For each candidate, perform at least 3 repeated 8-resident Warm runs from the same controlled/no-media workload class.

A candidate qualifies only when all repeats preserve lifecycle/data-safety invariants and:

1. resident managed count converges to the target when no hard protection prevents it;
2. no Hot/protected Runtime is evicted;
3. median reclaimed process-tree RSS is greater than `2 ×` the median absolute no-op drift;
4. no duplicate Runtime or failed restore is observed.

Select the **largest qualifying candidate**. This deliberately prefers continuity/responsiveness once a material memory benefit is proven.

If no candidate qualifies:

`STOP_RECONCILE: PHASE_4_NO_EVIDENCE_BACKED_BUDGET`

The selected value becomes the production normal managed budget in the same Phase 4 implementation branch.

### 7.7 Restore/materialization distribution

For reclaimed managed Slots, perform at least 10 activation/restoration cycles across representative reclaimed Slots and report host-side Runtime materialization/activation round-trip:

- median;
- p95;
- failures/outliers separately.

This metric ends when product status proves the target Runtime is resident/selected through the normal lifecycle path. It is **not** called click-to-interactive or page-ready latency.

Phase 6 owns perceived-fast restore and any trustworthy user-visible readiness instrumentation.

No arbitrary Phase 4 latency threshold is introduced. Any restore failure, duplicate Runtime or state/session loss is a STOP condition.

## 8. Authorized production scope

Expected production paths:

1. **NEW** `FloatTabs/Web/RuntimeBudgetPolicy.swift`;
2. `FloatTabs/Web/SlotLifecycleCoordinator.swift`;
3. `FloatTabs/Panel/PanelController.swift`;
4. `FloatTabs/App/AppCoordinator.swift` — only composition / DEBUG benchmark-control wiring required by this plan;
5. `FloatTabs/Tabs/WebAppProfile.swift` — truthful residency copy only; no persisted raw-value/schema change;
6. `FloatTabs/UI/GlobalSettingsController.swift` — truthful residency/timer copy only;
7. `FloatTabs.xcodeproj/project.pbxproj` — source/test membership only.

`WebViewPool.swift` is not expected to require production mutation because current resident-set and hibernate mechanisms are sufficient. If production correctness requires changing its lifecycle/restore semantics, STOP/reconcile.

## 9. Authorized test / benchmark scope

Expected tests:

1. **NEW** `FloatTabsTests/RuntimeBudgetPolicyTests.swift`;
2. `FloatTabsTests/WebAttentionLifecycleTests.swift`;
3. a narrowly necessary existing lifecycle/presentation test file only if directly required;
4. `FloatTabs.xcodeproj/project.pbxproj`.

Expected benchmark/tool paths:

1. **NEW** `tools/benchmark/floattabs_runtime_budget_benchmark.py`;
2. `tools/benchmark/README.md`;
3. `.github/workflows/benchmark-tool-ci.yml` only to include new benchmark self-test/compile validation if needed.

No other production path is authorized without STOP/reconciliation.

## 10. Required machine outcomes

### Gate A — pure policy

Prove:

1. Hot is never an automatic-budget candidate;
2. Active/presented/fullscreen/supplemental/media/Generating protection is never evicted;
3. Ready/unread/native-notification presence does not protect Runtime;
4. Cold ranks before Warm;
5. older `lastUsedAt` ranks before newer within a class;
6. UUID tie-break is deterministic;
7. managed resident target and oversubscription reporting are correct;
8. critical mode targets zero eligible managed residents;
9. warning mode does not invent a tighter budget;
10. policy has no WebKit/AppKit/persistence side effects.

### Gate B — lifecycle integration

Prove:

1. over-budget inactive Warm/Cold can hibernate before timer expiry;
2. under-budget Warm/Cold retain existing maximum-timer behavior;
3. timer expiry still works;
4. Hot remains resident under normal/critical budget passes;
5. protection ending causes reevaluation;
6. resident-set reevaluation does not recursively duplicate release work;
7. critical pressure uses the same policy and lifecycle executor;
8. hibernate ordering remains `prepareRuntimeForRelease → container remove → WebViewPool.hibernate → release callback`;
9. restore creates/reuses exactly one Runtime;
10. Browser Profile/session/configuration/unread remain unchanged.

### Gate C — benchmark evidence

Prove the strict matrix, control drift, candidate selection and restore/materialization distribution from Section 7. Persist results only under gitignored `.benchmark-results/` and report the exact evidence path/summary in the execution receipt.

### Gate D — broad verification

- policy/benchmark self-tests PASS;
- focused Phase 4 XCTest PASS;
- full XCTest PASS;
- Debug arm64 PASS;
- Release arm64 PASS;
- exact changed-path/scope/data-safety audit PASS;
- literal-head required `Build & Test (Apple Silicon arm64)` PASS on `macmini-floattabs-01`;
- benchmark-tool workflow/self-test PASS if modified.

Under Program Contract V3, Phase 4 does not require AI/CUA live smoke, formal independent web audit or user human acceptance before merge.

## 11. Explicit non-scope

Do not modify without STOP/reconciliation:

- ChatGPT detector/response extraction;
- durable unread persistence/semantics;
- Phase 3 native notification semantics;
- Browser Profile datastore/session semantics;
- `WebViewPool` hibernate/restore contract;
- Slot/Profile persistence schema or Hot/Warm/Cold raw values;
- user-data deletion/reset;
- exact per-Slot WebContent memory attribution claims;
- private WebKit APIs;
- persisted Runtime-budget user preference in Phase 4;
- Phase 5 background-generation thrift;
- Phase 6 perceived-fast restore behavior;
- release/version metadata.

## 12. STOP conditions

STOP and reconcile if:

- a second Runtime lifecycle writer is required;
- normal budget correctness requires evicting Hot without a new explicit product decision;
- hard-protected Runtime must be evicted to meet the numeric budget;
- `WebViewPool` restore/hibernate semantics must change;
- Browser Profile/session/configuration schema must change;
- exact per-Slot WebContent bytes are required for ranking;
- fewer than 8 safe benchmark Slots are available;
- no candidate budget passes the evidence rule;
- benchmark cannot restore changed user configuration safely;
- restore/materialization produces duplicate Runtime, state/session loss or failed activation;
- required tests/build/CI fail because of Phase 4;
- Phase 5/6 work is required;
- overlapping unique work makes the writer unsafe.

## 13. Delivery

The local executor may implement the frozen Phase 4 policy and benchmark, run the required Real-Mac evidence gate, select the production budget only by the frozen rule, update factual control evidence, commit/push one implementation branch and open exactly one Phase 4 implementation PR.

It must not merge, release, bump version or begin Phase 5.

Expected successful terminal state:

`WAITING_FOR_PHASE_4_MERGE_GATE`

Expected evidence-blocked terminal states are the explicit `STOP_RECONCILE` conditions above.

## 14. Implementation sequence

```text
pure RuntimeBudgetPolicy + tests
→ integrate with SlotLifecycleCoordinator as sole executor
→ add DEBUG-only candidate-budget benchmark control
→ add 1/2/4/8 budget benchmark harness + self-tests
→ run raw 1/2/4/8 scale curve
→ run 8-resident no-op drift controls
→ run candidate budgets 4 → 3 → 2 with repeats
→ select largest qualifying budget or STOP
→ run restore/materialization distribution
→ finalize production normal budget
→ focused/full tests
→ Debug/Release arm64
→ exact scope/data-safety audit
→ commit/push one Phase 4 implementation PR
→ literal-head required self-hosted CI PASS
→ stop at merge gate
```
