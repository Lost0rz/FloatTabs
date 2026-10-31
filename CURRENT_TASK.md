# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`
**Title:** Runtime Lifecycle / Memory redesign — governed phased implementation
**Status:** `ACTIVE / PHASE 1 FOCUSED AUDIT`
**Mode:** `AUDIT`
**Task class:** `HIGH-RISK WEB RUNTIME LIFECYCLE / MEMORY`
**Main after Historical Doc Gate:** `9ade3652aef9f4f37d8c729d42dce1680c0d13c6`
**Pre-program product baseline:** `26d1669198a6f94faa769fb27d2cd00d0fcd1184`
**Frozen contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`
**JSC root cause:** `UNKNOWN`

## Program objective

Reduce FloatTabs steady-state resource use while preserving persistent Web App Slots, isolated Browser Profiles, user sessions/data, reliable completion state and fast return-to-interaction.

The accepted architecture treats live `WKWebView` instances as bounded/disposable Runtime cache only after safe capture/release/restore is proven.

## Completed gates

```text
PHASE_0_PR=#163 MERGED
PHASE_0_CONTROL_ALIGNMENT_PR=#164 MERGED
HISTORICAL_DOC_PR=#165 MERGED
HISTORICAL_DOC_PR_HEAD=bd94906450f721c0fbd5bf3dd58fe98ece312885
HISTORICAL_DOC_MERGE=9ade3652aef9f4f37d8c729d42dce1680c0d13c6
HISTORICAL_DOC_REQUIRED_CI_RUN=41206877144 PASS
HISTORICAL_DOC_CHANGED_PATHS=39 MARKDOWN/CONTROL ONLY
PRODUCT_RUNTIME_CODE_CHANGED=NO
```

The historical-document gate added `docs/README.md`, durable `AGENTS.md` routing, directory status indexes, and Historical/Superseded wrappers with original bodies preserved under archive paths. Historical labels no longer create current Authority.

## Current authorization — Phase 1 audit only

The only authorized engineering work is a **focused read-only pre-implementation audit** for:

`Phase 1 — Safe Hibernate + Restore`

The audit may:

- read production source and regression tests;
- inspect current repository history/PR/runtime evidence relevant to the lifecycle boundary;
- inspect supported public Apple/WebKit API documentation;
- inspect bounded open-source WebKit references;
- define non-mutating benchmark seams/plans;
- update control/design documents to freeze exact Phase 1 implementation scope after evidence is complete.

The audit may **not** mutate Runtime product code.

Product mutation becomes authorized only after this task is intentionally reconciled to `ACTIVE / PHASE 1 IMPLEMENTATION` with exact files/symbols, ownership/teardown order, tests, benchmark plan, acceptance and STOP conditions.

## Accepted/frozen architecture direction

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

Ownership invariants:

- `WebViewPool` remains live Web Runtime mechanism owner.
- `SlotLifecycleCoordinator` remains lifecycle execution boundary unless a later accepted phase deliberately refactors it.
- Browser Profile / `WKWebsiteDataStore` ownership stays independent from Runtime policy/lifetime.
- Attention, Response, Unread, Presentation, Persistence, Diagnostics and Website Cache remain separate authorities.
- Phase 1 must not implement Phase 2 Ready/Unread semantic changes or Phase 4 automatic budget policy.

## Phase 1 focused audit contract

### A. Runtime create / reuse / rebuild / release

Map from current `main`:

- exact `WebViewPool.webView(for:)` creation path;
- compatibility/reuse criteria;
- Browser Profile identity checks;
- rendering-profile rebuild conditions;
- runtime-generation / WebView-instance identity updates;
- exact `release(slotID:)` teardown sequence;
- every WebViewPool per-Slot map/sidecar and reference edge;
- every production caller that invokes release/rebuild/recovery replacement.

Produce an explicit retain/ownership graph and identify every reference that must be severed before a released WebView is eligible for deallocation.

### B. Lifecycle / presentation boundary

Audit:

- all `SlotLifecycleCoordinator` inactive-plan/release paths;
- active/panel-visible/hidden-active-grace semantics;
- fullscreen source ownership;
- supplemental/companion visible ownership;
- `WebPanelContainerView` attach/detach/reparent behavior;
- media protection and Attention protection interactions;
- current warning/critical memory-pressure semantics inherited from PR #162.

A visible/fullscreen/supplemental-visible Runtime must not become reclaimable in Phase 1.

### C. Observer / bridge / async teardown

Establish cleanup/retention for:

- `SlotNavigationObserver` and navigation delegate;
- ChatGPT Attention bridge;
- ChatGPT Response bridge;
- popup coordinator / UI delegate;
- `WKUserContentController` script-message handlers;
- pending health/liveness/page-app probes;
- pending Tasks/timers/callback closures;
- runtime-generation/navigation-generation stale-result rejection.

Identify any retained reference that could keep a released WebView alive or accept a stale callback after replacement.

### D. Restore snapshot feasibility

Audit public `WKWebView.interactionState` against FloatTabs supported macOS baseline and current configuration.

Freeze ordering for:

```text
capture state
→ prepare release
→ teardown Runtime
→ create fresh WKWebView with same Browser Profile/configuration
→ install scripts/bridges
→ restore interactionState when valid
→ bounded current-URL fallback when state is absent/invalid
```

Determine:

- availability/API type and OS support;
- capture timing;
- whether Phase 1 snapshot is memory-local only;
- invalidation when Browser Profile/rendering identity changes;
- back-forward/scroll/history expectations;
- duplicate-navigation risk;
- fallback/failure behavior;
- stale callback implications.

### E. Product/data invariants

Prove the proposed design does not implicitly mutate/delete:

- Default/custom Browser Profile stores;
- cookies/login/session website data;
- persisted Slot configuration/current URL;
- durable unread state;
- preferences/backups/recovery material.

Website Cache cleanup remains outside Runtime reclamation.

### F. Tests / benchmark

Freeze exact tests before construction. Minimum intended coverage:

- create → capture → release → recreate → restore;
- stale callback rejection across Runtime replacement;
- default/custom Browser Profile identity preservation;
- same-profile sibling behavior;
- rendering-profile rebuild interaction;
- active/fullscreen/supplemental-visible release protection;
- release order and observer/bridge cleanup;
- URL fallback when interactionState unavailable/invalid;
- 1 / 2 / 4 / 8 configured Slot matrix where feasible;
- pre-release, post-release after bounded settle, and post-restore memory evidence;
- restore latency and visible interaction correctness.

Do not claim exact per-Slot WebContent memory if public WebKit evidence cannot prove attribution.

## Required Phase 1 audit output

Before any construction card, freeze in repository Authority:

1. exact production files/symbols to change;
2. explicit out-of-scope files/symbols;
3. exact capture/release/teardown/restore sequence;
4. restore snapshot shape/lifetime/invalidation;
5. exact tests to add/update;
6. benchmark method and evidence threshold;
7. acceptance criteria;
8. STOP conditions;
9. rollback/recovery boundary;
10. confirmation that Phase 2+ semantics are excluded.

## Primary decision gate

```text
Does clean WKWebView reclamation produce a meaningful and repeatable memory reduction
without breaking Browser Profile/session/product-state invariants?
```

If evidence supports a safe Phase 1 design, reconcile to `PHASE 1 IMPLEMENTATION` and issue one concise local construction card.

If `NO / UNKNOWN`, STOP policy rollout and investigate teardown retention / WebKit process residency first. Do not advance Phase 2/3/4 based on an assumed reclamation mechanism.

## Prohibited shortcuts

Do not:

- delete/reset Browser Profile/session/website data to reclaim Runtime memory;
- treat Website Cache cleanup as Runtime reclamation;
- reuse one live WebView across unrelated Slots;
- emulate Chromium Freeze through broad JavaScript timer/task suppression;
- depend on private WebKit process/media APIs for correctness;
- introduce manual permanent `WKProcessPool` topology as the primary optimization;
- make Diagnostics or Attention a competing Runtime writer;
- conflate durable unread with runtime Attention;
- claim historical JSC root cause fixed because memory behavior improves;
- implement Phase 2+ semantics in Phase 1.

## STOP conditions

STOP and reconcile before product mutation if:

1. current Runtime ownership/teardown cannot be established;
2. Browser Profile/session/user-data safety cannot be preserved;
3. `interactionState` is unsupported/unreliable without a bounded fallback;
4. unknown overlapping unique lifecycle work exists;
5. required repository-host gates fail;
6. proposed correctness depends on private/unsupported WebKit behavior;
7. evidence cannot support meaningful Runtime memory reclamation;
8. implementation would cross into Phase 2+ before Phase 1 closes.

Production release is not authorized by this task state.
