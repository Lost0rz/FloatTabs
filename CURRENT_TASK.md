# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 4 Automatic Runtime Budget / Policy  
**Status:** `ACTIVE / PHASE 4 IMPLEMENTATION AUTHORIZED`  
**Mode:** `EXECUTE`  
**Task class:** `RUNTIME BUDGET POLICY / REAL-MAC SCALE EVIDENCE`  
**Program contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md`  
**Phase 4 plan:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md`  
**JSC root cause:** `UNKNOWN`

## Authorization

Implement Phase 4 only under the frozen Phase 4 V1 plan.

Program cadence remains:

```text
phase-focused audit / freeze
→ bounded implementation
→ phase-local machine verification + required CI
→ merge
→ next architecture phase
...
Phases 1–6 complete
→ unified independent audit
→ one user-owned full human acceptance pass
```

Delivered foundations:

```text
Phase 1 Safe Hibernate + Restore = COMPLETE
Phase 2 Ready / Unread Decoupling = COMPLETE
Phase 3 Native Completion Notification = COMPLETE / MERGED
Phase 3 merge commit = e182dd51a1bfd21a614e09f33643bf4acea551dc
```

## Frozen Phase 4 target

Add a central pure Runtime-budget policy for automatically managed Warm/Cold Runtime while retaining existing lifecycle ownership:

```text
read-only resident/protection/recency facts
→ RuntimeBudgetPolicy pure decision
→ deterministic ranked candidates
→ SlotLifecycleCoordinator sole executor
→ existing WebViewPool hibernate boundary
```

The normal managed budget value is selected from fresh strict 1 / 2 / 4 / 8 Real-Mac evidence, not guessed in advance.

## Required product semantics

### Hot

Hot remains an explicit user pin after activation.

- normal automatic budget must not evict Hot;
- critical budget pass must not silently demote Hot;
- Hot/protected Runtime may make total resident count exceed the managed budget;
- oversubscription must be reported truthfully.

No Hot/Warm/Cold raw-value or persistence migration is authorized.

### Warm / Cold

Warm and Cold are automatic-budget managed.

Existing timers remain maximum normal retention boundaries:

- budget may hibernate eligible inactive Warm/Cold earlier;
- timer expiry may still hibernate when budget has spare capacity;
- Cold ranks before Warm for budget eviction.

### Hard protection

Never budget-evict while protected by:

- active/actually presented state;
- fullscreen source;
- supplemental visible surface;
- existing media protection;
- Attention `generating`.

These do not protect Runtime:

- Attention `ready`;
- durable unread;
- Phase 3 native notification presence.

## Pure policy requirements

Expected new owner:

`FloatTabs/Web/RuntimeBudgetPolicy.swift`

Policy must be deterministic and side-effect free.

Candidate ranking:

```text
Cold before Warm
→ older lastUsedAt before newer
→ slot UUID lexical tie-breaker
```

Do not rank by guessed exact per-Slot WebContent memory.

`SlotLifecycleCoordinator` remains the only Runtime lifecycle writer.

## Memory pressure

Use the same policy/evaluation engine:

- normal → evidence-selected normal managed budget;
- warning → evaluate/report using normal budget, no invented tighter target;
- critical → managed budget `0`, evict every eligible inactive Warm/Cold Runtime while preserving Hot and hard protections.

## Evidence-selected budget

The benchmark must evaluate candidate normal managed budgets in descending order:

```text
4
3
2
```

Before candidates, capture:

- unbounded/disabled-budget loaded Runtime matrix: `1 / 2 / 4 / 8`;
- at least 3 stable 8-resident no-op control pairs;
- median absolute process-tree RSS drift.

For each candidate, run at least 3 repeated controlled 8-resident Warm scenarios.

A candidate qualifies only when:

1. managed resident count converges to target when not blocked by hard protection;
2. no Hot/protected Runtime is evicted;
3. median reclaimed process-tree RSS is `> 2 ×` median absolute no-op drift;
4. no duplicate Runtime, failed restore or data/session loss occurs.

Select the **largest qualifying candidate**.

If none qualifies: `STOP_RECONCILE / PHASE_4_NO_EVIDENCE_BACKED_BUDGET`.

## Restore/materialization evidence

Run at least 10 activation/restoration cycles across reclaimed managed Slots and report product-path Runtime materialization round-trip median/p95.

This is not click-to-interactive/page-ready latency. Phase 6 owns perceived-fast restore.

Any failed activation, duplicate Runtime or state/session loss is a STOP condition.

## Benchmark safety

Expected new tool:

`tools/benchmark/floattabs_runtime_budget_benchmark.py`

Reuse existing Debug benchmark control and responsible-PID process-tree attribution.

Required strict fixture: at least 8 safe configured Slots.

The harness may temporarily change test Slot residency/media through product APIs and use an in-memory DEBUG budget override, but must restore:

- original residency/media;
- original active Slot;
- original panel visibility;
- DEBUG override

on closeout.

Never directly edit persisted profile JSON.

Never automatically create/clone/delete/reset user Slots or Browser Profiles to satisfy the fixture.

