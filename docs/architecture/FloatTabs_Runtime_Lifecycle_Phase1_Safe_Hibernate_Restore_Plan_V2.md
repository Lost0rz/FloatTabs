# FloatTabs Runtime Lifecycle — Phase 1 Safe Hibernate + Restore Plan V2

**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Phase:** `1 — Safe Hibernate + Restore`  
**Status:** `ACCEPTED / FROZEN IMPLEMENTATION PLAN`  
**Supersedes for current execution:** `FloatTabs_Runtime_Lifecycle_Phase1_Safe_Hibernate_Restore_Plan_V1.md`  
**Parent contract:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md`

This plan keeps the already-audited Phase 1 implementation architecture and narrows the acceptance gate to structural correctness plus bounded live Runtime validation. The strict multi-Slot performance matrix is deferred to Phase 4 Runtime Budget / Policy.

## 1. Phase objective

Implement the foundational FloatTabs Runtime lifecycle primitive:

```text
Persistent Slot / Browser Profile / product state
                    │
                    ▼
           transient restore snapshot
                    │
                    ▼
             WKWebView Runtime
                LIVE / NIL
```

Phase 1 establishes that an eligible inactive Slot can lose its live `WKWebView`, keep durable Profile/session/configuration state intact, and later create a fresh Runtime that restores safely.

Phase 1 does not select the final residency budget and does not require proof of the 8-Slot memory curve.

## 2. Current implementation situation

Before this V2 refreeze, local Phase 1 implementation work had already been completed against the V1 code scope and produced:

- focused tests: `174 / 174 PASS`;
- full unit run: `1073 executed / 3 skipped / 0 failures`;
- Debug build: `PASS`;
- Release build: `PASS`;
- strict 1/2/4/8 benchmark: not run because the real configuration contains only five Slots and the strict 8-Slot fixture would require at least nine configured Slots.

Those test/build results are prior evidence, not permission to skip fresh verification after the final diff is committed. Existing local implementation work must be preserved and reconciled against this V2 plan rather than discarded and rewritten merely because the acceptance gate changed.

## 3. Frozen semantic split

### `hibernate(slotID:)`

Only normal eligible inactive lifecycle reclamation uses hibernate.

```text
capture compatible restore state if available
→ deterministic teardown of old Runtime
→ retain at most one memory-local restore snapshot
→ Slot remains durable / Runtime becomes non-resident
```

### `release(slotID:)`

Destructive transient Runtime release remains explicit.

```text
clear any pending restore snapshot
→ deterministic teardown
→ Runtime becomes non-resident
```

Do not redefine every existing `release()` caller as hibernation.

Destructive delete/reset/rebuild/Profile/cache/recovery paths stay destructive and clear pending hibernate state.

## 4. Restore snapshot contract

Keep restore state private to the Web Runtime domain, preferably inside `WebViewPool.swift`.

Semantics remain:

- interaction state is opaque;
- memory-local only;
- never log or persist it;
- one Slot has at most one pending snapshot;
- snapshot compatibility checks Slot identity, Browser Profile identity, effective rendering identity and safe current/captured URL relationship;
- missing/incompatible state is discarded and the existing safe URL fallback is used.

A compatible restore must create the full fresh Runtime first, then assign the interaction state, and must not also issue the ordinary initial URL load.

## 5. Restore creation ordering

For a compatible snapshot:

```text
resolve same Browser Profile data store
→ construct Attention/Response bridges
→ install document-start scripts/message handlers
→ create fresh WKWebView
→ assign new Runtime generation / WebView instance identity
→ attach bridges
→ create SlotNavigationObserver
→ create PopupCoordinator / install delegates
→ register new Pool sidecars/maps
→ assign interactionState
→ consume snapshot
```

For missing/incompatible snapshot:

```text
create normal fresh Runtime
→ use existing safe currentURL/home fallback
```

No arbitrary timer, double-navigation workaround or private WebKit API is authorized.

## 6. Deterministic teardown ordering

Use one common teardown boundary where compatible with current semantics.

Before the old Runtime is considered released:

1. freeze only diagnostic/native navigation metadata still needed for truthful evidence;
2. invalidate Attention bridge;
3. invalidate Response bridge;
4. close/discard PopupCoordinator;
5. explicitly invalidate `SlotNavigationObserver` including KVO and pending liveness/navigation/probe tasks;
6. clear `navigationDelegate`;
7. clear `uiDelegate`;
8. call `stopLoading()`;
9. clear transient per-Slot Pool maps, including pending termination incident context;
10. remove the old WebView from AppKit hierarchy if still attached;
11. remove old WebView and Runtime diagnostic identity from Pool;
12. emit truthful hibernate/release/restore diagnostics;
13. update resident-set observation only when logical residency changes.

Stale async work from the old Runtime must fail identity/generation validation and must not mutate the restored Runtime.

## 7. Production implementation scope

Authorized production files remain:

- `FloatTabs/Web/WebViewPool.swift`
- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- `FloatTabs/Web/SlotNavigationObserver.swift`

Expected responsibility:

### `WebViewPool.swift`

- transient restore snapshot storage;
- explicit hibernate path;
- destructive release clears restore state;
- common deterministic teardown;
- restore-vs-URL-load creation decision;
- fresh Runtime identity;
- bounded lifecycle diagnostics.

### `SlotLifecycleCoordinator.swift`

- normal eligible inactive lifecycle reclamation uses hibernate;
- eligible existing critical-Warm pressure path may use the same hibernate primitive;
- no timer, ranking or Runtime Budget redesign in Phase 1.

### `SlotNavigationObserver.swift`

- explicit idempotent invalidation seam for KVO/liveness/navigation/probe work;
- stale callback safety remains generation/identity based.

## 8. Authorized tests

- `FloatTabsTests/WebViewPoolTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebFocusAdapterTests.swift` only if it remains the narrowest existing fixture for observer invalidation.

Tests must cover at least:

1. compatible hibernate capture + fresh restore without normal initial URL load;
2. nil/incompatible state URL fallback;
3. destructive release clears pending snapshot;
4. Browser Profile mismatch invalidates snapshot;
5. rendering mismatch invalidates snapshot;
6. same-Profile sibling Slot isolation;
7. deterministic bridge/popup/observer/delegate/task teardown;
8. pending termination/transient Pool state not carried forward;
9. stale old-Runtime async result rejection;
10. fresh Runtime generation/WebView instance identity;
11. old WebView deallocation where XCTest can establish it deterministically;
12. normal eligible Warm/Cold lifecycle and eligible existing critical-Warm path use the hibernate primitive as intended;
13. active/fullscreen/supplemental-visible/media/Attention protection remains unchanged;
14. Generating/Ready semantics remain unchanged.

Do not manufacture a fake weak-deallocation PASS if WebKit lifetime cannot be deterministic in XCTest.

## 9. Phase 1 verification gate — V2

### Gate A — focused correctness

Run focused lifecycle/Attention tests for the exact diff. Must pass.

### Gate B — broad regression

Run the normal full unit suite. No new failures caused by Phase 1.

### Gate C — builds

Debug and Release builds must pass.

### Gate D — bounded live Runtime smoke

Use the current safe real configuration. Do not add temporary production Slots merely to satisfy a benchmark count.

Exercise 1–2 existing Slots and verify:

```text
eligible inactive Runtime
→ hibernate
→ resident Runtime count decreases
→ select Slot again
→ exactly one fresh Runtime is created
→ interaction-state restore or defined URL fallback occurs
```

Also verify in the exercised path:

- Profile login/session remains intact;
- same page/conversation returns;
- no obvious competing double-load;
- no obvious focus/fullscreen regression;
- no duplicate Runtime identity.

This is a Runtime correctness smoke, not a final memory-performance study.

### Gate E — required PR CI

Required repository-host check `Build & Test (Apple Silicon arm64)` must pass on the literal PR head.

### Gate F — independent web audit

Audit exact diff, ownership, data safety, tests/build/live-smoke evidence and absence of Phase 2+ leakage before merge.

## 10. Deferred performance work

The following are explicitly removed from the Phase 1 merge blocker and moved to Phase 4:

- strict `1 / 2 / 4 / 8` loaded-Slot matrix;
- requirement for >=9 configured Slots;
- heavy 4/8 repeated runs;
- no-op/control drift study;
- `median reclaimed > 2× drift` threshold;
- scale process-tree memory curve;
- final restore p50/p95 budget comparison;
- automatic resident-Runtime budget/ranking decision.

Existing benchmark tooling may remain available. Phase 1 need not modify it further merely to satisfy V1's former strict gate.

Do not delete valid benchmark tooling/evidence just because it is no longer blocking.

## 11. Explicit non-scope

Do not change in Phase 1 without reconciliation:

- Panel/Fullscreen/Focus product semantics;
- Browser Profile datastore behavior/schema;
- Attention Generating/Ready semantics;
- durable Unread semantics;
- completion notifications;
- Hot/Warm/Cold UI/timing values;
- automatic Runtime Budget/ranking;
- Website Cache policy/data types;
- process-pool topology;
- server Push/service worker;
- native recent-conversation preview.

## 12. STOP conditions

STOP and reconcile if:

- old WebView remains strongly reachable from FloatTabs-owned code after deterministic teardown;
- Profile/session/user-data safety needs a behavior/schema change;
- interaction-state restore requires arbitrary timer/double-navigation/private API behavior;
- stale old-Runtime callbacks can mutate the new Runtime;
- destructive paths replay/retain hibernate state incorrectly;
- implementation requires new cross-domain Focus/Fullscreen/Download/Panel ownership semantics;
- required focused/full tests, Debug/Release build or PR CI fail due to the change;
- overlapping unique work makes the current writer unsafe.

Do **not** STOP merely because:

- the user has only five configured Slots;
- 8-Slot benchmark cannot run;
- large-scale memory gain is not yet statistically quantified;
- the final Runtime budget is unknown.

## 13. Delivery sequence

The local executor should preserve the current uncommitted implementation and continue in place if it remains inside this V2 boundary.

```text
refresh new Authority
→ inspect existing dirty diff against V2 scope
→ preserve valid implementation; correct only actual V2 mismatches
→ run focused tests
→ run full tests
→ Debug + Release build
→ bounded 1–2 Slot live Runtime smoke
→ update factual STATUS/TASK evidence if needed
→ commit + push one Phase 1 implementation branch
→ create/update one Phase 1 PR
→ required CI
→ stop for independent web audit
```

No release is authorized.

## 14. Merge readiness

Phase 1 is merge-ready only after:

- exact implementation diff is inside this plan;
- required tests/builds pass;
- bounded live Runtime smoke passes;
- required PR CI passes;
- independent web audit passes;
- Browser Profile/session/user-data safety remains intact.

After merge, perform Control Alignment before entering Phase 2.
