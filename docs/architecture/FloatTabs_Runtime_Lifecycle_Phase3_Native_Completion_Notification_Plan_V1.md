# FloatTabs Runtime Lifecycle — Phase 3 Native ChatGPT Completion Notification Plan V1

**Status:** `ACCEPTED / FROZEN FOR PHASE 3 EXECUTION`  
**Program:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Program contract:** `FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md`  
**Baseline:** Phase 2 merged on `main`; persistent unread is independent from Runtime residency.

## 1. Objective

Phase 3 adds one native macOS projection for a completed unseen ChatGPT response:

```text
valid hidden completion
→ durable unread is marked
→ native completion notification may be delivered
→ Runtime may later be reclaimed
→ user taps notification
→ exact persistent Slot is selected and presented
→ existing Runtime restore/recreation path handles any missing WKWebView
→ existing presentation/acknowledgement rules decide when unread clears
```

A notification is a one-shot presentation/routing surface. It is **not** canonical unread state, Runtime state, or a second completion authority.

## 2. Focused audit findings

### 2.1 Existing completion and unread ownership are sufficient

Current production already separates:

- `ChatGPTAttentionBridge` / `WebAttentionCoordinator` — transient generation/Attention sensing;
- `ChatGPTUnreadResponseCoordinator` / `UnreadResponseStore` — durable unread truth;
- `PanelController` — completion handoff, presentation facts and lifecycle restart;
- `AppCoordinator` — app-level composition and existing completion-sound wiring.

`ChatGPTUnreadResponseCoordinator.handle(...)` already returns a bounded completion result. A valid hidden completion returns `.marked(...)` only after durable unread has been written. Visible completion, invalid completion and already-handled completion do not produce that result.

Therefore Phase 3 does **not** need new ChatGPT DOM detection, response extraction, persistence or Runtime lifecycle semantics.

### 2.2 Existing generic completion callback cannot be reused as the notification trigger

`PanelController.onChatGPTGenerationCompleted(slotID)` currently fires for any valid completion and drives the existing attention sound, including visible completion.

Native system notification should represent an **unseen response**, not every valid completion. Reusing that callback would either notify while the user is already reading the response or change existing sound semantics.

Phase 3 therefore adds a separate one-shot callback that fires only when the durable unread completion result is `.marked`.

### 2.3 Slot UUID is the only routing identity needed

`TabStore.select(id:)` validates a persistent Slot ID, changes the selected Slot and synchronously notifies the presentation owner. `PanelController.synchronizeSlotState()` already activates the selected Slot and obtains/restores its Runtime through the existing Phase 1/2 lifecycle path.

A notification route therefore carries only the persistent `Slot.id` UUID. It must never retain or encode:

- `WKWebView` identity;
- Runtime generation;
- navigation/document token;
- Browser Profile data-store identity;
- response body/prompt content.

A deleted/stale Slot ID is a safe no-op and must never fall back to the currently active Slot.

### 2.4 No native notification implementation exists today

There is currently no `UNUserNotificationCenter` integration. Phase 3 adds one thin App-layer coordinator rather than placing notification behavior inside Attention, Unread, Tabs or Web Runtime owners.

The macOS notification delegate is installed during app launch. Authorization is requested contextually on the first real unseen-completion delivery attempt rather than at every launch.

### 2.5 No new persisted FloatTabs notification preference is required

Phase 3 requests **alert authorization only** and relies on macOS notification settings as the user-facing system control. It does not add a new FloatTabs preference, backup field or persistence schema.

Existing FloatTabs attention sound behavior remains independent. The native notification itself does not request a system notification sound, avoiding duplicate audio policy.

Authorization denied/unavailable/error is a notification-projection failure only. It must not mutate or block:

- durable unread;
- existing attention sound;
- generation state;
- Runtime reclaim/restore;
- Slot/Profile/session data.

## 3. Frozen ownership

### 3.1 New notification projection owner

Add an App-layer coordinator, expected path:

`FloatTabs/App/ChatGPTCompletionNotificationCoordinator.swift`

It owns only:

- `UNUserNotificationCenter` delegate integration;
- contextual alert authorization request;
- local notification request construction/delivery;
- privacy-bounded notification payload parsing;
- default-action tap → exact Slot UUID callback;
- notification-specific diagnostics.

