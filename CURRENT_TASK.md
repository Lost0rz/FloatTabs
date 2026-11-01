# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 3 Native ChatGPT Completion Notification  
**Status:** `ACTIVE / PHASE 3 IMPLEMENTATION AUTHORIZED`  
**Mode:** `EXECUTE`  
**Task class:** `NATIVE NOTIFICATION PROJECTION / EXACT SLOT ROUTING`  
**Program contract:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md`  
**Phase 3 plan:** `docs/architecture/FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V1.md`  
**JSC root cause:** `UNKNOWN`

## Authorization

Implement Phase 3 only, under the frozen Phase 3 V1 plan.

Program cadence remains:

```text
phase-focused audit / freeze
→ bounded implementation
→ phase-local machine verification + required CI
→ merge
→ continue next architecture phase
...
Phases 1–6 complete
→ unified independent audit
→ one user-owned full human acceptance pass
```

Phase 2 is structurally complete and merged at `3b8270de6917b0342143a36d2457686bb59dcc25`.

## Frozen Phase 3 target

A valid unseen ChatGPT completion may create a native macOS notification that remains independently routable after the corresponding `WKWebView` Runtime has been reclaimed.

Canonical chain:

```text
valid hidden completion
→ ChatGPTUnreadResponseCoordinator returns .marked
→ durable unread presentation synchronized
→ native notification projection receives persistent Slot UUID
→ normal lifecycle may reclaim Runtime
→ user taps notification
→ exact Slot is selected
→ existing Runtime restore/recreation path supplies Runtime if absent
→ FloatTabs is presented
→ existing acknowledgement rules decide when unread clears
```

Native notification is a projection only. Durable unread remains canonical product truth.

## Required ownership decisions

1. Add one App-layer notification coordinator for `UNUserNotificationCenter` integration.
2. Keep the existing `onChatGPTGenerationCompleted` attention-sound callback unchanged.
3. Add a distinct Panel callback only for durable unread result `.marked`.
4. Carry only `Slot.id` UUID as route identity.
5. Add one bounded `PanelController` route that selects the exact Slot, uses existing Slot/Runtime synchronization, presents FloatTabs, then relies on existing presentation-aware acknowledgement semantics.
6. Missing/deleted target returns unavailable with no fallback selection.
7. No notification-owned unread state, Runtime identity or persistence is introduced.

## Notification behavior

- request `.alert` authorization contextually on the first real unseen-completion notification attempt;
- do not request a system notification sound; existing FloatTabs attention sound remains independent;
- generic content only: no prompt, assistant body, URL, Profile/session data or document identity;
- payload contains only a version/kind marker and exact Slot UUID;
- deterministic same-Slot request identifier coalesces/replaces stale same-Slot alerts;
- foreground recognized completion may present as banner/list through the notification-center delegate;
- only default notification action routes the Slot;
- dismissal, malformed payload, unknown kind/version or stale Slot is ignored safely;
- denied/unavailable/error authorization never changes unread, sound, generation, Runtime lifecycle or user data;
- do not add a persisted FloatTabs notification preference or backup/schema field in Phase 3.

## Authorized production files

Only:

- **NEW** `FloatTabs/App/ChatGPTCompletionNotificationCoordinator.swift`
- `FloatTabs/App/AppCoordinator.swift`
- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs.xcodeproj/project.pbxproj` for source/test membership and, only if actually linker-required, the relevant system-framework entry.

## Authorized test files

- **NEW** `FloatTabsTests/ChatGPTCompletionNotificationTests.swift`
- `FloatTabsTests/WebAttentionCrossFeatureTests.swift`
- `FloatTabs.xcodeproj/project.pbxproj`

A narrowly necessary adjacent existing test file may be added only when it directly proves the frozen route without expanding production scope. Otherwise STOP/reconcile.

## Required machine outcomes

The implementation must prove:

1. hidden valid completion whose durable-unread result is `.marked` emits exactly one notification projection request;
2. visible completion emits none;
3. stray/invalid completion emits none;
4. already-handled duplicate emits none;
5. a later distinct hidden response in the same Slot may emit a new notification;
6. authorization granted schedules one generic alert;
7. denied/error authorization schedules none and has no product-state side effect;
8. same Slot uses deterministic same identifier/coalescing; different Slots remain independent;
9. payload is privacy bounded to kind/version/Slot UUID;
10. default action routes exact Slot UUID;
11. dismiss/unknown/malformed payload does not route;
12. stale/deleted Slot never falls back to current Slot;
13. non-resident target activation uses existing restore/recreation ownership and does not duplicate Runtime;
14. notification activation does not clear unread before actual presentation acknowledgement rules allow it;
15. existing attention sound behavior remains unchanged;
16. Generating remains Runtime-protected and Ready remains non-protecting;
17. Browser Profile/session/configuration data is unchanged.

## Verification / delivery

Required before merge:

- focused Phase 3 tests PASS;
- full XCTest PASS with no new Phase 3-caused failure;
- Debug arm64 build PASS;
- Release arm64 build PASS;
- exact changed-path/scope/data-safety audit PASS;
- commit and push one Phase 3 implementation branch;
- exactly one Phase 3 implementation PR;
- literal-head `Build & Test (Apple Silicon arm64)` PASS on `macmini-floattabs-01`;
- PR remains mergeable with no required host blocker.

Under Program Contract V3, do **not** require Phase 3 AI/CUA live smoke, formal independent web audit or user human acceptance before merge.

## Explicit forbidden scope

Do not modify without STOP/reconciliation:

- `ChatGPTAttentionBridge.swift`;
- `ChatGPTResponseBridge.swift`;
- `ChatGPTResponseExtraction.swift`;
- `ChatGPTUnreadResponseCoordinator.swift`;
- `UnreadResponseStore.swift` or unread schema;
- `WebAttentionCoordinator.swift` protection semantics;
- `SlotLifecycleCoordinator.swift` timing/policy;
- `WebViewPool.swift` hibernate/restore semantics;
- Browser Profile / website session / Slot configuration persistence;
- persisted notification preference / backup schema;
- response/prompt preview in native notification;
- Phase 4 Runtime Budget/policy;
- Phase 5 background-generation thrift;
- Phase 6 perceived-fast restore;
- release/version metadata.

No user-data reset/deletion is authorized.

## STOP conditions

STOP and reconcile if:

- notification correctness requires detector/response-extraction changes;
- a second unread/completion writer would be required;
- notification state would retain WebView/Runtime/document identity;
- routing would require fallback to another Slot;
- unread must be cleared before normal presentation acknowledgement;
- durable unread schema/persistence must change;
- Browser Profile/session/configuration behavior must change;
- lifecycle timer/policy or restore semantics must change;
- a persisted notification setting/backup migration is required for basic correctness;
- Phase 4/5/6 work is required;
- required tests/build/CI fail because of Phase 3;
- overlapping unique work makes the writer unsafe.

## Delivery boundary

The local executor may commit, push and create/update exactly one Phase 3 implementation PR. It must not merge, release, bump version or begin Phase 4.

Expected construction terminal result:

- `WAITING_FOR_PHASE_3_MERGE_GATE` when machine evidence and literal-head CI are complete; or
- `STOP_RECONCILE` when a frozen STOP condition is triggered.

Program-level independent audit and human acceptance remain deferred until Phases 1–6 are complete.
