# FloatTabs Current Status

**Status date:** `2026-11-01`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: RUNTIME LIFECYCLE / MEMORY PROGRAM — PHASE 3 NATIVE COMPLETION NOTIFICATION**

Current program/task: `FT-RUNTIME-LIFECYCLE-MEMORY-001`.

Current execution state: `ACTIVE / PHASE 3 IMPLEMENTATION AUTHORIZED — V2 BACKEND SEAM REFINEMENT`.

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
PHASE_3_KYLMORA_COMPARATIVE_AUDIT=COMPLETE
PHASE_3_PLAN_V2=ACCEPTED_FROZEN
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
→ docs/architecture/FloatTabs_Runtime_Lifecycle_Phase3_Native_Completion_Notification_Plan_V2.md
→ docs/architecture/DOMAIN_MAP.md
→ current source/tests/fresh evidence
```

Phase 3 V1 remains historical freeze evidence; V2 is the active execution plan.

## Phase 3 focused + comparative audit conclusion

Phase 3 does **not** require new ChatGPT detector, response extraction, unread persistence or Runtime lifecycle semantics.

Current production already provides:

```text
valid ChatGPT completion
→ PanelController completion handoff
→ ChatGPTUnreadResponseCoordinator.handle(...)
→ hidden unseen completion => durable unread result .marked
```

The native-notification trigger remains the durable-unread `.marked` transition, not the existing generic `onChatGPTGenerationCompleted` sound callback.

A direct comparison with Kylmora's working native Web Notification implementation at commit `7d60b6c4cda0784c9a9034213f0fc323e0841fb0` confirmed the core infrastructure pattern:

- isolate `UNUserNotificationCenter` behind a testable backend seam;
- install the notification delegate at application startup;
- explicitly support foreground presentation;
- use stable persistent tab/Slot UUID routing rather than retaining a live WebView;
- default click routes exact target; dismiss does not navigate;
- stale/unknown target is ignored safely;
- explicitly withdraw/replace stale same-source notification state.

FloatTabs intentionally does not adopt Kylmora's full browser Web Notification API, origin/tag store, service-worker/page-event semantics or content-rich notification payload. FloatTabs remains ChatGPT-specific and privacy bounded.

## Frozen Phase 3 ownership / privacy decisions

Canonical flow:

```text
durable unread .marked
→ ChatGPTCompletionNotificationCoordinator
→ injected CompletionNotificationBackend
→ native notification keyed by persistent Slot UUID
→ Runtime may be reclaimed normally
→ default-action tap
→ exact Slot UUID selection
→ existing Runtime restore/recreation path
→ normal presentation acknowledgement semantics
```

Rules:

- direct `UNUserNotificationCenter` access belongs only to the system backend;
- production and tests share the same coordinator semantics, but XCTest uses a recording/fake backend;
- no real system Notification Center is required for unit tests;
- `Slot.id` UUID is the only routing identity;
- no `WKWebView`, Runtime generation, document token or Browser Profile identity is retained;
- exact routing must not require an in-memory notification record as product truth;
- same-Slot request identity is deterministic and prior same-Slot delivered/pending notification state is explicitly withdrawn before replacement where applicable;
- different Slots remain independent;
- notification body is generic and contains no prompt/response/URL/profile content;
- native notification requests alert presentation only; existing FloatTabs attention sound remains independent;
- denied/unavailable/error permission cannot affect unread, sound, generation, reclaim/restore or user data;
- stale/deleted target is a safe no-op and never falls back to current Slot.

## Authorized Phase 3 production scope

Expected production files:

1. **NEW** `FloatTabs/App/ChatGPTCompletionNotificationCoordinator.swift` — coordinator + bounded backend protocol/system backend;
2. `FloatTabs/App/AppCoordinator.swift`;
3. `FloatTabs/Panel/PanelController.swift`;
4. `FloatTabs.xcodeproj/project.pbxproj` — membership and only a linker-required system-framework entry if needed.

Expected test files:

1. **NEW** `FloatTabsTests/ChatGPTCompletionNotificationTests.swift` — recording/fake backend coverage;
2. `FloatTabsTests/WebAttentionCrossFeatureTests.swift`;
3. `FloatTabs.xcodeproj/project.pbxproj`.

No other production path is authorized without STOP/reconciliation.

## Phase 3 machine gate

Before Phase 3 merge:

1. backend abstraction is actually used by the coordinator;
2. hidden durable-unread `.marked` completion produces one notification callback;
3. visible/invalid/already-handled completion produces none;
4. grant/deny/error/unavailable/foreground/default-action/malformed payload behavior is covered;
5. same-Slot identity explicitly withdraws/replaces prior same-Slot system state;
6. different Slots remain independent;
7. exact Slot activation is proven, including non-resident Runtime restoration through existing lifecycle ownership;
8. stale/deleted Slot never falls back to another Slot;
9. notification activation does not pre-clear unread before normal presentation acknowledgement;
10. existing attention sound semantics and Generating/Ready protection semantics remain unchanged;
11. Browser Profile/session/configuration data remains untouched;
12. targeted/focused tests PASS;
13. full XCTest PASS;
14. Debug arm64 PASS;
15. Release arm64 PASS;
16. exact changed-path/scope/data-safety review PASS;
17. literal-head required `Build & Test (Apple Silicon arm64)` PASS on `macmini-floattabs-01`.

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
- complete browser Web Notification API emulation;
- page-origin/tag/service-worker notification store;
- Runtime Budget/policy (Phase 4);
- background-generation thrift (Phase 5);
- perceived-fast restore (Phase 6);
- release/version metadata.

No user-data reset/deletion is authorized.

## Next action

Execute Phase 3 from the frozen V2 plan using one canonical writer. Implement only the bounded native notification projection, backend seam, explicit same-Slot replacement and exact-Slot route; run the phase-local machine gate; push exactly one Phase 3 implementation PR; require literal-head self-hosted CI; merge when green; then perform control alignment and proceed to Phase 4 focused audit/freeze. Program-final independent audit and human acceptance remain deferred until Phases 1–6 are structurally complete.
