# FloatTabs Runtime Lifecycle & Memory Contract V1

**Status:** `ACCEPTED / FROZEN`
**Accepted:** `2026-10-31`
**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`
**Product baseline:** `main` after PR #162 merge (`26d1669198a6f94faa769fb27d2cd00d0fcd1184`)

This document is the accepted architecture contract for the Runtime Lifecycle / Memory program. It defines the target ownership model, phase order, invariants, gates, and non-goals. It does not claim that later phases are already implemented.

A material change to this contract requires explicit task reconciliation in `CURRENT_TASK.md` and an intentional contract revision. Historical task cards, chat summaries, PR descriptions, and local notes do not override this contract.

## 1. Problem statement

FloatTabs is a long-lived Web App container. Persistent Slots must remain quickly accessible while live `WKWebView` runtimes are allowed to be disposable when they are not needed.

The current implementation already separates persisted Slot/Profile data from transient Web runtime, but memory use can remain high because multiple heavyweight Web runtimes stay resident and lifecycle policy is primarily per-Slot/timer driven. In particular, runtime Attention `ready` currently participates in residency protection even though durable unread state already exists independently.

The program goal is:

> Keep persistent Slot identity, Browser Profiles, sessions, unread state, and user configuration durable while treating live `WKWebView` instances as a bounded cache that can be safely reclaimed and restored.

Primary success dimensions:

1. materially lower steady-state memory with multiple long-lived Web App Slots;
2. no loss of Browser Profile cookies/session/website data or Slot configuration;
3. no loss of ChatGPT completion/unread signaling when an inactive runtime is reclaimed;
4. bounded and measurable restore latency;
5. no new runtime-ownership ambiguity;
6. truthful diagnostics without unsupported per-Slot WebContent attribution claims.

## 2. Non-negotiable invariants

### 2.1 Persistent product state is not runtime state

The durable product layer remains independent from `WKWebView` lifetime:

```text
Persistent Slot
├─ Web App URL / configuration
├─ Browser Profile identity
├─ rendering / viewport / zoom configuration
├─ durable unread / response identity where applicable
└─ disposable WKWebView runtime
```

Destroying a runtime must not implicitly delete or reset:

- Browser Profiles;
- cookies / login sessions;
- website data stores;
- Slot configuration;
- preferences;
- backups / recovery material;
- durable unread state.

### 2.2 Browser Profile ownership stays unchanged

`BrowserProfileDataStoreProvider` remains the website-data-store authority. Default Profile continues to use the real default WebKit data store; custom profiles continue to use their UUID-backed WebKit data stores on supported macOS versions.

Runtime reclamation is never permission to call website-data deletion APIs.

### 2.3 Runtime ownership stays in Web

`WebViewPool` remains the live Web runtime mechanism owner. `SlotLifecycleCoordinator` remains the lifecycle execution boundary unless a later accepted phase deliberately refactors that responsibility.

Tabs own product/configuration state. Attention/Response own bounded provider/runtime signals and projections. Diagnostics records evidence only.

### 2.4 One canonical writer per state

Do not create a second authoritative source for:

- active Slot;
- Browser Profile identity;
- runtime generation / WebView instance identity;
- Attention state;
- unread state;
- lifecycle disposition.

Read-only projections are allowed; competing writers are not.

### 2.5 Recovery is not root-cause proof

Reload, runtime rebuild, hibernation/recreation, restart, or memory reclamation may demonstrate a recovery boundary. They do not prove the historical JSC/WebContent root cause. The historical JSC crash family remains `ROOT CAUSE UNKNOWN` unless fresh causal evidence establishes otherwise.

## 3. Accepted target architecture

### 3.1 Runtime is a cache

The accepted target model is:

```text
Persistent Slot / Browser Profile / Unread State
                    │
                    ▼
         Runtime Restore Snapshot
                    │
                    ▼
             WKWebView Cache
              LIVE / NIL
                    │
                    ▼
              WebViewPool
