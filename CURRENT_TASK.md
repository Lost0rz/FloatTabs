# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`
**Title:** Runtime Lifecycle / Memory redesign — governed phased implementation
**Status:** `ACTIVE / PHASE 1 FOCUSED AUDIT`
**Mode:** `AUDIT`
**Task class:** `HIGH-RISK WEB RUNTIME LIFECYCLE / MEMORY`
**Pre-program product baseline:** `26d1669198a6f94faa769fb27d2cd00d0fcd1184`
**Phase 0 merge:** `18d9d8a0a0c07f4f6547907cfaae043741346080`
**Frozen contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`
**JSC root cause:** `UNKNOWN`

## Program objective

Reduce FloatTabs steady-state resource use while preserving the product promise of persistent, quickly accessible Web App Slots and isolated persistent Browser Profiles.

The accepted architecture treats live `WKWebView` instances as disposable/bounded Runtime cache only after safe capture/release/restore is proven. Persistent Slot configuration, Browser Profile website data, user sessions, durable unread state, preferences, backups, and recovery data remain outside Runtime lifetime.

## Phase 0 closeout

Phase 0 is complete.

```text
PHASE_0_PR=#163 MERGED
PHASE_0_PR_HEAD=546963e13c3a259bbb3e484d74d144910c48c39f
PHASE_0_MERGE_COMMIT=18d9d8a0a0c07f4f6547907cfaae043741346080
PHASE_0_REQUIRED_CI_RUN=41202810371 PASS
PHASE_0_CHANGED_FILES=6 CONTROL/ARCHITECTURE MARKDOWN FILES ONLY
PHASE_0_PRODUCT_CODE_CHANGED=NO
REVIEWS=0
UNRESOLVED_REVIEW_THREADS=0
```

The accepted contract, architecture routing, Domain Map updates, and durable phase/audit execution gate are now part of `main`.

## Current authorization — Phase 1 audit only

The only currently authorized work is a **focused read-only pre-implementation audit** for:

`Phase 1 — Safe Hibernate + Restore`

The audit may:

- read current production source and tests;
- inspect current Git/GitHub branch/PR/history evidence relevant to the lifecycle boundary;
- inspect supported public Apple/WebKit API documentation;
- inspect relevant open-source WebKit browser implementations for bounded reference evidence;
- run/read non-mutating benchmarks or existing diagnostic seams where safe;
- update repository control/design documents to freeze the exact Phase 1 implementation boundary.

The audit may **not** mutate Runtime product code.

Runtime product mutation becomes authorized only after this task is intentionally reconciled to `ACTIVE / PHASE 1 IMPLEMENTATION` with exact files/symbols, acceptance criteria, tests, benchmark plan, and STOP conditions.

## Accepted/frozen architecture direction

The complete contract lives in `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`. The following is a routing summary only.

### Ownership

```text
Persistent Slot / Browser Profile / durable unread
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

- `WebViewPool` remains the live Web Runtime mechanism owner.
- `SlotLifecycleCoordinator` remains the current lifecycle execution boundary unless a later accepted phase deliberately refactors that responsibility.
- Browser Profile / `WKWebsiteDataStore` ownership does not move into Runtime policy.
- Attention, Response, Unread, Presentation, Persistence, Diagnostics, and Website Cache remain separate authorities.

### Frozen phase order

```text
0  Authority / contract freeze                         COMPLETE
1  Safe Hibernate + Restore                            AUDIT ACTIVE
2  Ready / Unread decoupling                           NOT STARTED
3  Native ChatGPT Completion Notification              NOT STARTED
4  Automatic Runtime Budget / Policy                   NOT STARTED
5  Long-running Background Generation Thrift           NOT STARTED
6  Perceived-fast Restore                              NOT STARTED
7  Optional server-push / service-worker research      NOT STARTED
```

No later phase may be pulled forward merely because it is easier to implement.

## Mandatory per-phase workflow

Every implementation phase follows this sequence:

```text
READ AUTHORITIES
→ focused read-only audit
→ freeze exact phase scope / files / tests / STOP conditions
→ reconcile CURRENT_STATUS / CURRENT_TASK when material
→ issue concise construction card
→ local implementation
→ focused verification
→ independent web audit
→ merge / closeout
→ Control Alignment Gate
```

The concise construction card is not repository Authority and must not duplicate the full contract.

## Phase 1 audit scope

Before issuing any construction card, establish all of the following from the current `main` implementation.

### A. Runtime creation / reuse / rebuild / release ownership

Map exactly:

- `WebViewPool.webView(for:)` creation path;
- runtime reuse criteria;
- Browser Profile identity compatibility checks;
- rendering-profile rebuild criteria;
- runtime generation / WebView instance identity updates;
- `WebViewPool.release(slotID:)` teardown order;
- all per-Slot maps/sidecars held by `WebViewPool`;
- all production callers of release/rebuild paths.

Produce an explicit retain/ownership graph identifying which references must be severed before a released WebView can deallocate.

### B. Lifecycle / presentation ownership

Audit:

- all `SlotLifecycleCoordinator` inactive-plan/release paths;
- active / panel-visible / hidden-active-grace behavior;
- fullscreen source ownership;
- supplemental/companion visible profile ownership;
- `WebPanelContainerView` detach/reparent behavior;
- media protection and Attention protection interactions;
- memory-pressure behavior inherited from PR #162.

