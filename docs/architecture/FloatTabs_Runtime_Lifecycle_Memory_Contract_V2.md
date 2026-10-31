# FloatTabs Runtime Lifecycle & Memory Contract V2

**Status:** `ACCEPTED / FROZEN`  
**Accepted:** `2026-10-31`  
**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Supersedes:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md` for current program execution  
**Reason for revision:** separate structural runtime-lifecycle correctness from later scale/performance policy tuning.

This is the current program-level architecture contract for the Runtime Lifecycle / Memory redesign. V1 remains historical evidence for the original audit and benchmark rationale, but its Phase 1 strict scale-benchmark gate is superseded by this V2 contract.

## 1. Product objective

FloatTabs is a long-lived Web App container. Persistent Slots, Browser Profiles, sessions, unread state and user configuration remain durable while live `WKWebView` runtimes become disposable cache objects that may be reclaimed and recreated safely.

The target architecture remains:

```text
Persistent Slot / Browser Profile / durable product state
                    │
                    ▼
         bounded restore snapshot
                    │
                    ▼
             WKWebView cache
              LIVE / NIL
                    │
                    ▼
              WebViewPool
```

A Slot may exist without a live `WKWebView`.

## 2. Non-negotiable invariants

The following remain frozen and unchanged:

- Browser Profile / `WKWebsiteDataStore` identity is independent from Runtime lifetime.
- Runtime reclamation never authorizes deleting cookies, sessions, website data stores, Slot configuration, preferences, backups or recovery material.
- `WebViewPool` remains the live Web Runtime mechanism owner.
- `SlotLifecycleCoordinator` remains the lifecycle execution boundary unless a later accepted phase changes that ownership.
- Tabs own product/configuration state; Attention/Response own bounded provider/runtime signals; Diagnostics records evidence only.
- One canonical writer per state remains mandatory.
- `WKWebView.interactionState` is opaque runtime state; it is memory-local in Phase 1 and is never logged or persisted.
- Compatible interaction-state restore must not race with an ordinary initial URL load.
- Historical JSC/WebContent stall root cause remains `UNKNOWN`; lifecycle reclamation is not causal proof.
- Cache cleanup is not Runtime lifecycle cleanup.
- Private WebKit APIs are not required or authorized for correctness.

## 3. Revised program cadence

The program now follows an architecture-first cadence:

```text
establish correct ownership / lifecycle primitive
→ prove bounded real-runtime correctness
→ merge the structural change
→ continue dependent architecture phases
→ quantify scale / tune policy when that evidence is needed for policy decisions
```

Verification remains risk-proportional, but a structural phase is not blocked by performance experiments that do not change the structural correctness decision.

This revision does **not** lower the data-safety, lifecycle-correctness, stale-callback, Browser Profile/session, build, test, CI or independent-audit standard.

It changes only when large-scale performance evidence becomes blocking.

## 4. Frozen phase order

### Phase 0 — Authority / contract freeze

Complete.

### Phase 1 — Safe Hibernate + Restore

Goal: establish the reusable Runtime primitive:

```text
hibernate(slotID:)
  capture bounded compatible restore state
  → deterministic teardown
  → Runtime becomes non-resident
  → retain one memory-local restore snapshot when valid

release(slotID:)
  clear pending restore state
  → deterministic destructive teardown
  → Runtime becomes non-resident
