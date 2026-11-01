# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 3 NATIVE COMPLETION NOTIFICATION**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `ACTIVE / PHASE 3 IMPLEMENTATION AUTHORIZED`.

Program Contract V3 remains the current program authority: complete Phases 1–6 with phase-local machine correctness and required CI, then perform one unified independent audit followed by one user-owned full human acceptance pass.

## Canonical / current state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN

PROGRAM_CONTRACT_V3=ACCEPTED_FROZEN
PROGRAM_UNIFIED_INDEPENDENT_AUDIT=DEFERRED_UNTIL_PHASES_1_6_COMPLETE
PROGRAM_HUMAN_ACCEPTANCE=PENDING / DEFERRED_UNTIL_UNIFIED_AUDIT_PASS

PHASE_1_SAFE_HIBERNATE_RESTORE=COMPLETE
PHASE_2_READY_UNREAD_DECOUPLING=COMPLETE / MERGED
PHASE_2_MERGE_COMMIT=3b8270de6917b0342143a36d2457686bb59dcc25
PHASE_3_FOCUSED_READ_ONLY_AUDIT=COMPLETE
PHASE_3_PLAN_V1=ACCEPTED_FROZEN
PHASE_3_IMPLEMENTATION=AUTHORIZED
PHASE_4=NOT_STARTED / NOT_AUTHORIZED
PHASE_5=NOT_STARTED / NOT_AUTHORIZED
PHASE_6=NOT_STARTED / NOT_AUTHORIZED
CI_RUNNER=macmini-floattabs-01 / self-hosted / macOS / ARM64 / mac-mini-ci
```

## Current Authority

Read in this order:

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ docs/README.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V3.md
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V1.md
→ docs/architecture/DOMAIN_MAP.md
→ current source/tests/fresh evidence
```

Phase 1/2 plans remain accepted historical/delivered evidence but are not active Phase 3 execution authority.

## Phase 3 focused audit conclusion

Phase 3 does **not** require new ChatGPT detector, response extraction, unread persistence or Runtime lifecycle semantics.

Current production already provides the needed boundaries:

```text
valid ChatGPT completion
→ PanelController completion handoff
→ ChatGPTUnreadResponseCoordinator.handle(...)
→ hidden unseen completion => durable unread result .marked
```

The Phase 3 trigger is the transition where durable unread is newly marked, not the existing generic `onChatGPTGenerationCompleted` callback. That existing callback remains unchanged because it drives the current attention sound for all valid completions, including visible completion.

Phase 3 adds one App-layer native-notification projection owner and one bounded exact-Slot presentation route:

```text
durable unread .marked
→ native notification projection (Slot UUID only)
→ Runtime may be reclaimed normally
→ notification default-action tap
→ exact Slot UUID selection
→ existing Runtime restore/recreation path
→ normal presentation acknowledgement semantics
```

A notification is never canonical unread state and never owns Runtime state.

## Frozen Phase 3 ownership / privacy decisions

- native notification owner lives in the App composition layer;
- `Slot.id` UUID is the only notification routing identity;
- no `WKWebView`, Runtime generation, navigation/document token or Browser Profile identity is retained in notification state;
- notification body is generic and contains no prompt/response/URL/profile content;
- alert authorization is requested contextually on the first real unseen-completion delivery attempt;
- no new FloatTabs persisted notification preference or backup schema is added;
- notification requests alert presentation only; existing FloatTabs attention sound remains the independent audio policy;
- denied/unavailable notification permission cannot affect unread, sound, generation, reclaim/restore or user data;
- stale/deleted notification target is a safe no-op and never falls back to the current Slot.

## Authorized Phase 3 production scope

Expected production files:

1. **NEW** `FloatTabs/App/ChatGPTCompletionNotificationCoordinator.swift`
2. `FloatTabs/App/AppCoordinator.swift`
3. `FloatTabs/Panel/PanelController.swift`
4. `FloatTabs.xcodeproj/project.pbxproj` — source/test membership and only a linker-required system-framework entry if needed.

Expected test files:

1. **NEW** `FloatTabsTests/ChatGPTCompletionNotificationTests.swift`
2. `FloatTabsTests/WebAttentionCrossFeatureTests.swift`
3. `FloatTabs.xcodeproj/project.pbxproj`

No other production path is authorized without STOP/reconciliation.

## Phase 3 machine gate

Before Phase 3 merge:

1. hidden durable-unread `.marked` completion produces one notification callback;
2. visible/invalid/already-handled completion produces none;
3. notification coordinator grant/deny/error/foreground/default-action/malformed payload behavior is covered;
4. same-Slot notification identity coalesces; different Slots remain independent;
5. exact Slot activation is proven, including non-resident Runtime restoration through existing lifecycle ownership;
6. stale/deleted Slot never falls back to another Slot;
7. notification activation does not pre-clear unread before normal presentation acknowledgement;
8. existing attention sound semantics and Generating/Ready protection semantics remain unchanged;
9. Browser Profile/session/configuration data remains untouched;
10. focused tests PASS;
11. full XCTest PASS;
12. Debug arm64 PASS;
13. Release arm64 PASS;
14. exact changed-path/scope/data-safety review PASS;
15. literal-head required `Build & Test (Apple Silicon arm64)` PASS on `macmini-floattabs-01`.

Per Program Contract V3, no Phase 3 AI/CUA live smoke, formal independent web audit or user human acceptance is a routine merge gate.

## Explicit Phase 3 non-scope

Do not modify without STOP/reconciliation:

- `ChatGPTAttentionBridge.swift`;
- `ChatGPTResponseBridge.swift`;
- `ChatGPTResponseExtraction.swift`;
- `ChatGPTUnreadResponseCoordinator.swift`;
- `UnreadResponseStore.swift` / unread schema;
- `WebAttentionCoordinator.swift` semantics;
- `SlotLifecycleCoordinator.swift` timing/policy;
- `WebViewPool.swift` hibernate/restore semantics;
- Browser Profile/session/configuration persistence;
- Runtime Budget/policy (Phase 4);
- background-generation thrift (Phase 5);
- perceived-fast restore (Phase 6);
- release/version metadata.

No user-data reset/deletion is authorized.

## Next action

Execute Phase 3 from the frozen V1 plan using one canonical writer. Implement only the bounded native notification projection and exact-Slot route, run the phase-local machine gate, push exactly one Phase 3 implementation PR, require literal-head self-hosted CI, merge when green, then perform control alignment and proceed to Phase 4 focused audit/freeze. Program-final independent audit and human acceptance remain deferred until Phases 1–6 are structurally complete.
