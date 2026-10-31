# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`
**Title:** Runtime Lifecycle / Memory redesign — governed phased implementation
**Status:** `ACTIVE / PHASE 0 CONTROL FREEZE`
**Mode:** `CONTROL / DESIGN FREEZE`
**Task class:** `HIGH-RISK WEB RUNTIME LIFECYCLE / MEMORY`
**Product baseline:** `26d1669198a6f94faa769fb27d2cd00d0fcd1184`
**Active PR:** `#163` / `codex/ft-runtime-lifecycle-memory-001-phase0-docs`
**Frozen contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`
**JSC root cause:** `UNKNOWN`

## Program objective

Reduce FloatTabs steady-state resource use while preserving the product promise of persistent, quickly accessible Web App Slots and isolated persistent Browser Profiles.

The accepted architecture treats live `WKWebView` instances as disposable/bounded Runtime cache only after safe capture/release/restore is proven. Persistent Slot configuration, Browser Profile website data, user sessions, durable unread state, preferences, backups, and recovery data remain outside Runtime lifetime.

## Current authorization

### Authorized now — Phase 0 only

The current PR may change only control/design/navigation documentation required to freeze this program:

- `AGENTS.md`;
- `CURRENT_STATUS.md`;
- `CURRENT_TASK.md`;
- `docs/architecture/README.md`;
- `docs/architecture/DOMAIN_MAP.md`;
- `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`.

No product/runtime source mutation is authorized in Phase 0.

### Automatically authorized after Phase 0 merge — Phase 1 audit only

Once PR #163 is merged and control alignment on `main` is verified, the next authorized work is a **focused read-only Phase 1 pre-implementation audit**.

That audit may read production source, tests, current runtime/benchmark seams, Apple/WebKit public API documentation, and relevant open-source references. It may update repository control/design documents to freeze the exact Phase 1 implementation boundary.

It may **not** mutate Runtime product code until this task is reconciled from `PHASE 1 AUDIT` to an explicit `PHASE 1 IMPLEMENTATION` boundary.

## Accepted/frozen architecture direction

The complete contract lives in `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V1.md`. The following summary is a routing aid only.

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
0  Authority / contract freeze
1  Safe Hibernate + Restore
2  Ready / Unread decoupling
3  Native ChatGPT Completion Notification
4  Automatic Runtime Budget / Policy
5  Long-running Background Generation Thrift
6  Perceived-fast Restore
7  Optional server-push / service-worker research
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

## Phase 0 acceptance criteria

PR #163 is ready to close Phase 0 only when:

1. PR #162 is recorded as merged at `26d1669198a6f94faa769fb27d2cd00d0fcd1184`;
2. historical JSC root cause remains `UNKNOWN` and no crash-elimination claim is introduced;
3. the lifecycle/memory contract is present and marked `ACCEPTED / FROZEN`;
4. `AGENTS.md` contains the durable phase/audit execution gate;
5. architecture README and Domain Map route future work to the frozen contract;
6. STATUS and TASK clearly identify the current phase and next gate;
7. the PR contains no product/runtime code change;
8. required GitHub check `Build & Test (Apple Silicon arm64)` is not failing;
9. final read-only diff/Authority audit finds no scope or ownership contradiction.

If these pass, mark PR #163 ready and merge using the repository's normal accepted merge method. Production release is not authorized by Phase 0.

## Phase 1 focused audit contract

The first product phase is **Safe Hibernate + Restore**, but implementation is not yet authorized.

Before issuing a construction card, the audit must establish all of the following.

### Runtime ownership / teardown

- exact `WebViewPool.webView(for:)` create/reuse/rebuild path;
- exact `WebViewPool.release(slotID:)` teardown path and every retained sidecar keyed by Slot;
- navigation delegate/observer invalidation;
- Attention bridge invalidation;
- Response bridge invalidation;
- popup coordinator / UI delegate lifetime;
- `WKUserContentController` script-message-handler cleanup;
- pending async tasks, probe callbacks, timers, closures, and stale runtime/navigation generation rejection;
- container/superview removal and any fullscreen/supplemental-visible reparenting boundary.

### Restore state

Audit `WKWebView.interactionState` against the current macOS support baseline and FloatTabs runtime model:

- capture timing;
- type/availability behavior;
- restore ordering relative to WebView creation, user scripts, Browser Profile data store and initial load;
- navigation/back-forward/scroll behavior;
- fallback to current URL when state is absent/invalid;
- whether the snapshot stays memory-local in Phase 1;
- invalidation when rendering profile / Browser Profile identity materially changes.

### Product/data invariants

Prove the proposed Phase 1 design does not implicitly mutate/delete:

- Default/custom Browser Profile stores;
- cookies/login/session website data;
- persisted Slot configuration;
- durable unread state;
- user preferences/backups/recovery material.

### Tests / benchmark

Freeze the exact regression additions and benchmark evidence before construction. At minimum cover:

- create → capture → release → recreate → restore;
- stale callback rejection across runtime generation change;
- default/custom Browser Profile identity preservation;
- same-profile sibling behavior;
- rendering-profile rebuild interaction;
- active/fullscreen/supplemental-visible protection;
- release order and bridge/observer cleanup;
- URL fallback when interaction state is unavailable;
- 1/2/4/8 configured Slot memory matrix where feasible;
- pre-release, post-release (+ bounded settle window), and post-restore memory evidence;
- restore latency / visible correctness.

Do not claim exact per-Slot WebContent memory when public WebKit evidence cannot prove the mapping.

## Phase 1 primary decision gate

The central question is:

```text
Does clean WKWebView reclamation produce a meaningful and repeatable memory reduction
without breaking Browser Profile/session/product-state invariants?
```

If **YES**, Phase 1 implementation can be frozen and a concise construction card can be issued.

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
- claim the historical JSC root cause is fixed because memory/reclamation behavior improves.

## STOP conditions

STOP and reconcile before product mutation if:

1. PR #163 is not merged / its control state is stale;
2. the frozen contract needs a material change;
3. Browser Profile/session/user-data safety cannot be preserved;
4. exact Web Runtime ownership/teardown cannot be established;
5. unknown overlapping unique work exists in the relevant lifecycle area;
6. a required repository-host gate is failing;
7. the proposed implementation depends on unsupported/private WebKit behavior for correctness;
8. Phase 1 evidence does not support meaningful memory reclamation;
9. implementation would cross into Phase 2+ semantics before Phase 1 closes.

## Next action

1. Complete PR #163 control/docs-only diff.
2. Run repository-host checks and independent read-only audit.
3. Merge PR #163 if Phase 0 acceptance passes.
4. Verify `main` control alignment.
5. Enter **Phase 1 focused read-only pre-implementation audit**.
6. Update this task with exact Phase 1 implementation scope/tests/STOP conditions.
7. Only then issue the concise local construction card.

Production release is not authorized by this task state.