```

Phase 1 proves structural correctness and bounded live behavior. It does **not** choose the final Runtime budget or prove a full multi-Slot memory curve.

### Phase 2 — Ready / Unread decoupling

Goal: durable completion/unread state survives Runtime reclamation and `ready` no longer implies indefinite Runtime residency.

### Phase 3 — Native ChatGPT Completion Notification

Goal: validated completion can notify and route back to the exact Slot even when the Runtime has been reclaimed.

### Phase 4 — Automatic Runtime Budget / Policy + scale benchmark

Goal: replace timer-centric residency decisions with a central pure policy, evidence-based candidate ranking and bounded resident-Runtime budget.

**Phase 4 owns the strict scale/performance matrix** needed to choose policy, including the 1/2/4/8 loaded-Slot comparison, repeat runs, control/no-op drift, reclaimed-memory curve, restore latency distribution and budget/threshold decisions.

### Phase 5 — Long-running Background Generation Thrift

Goal: reduce FloatTabs-owned work while generation must remain live.

### Phase 6 — Perceived-fast Restore

Goal: improve perceived restore speed without retaining heavyweight WebViews merely for continuity.

### Optional Phase 7 — server-push / service-worker research

Research only until separately proven and authorized.

## 5. Phase 1 acceptance gate

Phase 1 is accepted when all of the following are true.

### 5.1 Structural correctness

- hibernate and destructive release are separate explicit semantics;
- only eligible inactive lifecycle reclamation uses hibernate;
- destructive delete/reset/rebuild/Profile/cache/recovery paths remain destructive;
- a compatible restore creates a fresh physical Runtime identity and applies the saved interaction state without competing URL load;
- missing/incompatible restore state uses the existing safe URL fallback;
- deterministic teardown invalidates bridges/popup/observer/tasks, clears delegates, calls `stopLoading()`, clears transient Pool maps and removes the old Runtime identity;
- stale callbacks from the old Runtime cannot mutate the new Runtime;
- current active/fullscreen/supplemental-visible/media/Attention protection remains unchanged;
- Phase 1 does not change Generating/Ready semantics, Browser Profile persistence, Website Cache policy or Runtime Budget policy.

### 5.2 Automated verification

Required before Phase 1 merge:

- focused regression tests for the changed lifecycle paths;
- existing Browser Profile / Attention / lifecycle / diagnostics regression coverage remains green;
- full unit test suite remains green except explicitly known pre-existing skips;
- Debug build passes;
- Release build passes;
- required GitHub CI passes on the literal PR head.

### 5.3 Minimal live Runtime smoke

Use the user's existing safe configuration; do not manufacture additional real user Slots solely for this gate.

A bounded 1–2 Slot live smoke must establish:

- an eligible inactive Runtime transitions from resident to non-resident;
- reselecting the Slot creates one fresh Runtime, not a duplicate;
- Browser Profile login/session remains intact;
- the same page/conversation can return through interaction-state restore or the defined URL fallback;
- no visible competing double-load is observed;
- no obvious focus/fullscreen regression is introduced in the exercised path.

Exact child-process/per-Slot memory attribution is **not** required for Phase 1 acceptance.

### 5.4 Independent audit

An independent audit must confirm the exact diff remains inside Phase 1, preserves the ownership/data-safety contract, satisfies the automated/live evidence above and contains no Phase 2+ policy leakage.

## 6. Evidence that is useful but not Phase 1 blocking

The following may be collected opportunistically, but absence or insufficiency does not block Phase 1 merge by itself:

- strict 1/2/4/8 Slot benchmark matrix;
- >=9 configured-Slot fixture;
- 4/8 heavy repeated runs;
- `median reclaimed > 2× control drift` threshold;
- per-scenario process-tree reclaimed-memory curve;
- paired restore p50/p95 distribution at policy-benchmark scale;
- final resident-Runtime budget recommendation.

These move to Phase 4 because they are needed to choose and tune the automatic policy, not to establish the Phase 1 primitive.

Phase 1 may record basic process-tree/resident-count observations, but it must not promote a small smoke sample into a final memory-budget claim.

## 7. Phase 1 STOP conditions

STOP and reconcile before merge if any of the following occurs:

- old Runtime remains strongly reachable from a FloatTabs-owned graph after deterministic teardown;
- Browser Profile/session/user-data safety would require a behavior/schema change;
- compatible `interactionState` restore requires an arbitrary timer, double-navigation workaround, private API or unsupported WebKit behavior;
- stale old-Runtime callback can mutate the restored Runtime;
- destructive paths accidentally retain/replay a hibernate snapshot;
- implementation requires new Focus/Fullscreen/Download/Panel ownership semantics outside the accepted boundary;
- required focused/full tests, Debug/Release build or required CI fail because of the Phase 1 change;
- overlapping unknown unique work makes the authorized writer unsafe.

The following are **not** Phase 1 STOP conditions under V2:

- the current real configuration has fewer than nine Slots;
- strict 8-Slot benchmark cannot run;
- scale memory savings have not yet exceeded a statistical control-drift threshold;
- final automatic Runtime budget is unknown.

Those are Phase 4 evidence questions.

## 8. Phase transition rule

Phase 2 may begin after Phase 1 is merged, control alignment is complete, and the Phase 1 structural + minimal live-runtime gate is accepted.

Do not wait for the Phase 4 scale benchmark before continuing the architecture sequence.

Likewise, do not use the absence of scale benchmark evidence to invent a Runtime budget in Phase 1/2/3.

## 9. Verification philosophy for this program

Use the smallest evidence set that can falsify the current phase's core claim.

- Structural lifecycle phase → lifecycle correctness, data safety, stale-callback safety, real-runtime smoke.
- State-decoupling phase → durable state ownership and transition correctness.
- Notification phase → notification correctness and exact Slot routing.
- Policy phase → scale benchmark, memory curve, latency distribution, budget/ranking evidence.

Do not front-load later-phase experiments into an earlier phase unless they materially change the earlier architecture decision.

## 10. Change control

This V2 contract is `ACCEPTED / FROZEN` for current program execution.

A future material change to phase order, ownership boundaries, persistence/data-safety rules, Attention/unread handoff, notification routing, prohibited shortcuts, or the revised phase-specific acceptance gates requires explicit task reconciliation and a revisioned contract before affected product mutation.