It does **not** own unread truth, Slot existence, Runtime creation, selection persistence, focus or Browser Profile data.

### 3.2 App composition

`AppCoordinator` retains/wires the notification coordinator and connects:

```text
PanelController durable-unread-marked callback
→ ChatGPTCompletionNotificationCoordinator.notify(slotID:)

notification default-action callback(slotID)
→ PanelController.presentSlotFromCompletionNotification(slotID:)
```

The existing `onChatGPTGenerationCompleted` → attention-sound route stays unchanged.

### 3.3 Panel routing boundary

`PanelController` adds one bounded route for notification activation. Semantically:

```text
validate/select exact Slot UUID through TabStore
→ existing slot synchronization/restoration path
→ present FloatTabs through existing presentation owner
→ run existing explicit-selection unread acknowledgement only after presentation facts allow it
```

This route must not:

- directly create a `WKWebView` outside the existing Runtime owner;
- directly clear durable unread before actual presentation;
- fall back to the current Slot when the target is stale/missing;
- bypass normal focus/fullscreen/presentation ownership.

## 4. Notification contract

### 4.1 Trigger

Deliver at most one Phase 3 notification attempt for each production completion handoff where:

```text
completion is valid
AND completion was not actually visible
AND ChatGPTUnreadResponseCoordinator.handle(...) == .marked(...)
```

Do not notify for:

- visible completion;
- stray/invalid finish;
- already-handled completion;
- runtime reset/recreation by itself;
- durable-unread acknowledgement;
- restoring a Slot.

A later distinct hidden response in the same Slot may produce a new notification.

### 4.2 Identifier / coalescing

Use one deterministic notification request identifier per Slot, for example:

`floattabs.chatgpt-completion.<slot-uuid>`

Before delivering a newer completion notification for the same Slot, remove/replace the previously delivered same-identifier notification so one Slot does not accumulate stale completion alerts.

Different Slots remain independently addressable.

### 4.3 Privacy-bounded content

Default notification content is generic:

- title: `FloatTabs`
- body: `A ChatGPT response is ready.`

Do not include prompt text, assistant response text, URL, Browser Profile name, cookies/session data, document tokens or diagnostics payloads.

The routing payload contains only a small version/kind marker and the exact Slot UUID string.

### 4.4 Foreground presentation

The notification coordinator handles its own foreground notification in the `UNUserNotificationCenterDelegate` path and requests banner/list presentation for the recognized FloatTabs ChatGPT completion notification. It does not request notification sound.

Unknown/unrecognized notification payloads are not routed as Phase 3 completions.

### 4.5 Tap routing

Only the system default notification action routes the Slot. Dismissal, malformed payload, unknown kind/version or invalid UUID is ignored safely.

When the target Slot no longer exists:

```text
route result = unavailable/stale
→ no fallback selection
→ no Runtime materialization
→ no user-data mutation
→ diagnostic evidence only
```

## 5. Authorized production scope

Expected production paths:

1. **NEW** `FloatTabs/App/ChatGPTCompletionNotificationCoordinator.swift`
2. `FloatTabs/App/AppCoordinator.swift`
3. `FloatTabs/Panel/PanelController.swift`
4. `FloatTabs.xcodeproj/project.pbxproj` — source/test membership only, plus a system-framework link entry only if the compiler/linker actually requires one.

No other production file is authorized without STOP/reconciliation.

## 6. Authorized test scope

Expected tests:

1. **NEW** `FloatTabsTests/ChatGPTCompletionNotificationTests.swift`
2. `FloatTabsTests/WebAttentionCrossFeatureTests.swift`
3. `FloatTabs.xcodeproj/project.pbxproj` — new test membership.

A narrowly necessary adjacent existing test may be added only when it directly proves the frozen Phase 3 route and does not change its production scope. Otherwise STOP/reconcile.

## 7. Explicit non-scope

Phase 3 does not authorize changes to:

