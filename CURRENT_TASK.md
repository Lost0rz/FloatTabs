# FloatTabs Current Task

**Task ID:** `FT-NOTIFICATION-RELIABILITY-RICH-PREVIEW-001`  
**Title:** Native completion notification reliability + Slot name + assistant preview  
**Status:** `ACTIVE / DESIGN FROZEN / READY FOR IMPLEMENTATION`  
**Mode:** `IMPLEMENTATION AUTHORIZED / MERGE NOT AUTHORIZED UNTIL GATES COMPLETE`  
**Task class:** `APP / NATIVE NOTIFICATION / RESPONSE PROJECTION / UX RELIABILITY`  
**Execution baseline:** `main@08831ad2cc3e7f18432b1a6ecdc983e849a992aa`  
**Task branch:** `codex/notification-reliability-rich-preview-001`

## Authorization

The user opened a new standalone notification task after the Phase 8 lifecycle task closed.

Authorized objective:

1. make native ChatGPT completion notification delivery diagnosable;
2. show the target Slot/Web App name in the notification;
3. show a bounded plain-text preview of the completed assistant response when safely available;
4. preserve exact-Slot click routing and existing Runtime restore ownership;
5. keep notification behavior compatible with the merged lightweight background-generation policy.

This task does not reopen or modify the closed Phase 8 memory-budget work.

## Authority

- Project rules: `AGENTS.md`
- Current state: `CURRENT_STATUS.md`
- Task contract: this file
- Durable design/implementation contract: `docs/architecture/FloatTabs_Native_Completion_Notification_Reliability_Rich_Preview_Contract_V1.md`
- Documentation routing: `docs/README.md`
- Domain navigation: `docs/architecture/DOMAIN_MAP.md`
- Existing Phase 3 notification plan: historical/delivered baseline only where not superseded by the new contract
- Production source/tests/fresh repository and runtime evidence remain implementation truth.

## Verified baseline findings

Fresh audit of `main@08831ad2...` established:

1. `ChatGPTCompletionNotificationCoordinator` already owns the only `UNUserNotificationCenter` integration.
2. Current content is intentionally generic: title `FloatTabs`, body `A ChatGPT response is ready.`.
3. Current notification routing payload contains only `version / kind / slot_id`.
4. `AppCoordinator` already wires notification default action to `PanelController.presentSlotFromCompletionNotification(slotID)`.
5. Exact persistent Slot routing is already covered by tests; stale Slot IDs fail closed and do not fall back to the current Slot.
6. Notification projection is triggered only when a valid hidden completion produces durable unread `.marked`; visible/invalid/already-handled completions do not notify.
7. Existing response infrastructure can identify the latest assistant response root and response identity/status, but response-body preview is deliberately not currently extracted.
8. Existing diagnostics record request / skipped / delivery-style events but do not record current macOS notification authorization/alert/preview settings and cannot prove a visible banner.
9. Apple public notification settings APIs expose authorization, alert setting/style, Notification Center setting and show-previews policy; they do not provide a supported basis for claiming Focus suppression as proven root cause.
10. There are no open PRs in the repository at task start and no pre-existing task branch matching this objective.

## Frozen product behavior

### Trigger

Preserve existing trigger semantics:

```text
valid hidden completion
AND durable unread transition == .marked
→ one native notification projection attempt
```

Do not notify for visible completion, invalid/stray finish, already-handled duplicate, Runtime reset or restore alone.

### Content

Notification title:

```text
normalized Slot/Web App display name
fallback: ChatGPT
max: 80 user-perceived characters
```

Notification body:

```text
latest completed assistant response preview
plain text
normalized whitespace
max: 240 user-perceived characters
fallback: A ChatGPT response is ready.
```

Never include prompt/user text, URL, Browser Profile/session identity, document token or Runtime identity.

### Routing payload

Keep exactly:

```text
version
kind
slot_id
```

Do not add Slot name or response preview to `userInfo`.

### Preview extraction ownership

- `ChatGPTResponseExtraction` remains the DOM semantic source for assistant-response roots.
- `ChatGPTResponseBridge` may add a separate one-shot preview snapshot API using its existing isolated content world and current-WebView/current-document guards.
- Do not add response text to the existing ordinary status snapshot contract.
- Preview is ephemeral and best-effort. If extraction fails, races Runtime/navigation replacement, or returns untrustworthy state, deliver the generic fallback body.
- Preview extraction must not create periodic polling or a new long-lived Runtime protection.

### Notification system preflight

Before submission, read the current system notification settings through the injectable backend seam.

Required bounded settings facts:

- authorization status;
- alert setting;
- alert style;
- Notification Center setting;
- show-previews setting.

If authorization is `notDetermined`, request `.alert` contextually and reread settings. Do not re-request authorization for every already-authorized completion.

System submission success proves only that macOS accepted the request, not that a banner was visibly displayed. Diagnostics must use that semantic distinction.

Do not use private APIs and do not claim current Focus/DND suppression is directly observable.

### Exact click routing

Preserve the existing route:

```text
notification default action
→ parse persistent Slot UUID
→ PanelController.presentSlotFromCompletionNotification(slotID)
→ exact Slot select
→ existing presentation/materialization path
```

No fallback to another/current Slot is allowed.

## Authorized production paths

Expected mutation scope:

