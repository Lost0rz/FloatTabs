# FloatTabs Runtime Lifecycle — Phase 2 Ready / Unread Decoupling Plan V1

**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Phase:** `2 — Ready / Unread Decoupling`  
**Status:** `ACCEPTED / FROZEN IMPLEMENTATION PLAN`  
**Baseline audited:** `main` at `e61b932ae88460232eeb39b1538797c0b7f65359`  
**Parent contract:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V2.md`

## 1. Objective

Phase 2 makes unseen-completion state survive `WKWebView` Runtime reclamation without keeping a completed Runtime resident merely because it has unread output.

The required ownership split is:

```text
ChatGPT page/runtime observation
        │
        ▼
WebAttentionCoordinator
  idle / generating / ready
  transient Runtime state
        │
        ├── generating => may protect live Runtime
        │
        └── completion handoff
                │
                ▼
ChatGPTUnreadResponseCoordinator
        │
        ▼
UnreadResponseStore
  durable unread Slot/response identity
        │
        ├── rail unread projection
        └── status-item unread projection
```

Phase 2 does not redesign generation detection, hibernation, residency timers, notification delivery, or attention visuals.

## 2. Read-only audit findings

Fresh source/test audit at the baseline established:

1. `UnreadResponseStore` already persists unread Slot IDs and response identity independently from Runtime Attention.
2. `ChatGPTUnreadResponseCoordinator` is already the independent canonical owner for durable unread/handled-response semantics. `runtimeReset` and `generationStarted` do not clear durable unread.
3. `WebAttentionCoordinator` is intentionally runtime-only, but `WebAttentionState.isAttentionProtected` currently returns true for both `.generating` and `.ready`.
4. `PanelController` injects `attentionCoordinator.isAttentionProtected(slotID)` into `SlotLifecycleCoordinator`; therefore an inactive hidden completion transitions to `.ready` and continues protecting its Runtime.
5. `PanelController.handleAttentionEvent` already performs the durable unread handoff synchronously before the final protection-ended lifecycle restart decision. This is the correct ordering boundary to preserve.
6. The rail unread indicator already projects `unreadResponseCoordinator.unreadSlotIDs` and therefore already survives Runtime reset/reclamation.
7. The menu-bar badge still derives its count from `attentionCoordinator.readySlotIDs`; therefore a Runtime reset can remove the menu badge even while durable unread remains recorded.
8. Existing lifecycle tests explicitly encode the old behavior that Ready remains Runtime-protected; those expectations must change while Generating protection remains unchanged.

No evidence requires a new persistence schema, a detector/bridge rewrite, a WebView lifecycle redesign, or a new notification mechanism for Phase 2.

## 3. Frozen ownership model

### 3.1 Runtime Attention

`WebAttentionCoordinator` remains the sole transient Attention state authority.

The existing states remain for Phase 2:

- `idle`
- `generating`
- `ready`

`ready` is retained as transient Runtime/diagnostic compatibility state. It is **not** durable unread truth and is **not** a Runtime-residency reason.

Frozen residency semantic:

```text
idle       => not Attention-protected
ready      => not Attention-protected
generating => Attention-protected
```

Do not remove the `ready` state merely to perform this phase. Removing it would broaden the semantic migration unnecessarily.

### 3.2 Durable Unread

`ChatGPTUnreadResponseCoordinator` + `UnreadResponseStore` remain the only durable unseen-completion owner.

Durable unread must survive:

- hibernate;
- destructive Runtime replacement when the Slot itself remains valid;
- `runtimeReset`;
- recreation of a fresh `WKWebView`;
- app relaunch through the existing store;
- a later new generation until the prior unread response is actually acknowledged under existing rules.

Phase 2 must not add Runtime Attention state to Tab/Profile persistence or backup schema.

### 3.3 Presentation truth

Any presentation that must survive Runtime reclamation must read durable unread, not transient `ready`.

Frozen projections:

- Tab rail / overflow unread indicator: continue using durable unread.
- Menu/status-item badge count: switch from transient Ready count to durable unread count.
- Internal diagnostics may still report transient Attention state separately.

Production API names that currently expose `readyCount` for the status-item unread badge should be renamed to `unreadCount` (or an equally explicit durable-unread name) rather than passing durable unread through semantically false Ready naming.

## 4. Completion handoff ordering

For a valid completion, preserve one MainActor-owned synchronous handoff boundary:

```text
capture pre-transition Attention state + actual visibility facts
→ route completion through WebAttentionCoordinator
→ commit/record durable unread outcome through ChatGPTUnreadResponseCoordinator
→ synchronize durable unread presentation
→ emit existing generation-completed callback as applicable
→ evaluate Attention protection transition
→ if protection ended, restart normal inactive lifecycle boundary
```

Critical rule:

**Durable unread must be committed before a protection-ended lifecycle restart can make the Runtime eligible for hibernation.**

No async gap, timer, notification callback, or second writer may be inserted between durable-unread commit and the lifecycle restart decision.

For a hidden valid completion:

```text
generating (protected)
→ ready (not protected)
→ durable unread marked
→ normal inactive lifecycle plan restarted if needed
→ Runtime may later hibernate under existing policy
→ durable unread remains
```

For a visible valid completion:

```text
generating (protected)
→ idle (not protected)
→ handled/visible semantics remain existing behavior
→ no unread mark
→ normal inactive lifecycle may resume if applicable
```

A stray/invalid completion must not create durable unread or a false Ready state.

## 5. Runtime reset and acknowledgement

`runtimeReset` may continue clearing transient Runtime Attention state to `idle`. It must not clear durable unread.

Acknowledgement remains governed by the existing presentation/response-identity rules in `PanelController` and `ChatGPTUnreadResponseCoordinator`:

- selecting a Slot while not actually presented does not clear unread;
- response-identity mismatch does not clear the newer unread response;
- actual acknowledged presentation clears durable unread under existing rules;
- if a live Runtime still has transient `.ready`, its acknowledgement may also move transient Attention to `.idle`, but that transient transition is not the durable source of truth.

## 6. Frozen production scope

Authorized production files for Phase 2 implementation:

- `FloatTabs/Web/WebAttentionCoordinator.swift`
- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/App/AppCoordinator.swift`
- `FloatTabs/MenuBar/StatusItemController.swift`