No Phase 1 design may allow a currently visible/fullscreen/supplemental-visible Runtime to be reclaimed.

### C. Observer / bridge / async teardown

Establish exact cleanup for:

- `SlotNavigationObserver`;
- navigation delegate ownership;
- ChatGPT Attention bridge;
- ChatGPT Response bridge;
- popup coordinator / UI delegate;
- `WKUserContentController` script-message handlers;
- pending health/liveness/page-app probes;
- pending Tasks/timers/callback closures;
- stale runtime-generation/navigation-generation rejection.

The audit must identify any reference that could retain the released WebView or accept a stale callback after replacement.

### D. Restore snapshot feasibility

Audit public `WKWebView.interactionState` behavior against FloatTabs' supported macOS baseline and current runtime configuration.

Freeze the intended ordering for:

```text
capture state
→ prepare release
→ teardown live Runtime
→ create fresh WKWebView with same Browser Profile/configuration
→ install document-start scripts/bridges
→ restore interactionState when valid
→ URL fallback when state is absent/invalid
```

Determine:

- capture timing;
- data type / availability behavior;
- whether Phase 1 state remains memory-local;
- invalidation rules when Browser Profile/rendering identity changes;
- back/forward/scroll restoration expectations;
- failure/fallback behavior;
- whether restore can introduce duplicate navigation or stale callbacks.

### E. Product / data safety

Prove the proposed Phase 1 design does not implicitly mutate/delete:

- Default/custom Browser Profile stores;
- cookies/login/session website data;
- persisted Slot configuration;
- durable unread state;
- user preferences/backups/recovery material.

Website Cache cleanup must remain outside Runtime reclamation except for already-authorized explicit cache policy behavior.

### F. Tests / benchmark gate

Freeze exact regression additions and benchmark evidence before construction.

Minimum intended coverage:

- create → capture → release → recreate → restore;
- stale callback rejection across runtime generation change;
- default/custom Browser Profile identity preservation;
- same-profile sibling behavior;
- rendering-profile rebuild interaction;
- active/fullscreen/supplemental-visible protection;
- release order and bridge/observer cleanup;
- URL fallback when interaction state is unavailable;
- 1 / 2 / 4 / 8 configured Slot memory matrix where feasible;
- pre-release, post-release after a bounded settle window, and post-restore memory evidence;
- restore latency and visible interaction correctness.

Do not claim exact per-Slot WebContent memory when public WebKit evidence cannot prove the mapping.

## Required Phase 1 audit output

The audit must end with a repository-authorized implementation contract containing:

1. exact production files/symbols to change;
2. files/symbols explicitly out of scope;
3. exact ownership/teardown sequence;
4. restore snapshot shape and lifetime;
5. exact tests to add/update;
6. benchmark method and measurements;
7. acceptance criteria;
8. STOP conditions;
9. rollback/recovery boundary;
10. confirmation that Phase 2+ semantics are not included.

Only after those facts are frozen in `CURRENT_TASK.md` / linked contract may a concise local construction card be issued.

## Phase 1 primary decision gate

The central question is:

```text
Does clean WKWebView reclamation produce a meaningful and repeatable memory reduction
without breaking Browser Profile/session/product-state invariants?
```

If **YES**, reconcile this task to `PHASE 1 IMPLEMENTATION` and issue the bounded construction card.

If **NO / UNKNOWN**, STOP the lifecycle-policy rollout and investigate teardown retention / WebKit process residency first. Do not proceed to Phase 2/3/4 on the assumption that release is an effective memory mechanism.

## Program invariants / prohibited shortcuts

Do not:

- delete/reset Browser Profile/session/website data to recover memory;
- treat Website Cache cleanup as Runtime reclamation;
- reuse one live WebView across unrelated Slots;
- emulate Chromium Freeze through broad JavaScript timer/task suppression;
- build the architecture around private WebKit process/media APIs;
- introduce manual permanent `WKProcessPool` topology as the primary optimization;
- make Diagnostics or Attention a competing Runtime writer;
- conflate durable unread with runtime Attention;
- claim the historical JSC root cause is fixed because memory/reclamation behavior improves;
- include Phase 2 Ready/Unread semantic changes in the Phase 1 implementation.

## STOP conditions

STOP and reconcile before product mutation if:

1. the frozen contract needs a material change;
2. Browser Profile/session/user-data safety cannot be preserved;
3. exact Web Runtime ownership/teardown cannot be established;
4. unknown overlapping unique work exists in the relevant lifecycle area;
5. a required repository-host gate is failing;
6. the proposed implementation depends on unsupported/private WebKit behavior for correctness;
7. Phase 1 evidence does not support meaningful memory reclamation;
8. implementation would cross into Phase 2+ semantics before Phase 1 closes.

## Next action

Perform the Phase 1 focused read-only audit. When the evidence is complete:

1. update `CURRENT_STATUS.md` with the verified findings;
2. reconcile this task to an exact `PHASE 1 IMPLEMENTATION` boundary or STOP disposition;
3. if implementation is authorized, issue one concise local execution card that points back to repository Authority instead of duplicating it.

Production release is not authorized by this task state.