If fewer than 8 safe Slots exist: `STOP_RECONCILE / PHASE_4_EVIDENCE_FIXTURE_INSUFFICIENT`.

## Authorized production files

Only expected paths:

- **NEW** `FloatTabs/Web/RuntimeBudgetPolicy.swift`;
- `FloatTabs/Web/SlotLifecycleCoordinator.swift`;
- `FloatTabs/Panel/PanelController.swift`;
- `FloatTabs/App/AppCoordinator.swift` — composition / DEBUG benchmark-control only;
- `FloatTabs/Tabs/WebAppProfile.swift` — truthful residency copy only;
- `FloatTabs/UI/GlobalSettingsController.swift` — truthful residency/timer copy only;
- `FloatTabs.xcodeproj/project.pbxproj` — membership only.

`WebViewPool.swift` production lifecycle/restore semantics are not authorized to change. Current resident-set signal and hibernate mechanism are sufficient. If they are not sufficient, STOP/reconcile.

## Authorized test / benchmark files

Expected:

- **NEW** `FloatTabsTests/RuntimeBudgetPolicyTests.swift`;
- `FloatTabsTests/WebAttentionLifecycleTests.swift`;
- one narrowly necessary adjacent lifecycle/presentation test only if directly required;
- `FloatTabs.xcodeproj/project.pbxproj`;
- **NEW** `tools/benchmark/floattabs_runtime_budget_benchmark.py`;
- `tools/benchmark/README.md`;
- `.github/workflows/benchmark-tool-ci.yml` only for new-tool compile/self-test coverage if needed.

No other production path is authorized without STOP/reconciliation.

## Required machine outcomes

### Policy

Prove:

1. Hot excluded from automatic candidates;
2. hard protections never evicted;
3. Ready/unread/native notification do not protect Runtime;
4. Cold before Warm;
5. LRU by `lastUsedAt` within class;
6. deterministic UUID tie-break;
7. target/oversubscription accounting;
8. warning uses normal target;
9. critical targets zero managed eligible Runtime;
10. policy has no side effects.

### Lifecycle

Prove:

1. over-budget Warm/Cold may hibernate before timer expiry;
2. under-budget timers retain current maximum-retention behavior;
3. Hot stays resident;
4. protection ending reevaluates budget;
5. no recursive/duplicate release from resident-set callbacks;
6. critical pressure uses same policy and sole lifecycle executor;
7. existing hibernate ordering remains intact;
8. restore produces exactly one Runtime;
9. Browser Profile/session/config/unread remain unchanged.

### Benchmark

Prove all Section 7 evidence from the Phase 4 V1 plan and report exact `.benchmark-results/` evidence path.

### Broad gate

Before merge:

- benchmark tool compile/self-test PASS;
- targeted/focused Phase 4 tests PASS;
- full XCTest PASS;
- Debug arm64 PASS;
- Release arm64 PASS;
- exact scope/data-safety audit PASS;
- exactly one Phase 4 implementation PR;
- literal-head `Build & Test (Apple Silicon arm64)` PASS on `macmini-floattabs-01`;
- benchmark-tool CI/self-test PASS if workflow is changed;
- PR mergeable/no required host blocker.

No Phase 4 AI/CUA live smoke, formal program audit or user human acceptance is required before merge under Program Contract V3.

## Explicit forbidden scope

Do not modify without STOP/reconciliation:

- ChatGPT detector/response extraction;
- durable unread semantics/persistence;
- Phase 3 notification semantics;
- Browser Profile datastore/session behavior;
- `WebViewPool` hibernate/restore contract;
- Slot/Profile persistence schema or Hot/Warm/Cold raw values;
- private WebKit APIs;
- persisted Runtime-budget user preference;
- exact per-Slot WebContent memory attribution claims;
- user-data deletion/reset;
- Phase 5 background-generation thrift;
- Phase 6 perceived-fast restore;
- release/version metadata.

## STOP conditions

STOP/reconcile when:

- another Runtime lifecycle writer would be required;
- Hot must be automatically evicted to satisfy normal budget;
- hard-protected Runtime must be evicted;
- WebViewPool restore/hibernate semantics must change;
- persistence/session/schema changes are required;
- exact per-Slot memory attribution is required;
- strict 8-Slot safe fixture is unavailable;
- no candidate budget passes the frozen evidence rule;
- benchmark cannot safely restore temporary configuration;
- restore/materialization shows duplicate Runtime, activation failure or state/session loss;
- tests/build/required CI fail due to Phase 4;
- Phase 5/6 work is required;
- overlapping unique work makes the writer unsafe.

## Delivery boundary

The local executor may implement Phase 4, collect the required benchmark evidence, select the normal budget only by the frozen evidence rule, commit/push one implementation branch and create exactly one Phase 4 implementation PR.

Do not merge, release, bump version or begin Phase 5.

Expected successful terminal state:

`WAITING_FOR_PHASE_4_MERGE_GATE`

Otherwise return the applicable `STOP_RECONCILE` state with evidence.