Expected responsibility:

### `WebAttentionCoordinator.swift`
- change Runtime-protection semantics so only Generating protects;
- retain transient Ready state and existing transition diagnostics.

### `PanelController.swift`
- preserve completion-to-durable-unread handoff ordering;
- derive persistent unread presentation count from `ChatGPTUnreadResponseCoordinator`;
- trigger the existing protection-ended lifecycle restart after hidden completion now that Ready is non-protecting;
- keep acknowledgement visibility/identity semantics unchanged.

### `AppCoordinator.swift`
- wire status-item presentation using durable unread count/callback naming;
- do not add Phase 3 native notification behavior.

### `StatusItemController.swift`
- rename Ready-specific badge-count vocabulary to durable Unread vocabulary without changing badge rendering behavior.

Do **not** modify these production areas without STOP/reconciliation:

- `ChatGPTAttentionBridge.swift`
- `ChatGPTResponseBridge.swift`
- `ChatGPTResponseExtraction.swift`
- `ChatGPTUnreadResponseCoordinator.swift`
- `UnreadResponseStore.swift`
- `SlotLifecycleCoordinator.swift`
- `WebViewPool.swift`
- Browser Profile datastore/persistence code
- Tab/Profile schema
- External rail attention renderer/styles

If fresh implementation evidence proves one of those files must change for correctness, stop and reconcile the frozen scope before mutation.

## 7. Authorized test scope

Expected Phase 2 test changes are bounded to:

- `FloatTabsTests/WebAttentionCoordinatorTests.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebAttentionCrossFeatureTests.swift`
- `FloatTabsTests/WebAttentionPresentationTests.swift`
- `FloatTabsTests/UnreadResponseTests.swift` only for narrowly necessary durable-survival regression coverage

Existing bridge/detector/response tests remain regression gates but should not require production redesign.

## 8. Required regression matrix

At minimum prove:

1. Idle is not Runtime-protected.
2. Generating remains Runtime-protected.
3. Hidden completion may enter transient Ready, but Ready is not Runtime-protected.
4. A release timer that previously skipped while Generating gets a fresh lifecycle boundary after completion.
5. An inactive Cold/Warm Slot with durable unread can hibernate after the existing policy delay.
6. Eligible critical-Warm reclaim may hibernate a Ready/unread Slot while Generating remains protected.
7. Durable unread exists before the lifecycle restart/reclaim boundary is allowed to proceed.
8. Hibernate/runtime reset/fresh Runtime recreation does not clear durable unread.
9. New generation does not clear prior durable unread.
10. Visible completion does not create unread.
11. Stray/invalid completion does not create unread.
12. Response-identity acknowledgement/deduplication behavior remains unchanged.
13. Menu/status-item badge derives from durable unread and survives transient Ready reset.
14. Rail/overflow unread projection remains durable-unread-based and unchanged.
15. Active/fullscreen/supplemental-visible/media protections remain unchanged.
16. No duplicate Runtime or duplicate unread record is created by hibernate/restore.