- `FloatTabs/App/ChatGPTCompletionNotificationCoordinator.swift`
- `FloatTabs/App/AppCoordinator.swift`
- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/Web/ChatGPTResponseBridge.swift`
- `FloatTabs/Web/ChatGPTResponseExtraction.swift`

Conditional only if fresh source reconciliation proves it necessary:

- `FloatTabs/Web/WebViewPool.swift` for a minimal read-only response-bridge projection seam only.

No lifecycle policy file is authorized for semantic change.

## Authorized test paths

Expected focused coverage:

- `FloatTabsTests/ChatGPTCompletionNotificationTests.swift`
- `FloatTabsTests/ChatGPTResponseExtractionTests.swift`
- `FloatTabsTests/ChatGPTResponseBridgeTests.swift`
- `FloatTabsTests/WebAttentionCrossFeatureTests.swift`
- narrowly necessary diagnostics/privacy regression only if new diagnostics fields require it.

## Acceptance gates

### N0 — source reconciliation

Before production mutation, confirm current symbols/call order and that no newer branch/PR changed the notification or response ownership boundary.

### N1 — preview extraction

PASS only when tests prove:

- latest assistant-only plain text extraction;
- exclusion of user/composer/action/hidden content;
- Unicode-safe whitespace normalization and 240-character cap;
- no trusted preview for generating/missing/malformed/stale document state;
- Runtime/navigation invalidation drops stale async preview results;
- ordinary response-status snapshots remain body-free.

### N2 — notification coordinator / settings

PASS only when tests prove:

- Slot name title + assistant preview body;
- generic body fallback;
- routing payload remains version/kind/slot_id only;
- settings read occurs through injected backend;
- authorization request occurs only from notDetermined and settings are reread;
- denied/unavailable state skips system submission only;
- authorized submission remains allowed when system banner policy is disabled, with diagnostics reflecting that fact;
- same-Slot replacement and foreground banner/list/no-sound semantics remain intact;
- no diagnostics field records Slot name or response text.

### N3 — production composition / exact routing

PASS only when tests prove:

- hidden `.marked` completion emits one projection attempt;
- visible/invalid/duplicate completions emit none;
- preview failure still yields one generic notification attempt;
- default-action routes exact Slot;
- stale/deleted Slot never falls back;
- non-resident target restores through existing Runtime ownership;
- unread is not pre-cleared by submission/tap;
- existing completion sound semantics are unchanged.

### N4 — lifecycle/background regression

PASS only when:

- hidden generation watchdog remains 2s → 5s → 10s;
- Generating remains hard-protected;
- normal target=2 / 30s grace remain unchanged;
- warning/critical pressure ladder remains unchanged;
- no preview polling, second lifecycle writer or response-content persistence is introduced.

### N5 — broad repository gate

Required:

- focused tests PASS;
- full XCTest PASS;
- Debug arm64 PASS;
- Release arm64 PASS;
- native arm64 architecture PASS;
- package lock unchanged unless separately reconciled;
- exact changed-path / ownership / privacy self-audit PASS;
- push to this task branch and verify remote commit;
- one Draft PR for this task;
- literal-head required `Build & Test (Apple Silicon arm64)` PASS on `[self-hosted, macOS, ARM64, mac-mini-ci]`;
- QA DMG PASS if automatically triggered;
- independent exact-diff / ownership / privacy review before human acceptance.

## Human acceptance

This task materially changes native notification content and click interaction.

`HUMAN_UI_ACCEPTANCE=PENDING` until the user explicitly validates the real macOS notification behavior.

After machine + independent audit gates, stop before merge and ask the user to validate:

1. hidden ChatGPT completion produces a notification when macOS settings allow it;
2. correct Slot name appears;
3. assistant preview is sensible when system preview policy allows it;
4. clicking opens the exact Slot;
5. reclaimed Runtime restores correctly from a notification click;
6. macOS preview-disabled behavior is not misdiagnosed as app failure;
7. alert-disabled behavior is reflected in diagnostics.

AI/browser/screenshot inspection does not count as human acceptance.

## Explicit non-scope

Do not add or change:

- FloatTabs notification settings UI/persistence;
- notification sound policy;
- Time Sensitive/Critical Alert escalation;
- Focus/DND bypass;
- remote push or Web Notification API emulation;
- persisted notification history or persisted response text;
- ChatGPT generation detector semantics merely to obtain preview text;
- Runtime lifecycle policy/timers;
- aggregate memory-budget work;
- Browser Profile/session/cache reset or migration.

## STOP conditions

STOP and reconcile if implementation requires:

- a second completion/unread/Tab/Runtime writer;
- periodic response-preview polling;
- adding Slot name/preview to routing `userInfo`;
- persisting/logging response text or Slot name;
- unbounded wait for preview extraction;
- keeping a completed Runtime resident solely for notification preview;
- private notification/Focus APIs;
- lifecycle timer/pressure/generation-protection changes;
- destructive user/session data mutation;
- mutation outside authorized production scope without evidence-backed reconciliation;
- required tests/build/CI failure caused by the task.

## Delivery / merge boundary

The implementation stays on:

`codex/notification-reliability-rich-preview-001`

Use one Draft PR for the task. Do not merge from the executor context.

Required stopping state after implementation:

```text
machine gates complete
literal-head CI complete
independent audit still required or complete as observed
HUMAN_UI_ACCEPTANCE=PENDING
MERGE=NOT_MERGED
```

Final merge requires the user’s explicit human notification acceptance plus fresh merge-boundary verification.