```

A Slot may exist without a live `WKWebView`.

### 3.2 Restore snapshot

Before policy becomes more aggressive, FloatTabs must establish a safe hibernation primitive. The intended restore snapshot is bounded runtime-recovery metadata, initially memory-local, and may include:

- Slot identity;
- current URL;
- `WKWebView.interactionState` when safely available;
- runtime/navigation generation metadata required to reject stale callbacks;
- fallback information needed to reload the current URL if interaction-state restoration is unavailable or invalid.

The restore snapshot is not a new Browser Profile store and is not permission to persist arbitrary page content.

### 3.3 Runtime factual state and policy intent are separate

The target design separates observed runtime state from product/user intent.

Representative factual runtime states:

```text
UNLOADED
LOADING
ACTIVE
BACKGROUND
RECLAIMABLE
RESTORING
```

Exact enum names may change during implementation audit, but the semantic separation is frozen: factual runtime state must not be conflated with user residency preference.

### 3.4 Protection reasons are independent facts

The policy evaluates explicit protection facts rather than encoding every exception into one residency enum.

Expected protection inputs include:

- user-visible / active presentation;
- fullscreen / supplemental visible presentation;
- active ChatGPT generation;
- active media;
- camera / microphone capture where observable through supported APIs;
- other task-critical activity proven by a specific provider contract;
- explicit user `Keep Live` override if retained by the final UI.

A protection reason is not itself a second lifecycle owner. It is an input to the lifecycle policy.

### 3.5 Central runtime policy

The accepted target is a pure, testable policy that decides which resident runtimes are reclaimable and how candidates are ranked. The lifecycle driver supplies current facts and executes the result; it does not bury the policy inside independent per-Slot timers.

Policy inputs may include:

- protection facts;
- last-used time / recency;
- revisit frequency where useful and measurable;
- resident runtime count;
- memory-pressure level;
- explicit keep-live override;
- bounded configuration needed for rollout/compatibility.

The policy must be unit-testable without constructing `WKWebView`, windows, or real timers.

### 3.6 Runtime budget

After hibernation/restore is proven effective, FloatTabs may enforce a bounded background live-runtime budget. The exact default budget is evidence-gated and must not be frozen by guesswork before benchmark results exist.

The policy shape is accepted:

```text
visible / fullscreen      -> KEEP
active generation         -> KEEP
protected media/capture   -> KEEP
recent high-value runtime -> CACHE candidate
other eligible runtime    -> RECLAIMABLE
```

The exact ranking weights, idle thresholds, and live-runtime budget remain implementation decisions gated by measured evidence.

## 4. Attention, unread, and notification contract

### 4.1 Runtime Attention and durable unread are different states

`WebAttentionCoordinator` remains runtime-only. `UnreadResponseStore` / `ChatGPTUnreadResponseCoordinator` remain the durable unread authority.

The program explicitly rejects this long-term coupling:

```text
ready == keep WKWebView alive indefinitely
```

The intended transition is:

```text
generating
  -> validated generationFinished
  -> durable unread/response identity committed when applicable
  -> native presentation synchronized
  -> runtime may become reclaimable when no other protection reason remains
```

No phase may release a runtime before the completion/unread handoff is durably admitted.

### 4.2 Generation remains runtime-protected

A provider task that still requires the live page runtime to complete remains protected while generating, unless a future separately accepted server-push design proves that the work can survive WebView destruction.

### 4.3 Native completion notification

The accepted bounded notification goal is a FloatTabs-owned ChatGPT completion notification, not a general browser notification platform.

Expected flow:

```text
validated ChatGPT completion
  -> durable unread state
  -> native completion notification
  -> notification carries Slot identity
  -> click activates FloatTabs and selects/restores the exact Slot
