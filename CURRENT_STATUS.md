# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 4 AUTOMATIC RUNTIME BUDGET / POLICY**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `ACTIVE / PHASE 4 IMPLEMENTATION AUTHORIZED`.

Program Contract V3 remains the current program authority: complete Phases 1–6 with phase-local machine correctness and required CI, then perform one unified independent audit followed by one user-owned full human acceptance pass.

## Canonical / current state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PROGRAM_CONTRACT_V3=ACCEPTED_FROZEN
PROGRAM_UNIFIED_INDEPENDENT_AUDIT=DEFERRED_UNTIL_PHASES_1_6_COMPLETE
PROGRAM_HUMAN_ACCEPTANCE=PENDING / DEFERRED_UNTIL_UNIFIED_AUDIT_PASS

PHASE_1_SAFE_HIBERNATE_RESTORE=COMPLETE
PHASE_2_READY_UNREAD_DECOUPLING=COMPLETE / MERGED
PHASE_2_MERGE_COMMIT=3b8270de6917b0342143a36d2457686bb59dcc25
PHASE_3_NATIVE_COMPLETION_NOTIFICATION=COMPLETE / MERGED
PHASE_3_MERGE_COMMIT=e182dd51a1bfd21a614e09f33643bf4acea551dc
PHASE_4_FOCUSED_AUDIT=COMPLETE
PHASE_4_PLAN_V1=ACCEPTED_FROZEN
PHASE_4_IMPLEMENTATION=AUTHORIZED
PHASE_4_NORMAL_MANAGED_BUDGET=EVIDENCE_SELECTED_FROM_4_3_2_CANDIDATES
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
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Phase4_Automatic_Runtime_Budget_Policy_Plan_V1.md
→ docs/architecture/DOMAIN_MAP.md
→ current source/tests/fresh evidence
```

Phase 1–3 plans remain delivered evidence, not active Phase 4 mutation authority.

## Phase 3 closeout

Phase 3 implementation PR #179 merged at:

`e182dd51a1bfd21a614e09f33643bf4acea551dc`

Delivered Phase 3 behavior:

```text
hidden valid ChatGPT completion
→ durable unread .marked
→ native macOS notification projection
→ persistent Slot UUID routing
→ exact Slot presentation
→ existing Runtime restore/recreation if absent
→ existing acknowledgement semantics
```

Its literal-head required self-hosted CI passed on `macmini-floattabs-01`; program-level human acceptance remains deferred by V3.

## Phase 4 focused audit conclusion

Current runtime ownership already contains the necessary mechanism boundaries. Phase 4 does not need a second Web Runtime owner.

Current facts:

- `WebViewPool` owns live Runtime and hibernate/restore mechanism;
- `SlotLifecycleCoordinator` is the canonical lifecycle/release executor;
- Hot/Warm/Cold are persisted user-visible Slot configuration;
- Hot current semantics are explicit no-automatic-release behavior;
- Warm/Cold currently depend primarily on configurable timers;
- `TabStore` updates persisted `lastUsedAt` on selection;
- Generating protects Runtime; Ready does not;
- durable unread/native notification do not require Runtime residency;
- critical memory pressure currently has a separate eligible-Warm eviction pass;
- Debug benchmark control and aggregate process-tree benchmark infrastructure already exist;
- public WebKit APIs still do not provide reliable exact per-WebContent-process-to-Slot memory attribution.

Phase 4 therefore adds one pure policy inside the existing lifecycle domain and uses the existing lifecycle executor for every actual hibernate.

## Frozen Phase 4 semantics

### Hot compatibility

Hot remains an explicit user pin after activation and is not an automatic-budget candidate.

The managed budget may be exceeded by Hot or hard protections; this is recorded as oversubscription rather than silently changing user intent.

### Warm / Cold automatic management

Warm/Cold become automatic-budget managed.

Existing timers remain maximum normal retention limits, while an over-budget decision may hibernate eligible inactive Runtime earlier.

Ranking is deterministic:

```text
Cold before Warm
→ older lastUsedAt first
→ UUID lexical tie-break
```

### Hard protection

Never budget-evict:

- active/actually presented;
- fullscreen source;
- supplemental visible surface;
- media protected;
- Attention Generating.

Do not protect merely because of:

- Attention Ready;
- durable unread;
- native notification presence.

### Pressure

One policy model owns normal/pressure decisions:

- normal → evidence-selected managed budget;
- warning → evaluate/report normal target;
- critical → managed target 0 for eligible inactive Warm/Cold;
- Hot/hard protections remain intact.

## Phase 4 evidence gate

The production normal budget is deliberately not guessed in Authority.

Required benchmark:

1. raw unbounded loaded-Warm matrix: `1 / 2 / 4 / 8`;
2. at least 3 stable 8-resident no-op control pairs;
3. candidate budgets evaluated in order `4 → 3 → 2`;
4. at least 3 repeated 8-resident controlled runs per candidate;
5. choose the largest candidate whose median reclaimed process-tree RSS is `> 2 ×` median absolute no-op drift while preserving all Runtime/data protections;
6. at least 10 reclaimed-Slot restore/materialization cycles with median/p95 reported;
7. exact resident counts and aggregate process-tree evidence, never invented exact per-Slot memory.

If no budget qualifies, STOP/reconcile instead of hardcoding one.

Strict fixture requires at least 8 safe configured Slots. The benchmark may temporarily change selected Slot policies/media via product APIs and an in-memory DEBUG budget override, but it must restore exact user configuration and may not create/delete/reset user Slots/Profiles to satisfy the fixture.

## Authorized Phase 4 scope

Expected production:

1. **NEW** `FloatTabs/Web/RuntimeBudgetPolicy.swift`;
2. `FloatTabs/Web/SlotLifecycleCoordinator.swift`;
3. `FloatTabs/Panel/PanelController.swift`;
4. `FloatTabs/App/AppCoordinator.swift` — composition/DEBUG benchmark control only;
5. `FloatTabs/Tabs/WebAppProfile.swift` — truthful copy only;
6. `FloatTabs/UI/GlobalSettingsController.swift` — truthful copy only;
7. `FloatTabs.xcodeproj/project.pbxproj`.

Expected test/benchmark:

1. **NEW** `FloatTabsTests/RuntimeBudgetPolicyTests.swift`;
2. `FloatTabsTests/WebAttentionLifecycleTests.swift`;
3. narrowly required adjacent lifecycle/presentation test only if justified;
4. `FloatTabs.xcodeproj/project.pbxproj`;
5. **NEW** `tools/benchmark/floattabs_runtime_budget_benchmark.py`;
6. `tools/benchmark/README.md`;
7. `.github/workflows/benchmark-tool-ci.yml` only if needed for new-tool self-test/compile coverage.

`WebViewPool` production lifecycle/restore semantics are out of scope unless a STOP/reconciliation proves the current mechanism insufficient.

## Phase 4 machine gate

Before Phase 4 merge:

- pure policy invariants PASS;
- lifecycle integration invariants PASS;
- strict Real-Mac 1/2/4/8 evidence gate PASS;
- an evidence-backed normal budget is selected by the frozen rule;
- restore/materialization median/p95 is reported with no failure/duplicate Runtime;
- benchmark compile/self-tests PASS;
- focused Phase 4 XCTest PASS;
- full XCTest PASS;
- Debug arm64 PASS;
- Release arm64 PASS;
- exact changed-path/scope/data-safety audit PASS;
- exactly one Phase 4 implementation PR;
- literal-head required `Build & Test (Apple Silicon arm64)` PASS on `macmini-floattabs-01`;
- PR remains mergeable with no required host blocker.

No Phase 4 AI/CUA live smoke, formal program audit or human UI acceptance is a routine merge gate.

## Explicit non-scope

Do not modify without STOP/reconciliation:

- ChatGPT sensing/extraction;
- durable unread semantics/persistence;
- native completion notification semantics;
- Browser Profile datastore/session semantics;
- `WebViewPool` hibernate/restore contract;
- Slot/Profile persistence schema or Hot/Warm/Cold raw values;
- private WebKit API use;
- persisted Runtime-budget user preference;
- exact per-Slot WebContent memory attribution claims;
- user-data deletion/reset;
- Phase 5 background-generation thrift;
- Phase 6 perceived-fast restore;
- release/version metadata.

## Next action

Execute Phase 4 from the frozen V1 plan with one canonical writer. Implement the pure budget policy, integrate it only through `SlotLifecycleCoordinator`, add the dedicated safe benchmark harness, run the strict 1/2/4/8 + drift + candidate evidence gate, select the largest qualifying normal budget, finish machine verification and push exactly one Phase 4 implementation PR. Stop at the Phase 4 merge gate. Program-final audit and human acceptance remain deferred until Phases 1–6 complete.