- `ChatGPTAttentionBridge.swift` detector/sensing semantics;
- `ChatGPTResponseBridge.swift`;
- `ChatGPTResponseExtraction.swift`;
- `ChatGPTUnreadResponseCoordinator.swift`;
- `UnreadResponseStore.swift` or unread persistence schema;
- `WebAttentionCoordinator.swift` protection semantics;
- `SlotLifecycleCoordinator.swift` timer/policy;
- `WebViewPool.swift` hibernate/restore semantics;
- Browser Profile / website session / Slot configuration persistence;
- Runtime Budget/ranking policy (Phase 4);
- background-generation thrift (Phase 5);
- perceived-fast restore optimization (Phase 6);
- notification body preview of user/assistant content;
- new release/version metadata;
- final human UI/runtime acceptance.

No user-data reset/deletion is authorized.

## 8. Required machine verification

### Gate A — notification coordinator unit coverage

Prove at minimum:

1. granted alert authorization schedules one recognized generic notification;
2. denied/error authorization schedules none without affecting route callback/product state;
3. same Slot uses the same deterministic identifier and coalesces prior delivered notification;
4. different Slots produce independent identifiers;
5. payload contains only version/kind/Slot UUID and no page/user content;
6. default-action response routes the exact valid Slot UUID;
7. dismiss/unknown kind-version/malformed UUID does not route;
8. foreground recognized completion requests alert presentation without notification sound.

### Gate B — production completion composition

Prove through real production composition/tests:

1. hidden valid completion that returns durable unread `.marked` emits exactly one native-notification callback;
2. visible valid completion emits no native-notification callback;
3. stray/invalid finish emits none;
4. already-handled duplicate emits none;
5. later distinct hidden completion in the same Slot can emit a new notification;
6. existing `onChatGPTGenerationCompleted` sound callback semantics remain unchanged;
7. Generating protection / Ready non-protection remain unchanged.

### Gate C — exact Slot routing / Runtime independence

Prove:

1. notification activation selects the exact target Slot;
2. stale/deleted target does not fall back to the current Slot;
3. if target Runtime is non-resident, selection/presentation recreates/restores through existing lifecycle ownership and produces one Runtime, not a duplicate;
4. notification activation does not directly clear unread before actual presentation acknowledgement rules allow it;
5. Browser Profile/session/configuration identity is not mutated.

### Gate D — broad verification

- focused Phase 3 tests PASS;
- full XCTest PASS with no new Phase 3-caused failure;
- Debug arm64 build PASS;
- Release arm64 build PASS;
- exact changed-path/scope/data-safety audit PASS;
- literal-head required GitHub `Build & Test (Apple Silicon arm64)` PASS on `macmini-floattabs-01`.

Under Program Contract V3, Phase 3 does **not** require a per-phase AI/CUA live smoke, formal independent audit, or user human acceptance before merge.

## 9. STOP conditions

STOP and reconcile if implementation requires any of the following:

- changing ChatGPT detector/response extraction to produce notifications;
- changing durable unread persistence/schema or introducing a second unread writer;
- retaining `WKWebView`, Runtime generation or document identity in notification state;
- clearing unread merely because a notification was tapped, before existing presentation acknowledgement succeeds;
- falling back to another/current Slot when notification target is stale;
- mutating Browser Profile/session/configuration data;
- changing lifecycle timers/policy or Runtime restore semantics;
- adding response/prompt text to notification content;
- adding a persisted notification preference/backup schema to make basic Phase 3 correctness work;
- expanding into Phase 4/5/6;
- required tests/build/CI failure caused by Phase 3;
- overlapping unique work makes the writer unsafe.

## 10. Rollback

Phase 3 rollback removes only native notification projection/routing wiring. It must leave:

- Phase 1 hibernate/restore;
- Phase 2 durable unread / Ready decoupling;
- existing attention sound;
- Slot/Profile/session data;
- Runtime lifecycle policy

unchanged.

## 11. Implementation sequence

```text
add notification coordinator + test seam
→ wire AppCoordinator
→ add durable-unread-marked callback in PanelController
→ add exact Slot notification-presentation route
→ focused notification/composition/routing tests
→ full XCTest
→ Debug / Release arm64
→ exact scope/data-safety audit
→ commit / push / one Phase 3 implementation PR
→ literal-head required self-hosted CI PASS
→ merge
→ Phase 3 control alignment
→ continue to Phase 4
```