```

Notification delivery must not fall back to opening the URL in the default browser.

Permission denied, duplicate completion, stale response identity, foreground app behavior, hidden panel behavior, and reclaimed-runtime behavior require explicit verification.

A generic Web Notifications API bridge is out of scope unless separately authorized later.

## 5. Residency UI direction

The current persisted `Hot / Warm / Cold` values are compatibility state, not the target primary policy model.

The accepted product direction is to move toward automatic lifecycle management with at most a bounded user override such as:

```text
Automatic
Keep Live
```

Do not delete or reinterpret persisted residency data without an explicit migration design and tests. UI simplification occurs only after automatic policy behavior is proven.

## 6. Memory-pressure contract

Memory pressure is a policy input, not a command to delete user data or indiscriminately reset every runtime.

Accepted shape:

```text
normal   -> normal runtime budget
warning  -> tighter reclaim policy for eligible background runtimes
critical -> reclaim all eligible background runtimes allowed by current protection contract
```

The exact warning/critical behavior is phase-gated. Existing PR #162 behavior (`warning` diagnostics-only; bounded `critical` Warm eviction) remains production truth until a later phase intentionally replaces it.

Do not clear global caches or website data as a generic memory-pressure response.

## 7. Background generation thrift

Long-running background ChatGPT generation is a distinct optimization surface.

While a Slot is inactive but still generating, FloatTabs may reduce its own non-essential work while preserving the live work required for completion detection. Candidate reductions include:

- periodic liveness/probe work not required for the active generation;
- redundant DOM resynchronization;
- non-essential visual/presentation updates;
- high-frequency diagnostics that do not change a product decision.

PR #162's suppression of periodic cross-world liveness JavaScript while canonical Attention is `generating` is accepted precedent for this direction.

This phase must not claim that FloatTabs can materially shrink ChatGPT's own JavaScript heap while keeping that same heavyweight runtime alive.

## 8. Perceived-fast restore

Only after runtime reclamation is safe and effective may FloatTabs add a lightweight restore placeholder/preview.

A preview may show a bounded recent conversation representation while the real WebView restores, but it is never canonical conversation state and must not become a second ChatGPT database.

Initial preference is memory-local / bounded. Durable extraction of arbitrary conversation content is not authorized by this contract.

## 9. Optional future server-push research

A future research phase may ask whether a ChatGPT task can continue server-side after the submitting WebView is destroyed and still deliver a trustworthy completion signal to FloatTabs.

This is **not** assumed today and is not a prerequisite for the main program.

Until proven otherwise:

```text
active generation -> requires live runtime
```

## 10. Explicit non-goals / prohibited shortcuts

The program does not authorize:

1. reusing one `WKWebView` instance across unrelated Slots;
2. manual permanent `WKProcessPool` topology as the primary optimization;
3. JavaScript hacks that emulate Chromium Freeze by globally suppressing page timers/tasks;
4. private WebKit process identifiers or private media APIs as canonical product truth;
5. deleting cookies, Browser Profile stores, website data, preferences, backups, or session data to reclaim runtime memory;
6. treating cache cleanup as runtime lifecycle cleanup;
7. making Diagnostics the policy owner;
8. claiming exact per-Slot WebContent memory attribution when public WebKit APIs cannot prove it;
9. claiming historical JSC root cause fixed because hibernation/recreation reduces crashes or memory;
10. broad generic browser expansion unrelated to persistent Web App Slots.

## 11. Frozen phase order

Implementation proceeds in this dependency order unless this contract is explicitly revised.

### Phase 0 — Authority / contract freeze

- reconcile PR #162 as merged;
- align `CURRENT_STATUS.md` / `CURRENT_TASK.md`;
- publish this contract and architecture navigation;
- authorize only the next phase's audit, not broad product mutation.

### Phase 1 — Safe Hibernate + Restore

Goal: prove a live runtime can be captured, cleanly torn down, reclaimed, recreated with the same Browser Profile, and restored with bounded user-visible loss.

Primary evidence gate: `release -> meaningful memory reduction`. If memory does not materially fall after clean release, STOP and investigate teardown retention / WebKit process residency before building aggressive policy.

### Phase 2 — Ready / Unread decoupling

Goal: durable completion/unread state survives runtime reclamation; `ready` no longer automatically means indefinite WebView residency.

### Phase 3 — Native ChatGPT Completion Notification

Goal: completion can notify the user and route back to the exact Slot even when the panel is hidden or the runtime has been reclaimed.

### Phase 4 — Automatic Runtime Budget / Policy

Goal: replace timer-centric Hot/Warm/Cold runtime decisions with a central pure policy, evidence-based candidate ranking, and bounded resident-runtime budget.

### Phase 5 — Long-running Background Generation Thrift

Goal: reduce FloatTabs-owned CPU/probe/rendering overhead while inactive ChatGPT runtimes must remain alive for generation.

### Phase 6 — Perceived-fast Restore

Goal: make reclaimed Slot selection feel immediate without keeping heavyweight WebViews resident merely for visual continuity.

### Optional Phase 7 — Server-push / service-worker research

Research only until independently proven and explicitly authorized.

## 12. Per-phase development gate

Every phase after Phase 0 uses this sequence:

```text
READ AUTHORITIES
  -> FOCUSED READ-ONLY AUDIT
  -> FREEZE EXACT PHASE SCOPE / FILES / TESTS / STOP CONDITIONS
  -> UPDATE CURRENT_TASK / CURRENT_STATUS WHEN MATERIAL
  -> ISSUE CONCISE EXECUTION CARD
  -> LOCAL IMPLEMENTATION
  -> FOCUSED VERIFICATION
  -> INDEPENDENT WEB AUDIT
  -> MERGE / CLOSEOUT
  -> CONTROL ALIGNMENT GATE
