# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 1 CI ROUTING CORRECTIVE**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `ACTIVE / BLOCKING CI ROUTING CORRECTIVE BEFORE PHASE 1 INDEPENDENT AUDIT`.

The Phase 1 product implementation is complete on PR #170 and remains unmerged. Its required PR CI did not start. Fresh diagnosis established two independent CI facts: PR #170 currently conflicts with `main`, and GitHub does not create `pull_request` workflow runs while that conflict exists; additionally, FloatTabs macOS CI currently targets GitHub-hosted `macos-26` rather than the intended local Apple Silicon self-hosted runner.

## Canonical / current state

```text
MAIN_BEFORE_CI_CORRECTIVE=766487bf9a94837e714f5da9637f353c9d8a01ae
PRE_PROGRAM_PRODUCT_BASELINE=26d1669198a6f94faa769fb27d2cd00d0fcd1184
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN
JSC_CRASH_ELIMINATED=NOT_CLAIMED

ACTIVE_PROGRAM=FT-RUNTIME-LIFECYCLE-MEMORY-001
PHASE_0_CONTRACT_FREEZE=COMPLETE
HISTORICAL_DOC_GATE=COMPLETE
PHASE_1_FOCUSED_AUDIT=COMPLETE
PHASE_1_V1_PLAN=SUPERSEDED_FOR_CURRENT_EXECUTION
PHASE_1_V2_CONTRACT=ACCEPTED_FROZEN
PHASE_1_V2_PLAN=ACCEPTED_FROZEN
CURRENT_PHASE=PHASE_1_SAFE_HIBERNATE_RESTORE_IMPLEMENTATION
PHASE_1_IMPLEMENTATION_PR=#170 OPEN / UNMERGED
PHASE_1_PR_HEAD=b40bf1d63735700cb0c297d901bd284da1ac105a
PHASE_1_PR_MERGEABLE=NO / CONFLICTING
PHASE_1_REQUIRED_PR_CI=NO_RUN_CREATED
CI_RUNNER_CURRENT=GITHUB_HOSTED macos-26
CI_RUNNER_TARGET=SELF_HOSTED macOS ARM64 mac-mini-ci
PRODUCT_MUTATION=NO NEW PRODUCT MUTATION IN CI CORRECTIVE
STRICT_SCALE_BENCHMARK=DEFERRED_TO_PHASE_4
```

## Current Authority

Read in this order:

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ docs/README.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V2.md
→ docs/architecture/DOMAIN_MAP.md for navigation
→ current source/tests/fresh evidence
```

V1 lifecycle contract/Phase 1 plan remain historical evidence for the original audit and benchmark rationale. They do not override V2's current phase gate.

## Blocking CI corrective

Verified fault boundary:

1. PR #170 has merge conflicts against current `main`; `pull_request` workflow execution is therefore not created until the conflict is resolved.
2. `.github/workflows/macos-ci.yml` currently uses `runs-on: macos-26`, which routes to GitHub-hosted macOS runners rather than the intended local self-hosted Mac mini.
3. The established local Apple Silicon CI routing convention is `[self-hosted, macOS, ARM64, mac-mini-ci]`.
4. Because FloatTabs is public, self-hosted jobs must reject fork PR code by default.

The corrective is bounded to CI/control infrastructure. No Phase 1 Web Runtime product source may change in this corrective.

Required corrective sequence:

```text
reconcile Authority
→ switch required macOS job to [self-hosted, macOS, ARM64, mac-mini-ci]
→ same-repository PR guard
→ verify corrective PR generates/queues a workflow
→ confirm observed runner identity is self-hosted/local when matched
→ merge CI corrective after required check
→ reconcile PR #170 onto fresh main
→ required Phase 1 PR CI
→ independent web audit
```

If the corrective workflow queues indefinitely with no matching runner, stop and treat repository runner registration/access as the remaining infrastructure blocker; do not switch back to GitHub-hosted CI as an implicit workaround.

## Phase 1 target

Implement and finish the structural split:

```text
hibernate(slotID:)
  capture compatible opaque WKWebView interaction state when available
  → deterministic teardown
  → retain one memory-local restore snapshot
  → Runtime becomes non-resident

release(slotID:)
  clear pending restore state
  → deterministic destructive teardown
  → Runtime becomes non-resident