## 9. Verification gates

### Gate A — focused correctness

Run the narrowest Phase 2 tests first:

- WebAttentionCoordinator
- WebAttentionLifecycle
- UnreadResponse
- WebAttentionPresentation
- targeted WebAttentionCrossFeature cases

### Gate B — broad regression

Run the full XCTest suite. No new failures attributable to Phase 2.

### Gate C — build

- Debug arm64 build PASS
- Release arm64 build PASS

### Gate D — bounded real-runtime smoke

Using the current safe configuration and existing Slots only:

```text
inactive ChatGPT Slot starts generating
→ generation completes while not actually presented
→ durable unread appears
→ Runtime protection ends
→ after existing Warm/Cold policy boundary Runtime becomes non-resident
→ unread presentation remains
→ reselect Slot
→ exactly one fresh/restored Runtime appears
→ unread clears only after existing actual-presentation acknowledgement rules
```

Record resident Runtime identity/count and unread projection before/after hibernate and restore. Do not add temporary production Slots or change residency timers permanently merely to manufacture evidence.

### Gate E — required repository CI

`Build & Test (Apple Silicon arm64)` must pass on the literal implementation PR head using the established FloatTabs self-hosted runner.

### Gate F — independent web audit

Audit exact diff, ownership, durable-state safety, lifecycle handoff ordering, tests/build/smoke evidence, host gates, and absence of Phase 3/4 leakage before merge.

### Gate G — human UI acceptance

`HUMAN_UI_ACCEPTANCE=PENDING` until the user explicitly checks the installed/running build.

Minimum human checks:

1. hidden completion still shows unread on the Tab rail;
2. menu-bar unread badge remains after the completed Slot Runtime has been reclaimed;
3. returning to that Slot restores the conversation/session correctly;
4. merely selecting while not actually presented does not prematurely clear unread;
5. actual presentation clears unread as before;
6. a currently generating inactive ChatGPT Slot is not reclaimed;
7. no obvious focus/fullscreen regression.

Automated UI checks may support debugging but cannot set this gate to PASS.

## 10. Explicit non-scope

Phase 2 does not include:

- native macOS completion notifications (Phase 3);
- Runtime budget/ranking, new TTLs, or 1/2/4/8 scale benchmark (Phase 4);
- background generation thrift policy (Phase 5);
- perceived-fast restore tuning (Phase 6);
- server Push/service-worker work (Phase 7);
- ChatGPT detector/extraction redesign;
- Attention sound behavior changes;
- unread visual-style redesign;
- Browser Profile/session schema changes;
- user-data migration/reset/deletion;
- release/version bump.

## 11. STOP conditions

STOP and reconcile if any of the following is observed:

- durable unread can be lost by hibernate, Runtime reset, or Runtime recreation;
- lifecycle reclaim can begin before the durable-unread handoff is committed;
- a currently Generating Slot becomes reclaimable through the Phase 2 change;
- correct implementation requires changing detector/bridge/response extraction semantics;
- correct implementation requires modifying the unread persistence schema/store behavior;
- correct implementation requires changing `SlotLifecycleCoordinator` timers/policy or `WebViewPool` hibernate semantics;
- menu/rail unread projections would require two competing unread authorities;
- Browser Profile/session/configuration data must be mutated to make the phase work;
- implementation leaks into native notification or Runtime-budget work;
- required focused/full tests, Debug/Release build, or repository CI fail due to the change;
- human UI acceptance fails;
- overlapping unique work makes the writer unsafe.

## 12. Rollback

Phase 2 is rollback-safe at the semantic projection boundary:

- restore Ready to residency protection;
- restore status badge source to the previous projection if necessary;
- preserve the existing durable unread store/data unchanged;
- do not wipe unread, Browser Profiles, cookies, sessions, Slot configuration or backups;
- Phase 1 hibernate/restore remains independently valid.

## 13. Merge readiness

Phase 2 is merge-ready only when:

- implementation remains inside the frozen production/test scope;
- Generating remains protected and Ready no longer protects Runtime;
- durable unread is committed before lifecycle reclaim resumes;
- unread survives Runtime reclamation/recreation;
- durable unread owns persistent rail/menu projection;
- focused/full tests and Debug/Release builds pass;
- bounded real-runtime smoke passes;
- required exact-head CI passes;
- independent web audit passes;
- human UI acceptance passes.

No release is authorized by this plan.