```

The execution card is intentionally concise and must not duplicate the full repository task contract. Repository authority remains in the control files and this accepted contract.

No implementation phase may be skipped directly from high-level design to code mutation.

## 13. Phase 1 pre-implementation audit requirements

Before any Phase 1 product mutation, the audit must establish at minimum:

1. the complete `WebViewPool.release/rebuild/create` ownership and retain graph;
2. `SlotLifecycleCoordinator` release preparation/order and all release callers;
3. `WebPanelContainerView` / fullscreen / supplemental-visible ownership at detach/reparent boundaries;
4. `SlotNavigationObserver` invalidation and pending navigation/probe tasks;
5. Attention bridge, Response bridge, popup coordinator, script-message handlers and async task teardown;
6. `WKWebView.interactionState` availability/behavior on the supported macOS baseline and safe fallback behavior;
7. rebuild behavior when Browser Profile or rendering profile changes;
8. stale runtime/navigation callback rejection after restore;
9. current test coverage and exact missing regressions;
10. a benchmark plan comparing resident counts and memory before release, after release, and after restore;
11. explicit STOP conditions if release fails to reclaim memory or restore breaks session/profile invariants.

The output of that audit is the exact Phase 1 construction scope and a concise local execution card.

## 14. Verification matrix for the program

At relevant gates, cover at least:

- 1 / 2 / 4 / 8 configured Slots;
- active vs inactive;
- panel visible vs hidden;
- generating vs idle vs completed-unread;
- background media/capture where supported;
- Default Profile and custom Browser Profile;
- same-profile sibling Slots;
- runtime release / restore / rebuild;
- memory warning / critical pressure;
- app restart and durable unread preservation where applicable;
- notification permission granted/denied and click routing;
- restore latency and interaction correctness.

Memory evidence should distinguish FloatTabs host footprint from observable WebKit helper/content footprint where possible. Do not assign a child-process measurement to a specific Slot without proof.

## 15. Acceptance / change control

This contract is `FROZEN` for the current program.

A proposed change to:

- phase order;
- ownership boundaries;
- persistence/data-safety rules;
- Attention/unread handoff semantics;
- notification routing semantics;
- prohibited shortcuts;
- benchmark/STOP gates;

requires:

1. focused evidence;
2. explicit reconciliation in `CURRENT_TASK.md`;
3. an updated/revisioned contract;
4. no product mutation under the changed assumption until the revised contract is accepted.