```

Only normal eligible inactive lifecycle reclamation, including the already-existing eligible critical-Warm path, uses hibernate.

All destructive callers remain destructive.

## Authorized production scope

- `FloatTabs/Web/WebViewPool.swift`
- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- `FloatTabs/Web/SlotNavigationObserver.swift`

## Authorized tests

- `FloatTabsTests/WebViewPoolTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebFocusAdapterTests.swift` only if needed for the narrow observer-invalidation fixture

Existing benchmark tooling may be preserved, but strict benchmark expansion is not required for Phase 1 completion.

## Current implementation evidence

PR #170 implementation evidence reported and verified locally before CI:

```text
FOCUSED_TESTS=146 executed / 0 failures
FULL_TESTS=1073 executed / 3 skipped / 0 failures
DEBUG_BUILD=PASS
RELEASE_BUILD=PASS
STRICT_1_2_4_8_BENCHMARK=NOT_RUN / DEFERRED_TO_PHASE_4
LIVE_SMOKE=bounded 2 existing Slots; resident drop, fresh restore, interactionState restore observed
PR=#170 OPEN
PR_HEAD=b40bf1d63735700cb0c297d901bd284da1ac105a
REQUIRED_PR_CI=NO_RUN_CREATED
```

## Phase 1 validation gate — current

Phase 1 merge readiness still requires:

1. exact hibernate vs destructive-release semantics remain correct;
2. deterministic teardown and stale-callback rejection remain correct;
3. Browser Profile / cookies / session / Slot configuration remain untouched;
4. focused regression tests pass;
5. full unit suite has no new Phase 1 failures;
6. Debug and Release builds pass;
7. bounded live 1–2 Slot Runtime smoke proves resident-count drop, fresh single Runtime restore, intact login/session/page/conversation, and no obvious competing double-load;
8. required GitHub `Build & Test (Apple Silicon arm64)` passes on the literal PR head after the branch is reconciled with current `main`;
9. independent web audit passes before merge.

The following are deferred to Phase 4 and are **not** Phase 1 merge blockers:

- strict `1 / 2 / 4 / 8` matrix;
- >=9 configured-Slot fixture;
- 4/8 heavy repeated runs;
- `median reclaimed > 2× control drift`;
- final memory curve / Runtime budget / ranking;
- scale restore p50/p95 policy thresholds.

## Key invariants

- Browser Profile / `WKWebsiteDataStore` identity and persistent session data remain independent from Runtime lifetime.
- `WKWebView.interactionState` remains opaque and memory-local; never persist or log contents.
- compatible interaction-state restore must not also issue a competing ordinary URL load.
- missing/incompatible state uses the existing currentURL/home fallback.
- deterministic teardown explicitly invalidates bridges/popup/navigation observer, clears delegates, calls `stopLoading()`, clears transient Pool state including pending termination incident context, and removes the old Runtime identity.
- restored Runtime receives a fresh Runtime generation/WebView instance identity.
- current active/fullscreen/supplemental-visible/media/Attention protection remains unchanged.
- current Generating/Ready protection remains unchanged in Phase 1.
- Cold website-cache cleanup semantics remain separate and unchanged.

## Explicit non-scope

Do not modify without STOP/reconciliation:

- Panel/Fullscreen/Focus product semantics;
- Browser Profile datastore behavior/schema;
- Attention Generating/Ready semantics;
- durable Unread semantics;
- completion notifications;
- Hot/Warm/Cold UI or timer values;
- automatic Runtime Budget/ranking;
- Website Cache policy/data types;
- process-pool topology;
- server Push/service-worker behavior;
- native conversation preview.

## Execution / handoff state

The immediate action is the bounded CI routing corrective. Do not alter the Phase 1 product implementation while correcting CI infrastructure.

After the CI corrective merges, reconcile PR #170 with fresh `main` without discarding its validated product implementation, allow the required local self-hosted CI to run, then stop for independent web audit.

Merge/release of Phase 1 product code remains unauthorized until those gates pass.

## Non-claims

- Historical JSC root cause remains `UNKNOWN`.
- No final Runtime Budget number is accepted yet.
- No large-scale memory curve is accepted yet.
- No claim is made that ChatGPT generation survives WebView destruction.
- No claim is made yet that the FloatTabs repository can successfully dispatch to the local self-hosted runner until a matching workflow job is observed.
- No newer public release is authorized.
