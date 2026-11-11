# FloatTabs Native Completion Notification — Reliability + Rich Preview Contract V1

**Status:** `ACCEPTED / FROZEN FOR TASK FT-NOTIFICATION-RELIABILITY-RICH-PREVIEW-001`  
**Date:** `2026-11-02`  
**Baseline:** `main@08831ad2cc3e7f18432b1a6ecdc983e849a992aa`  
**Task:** `FT-NOTIFICATION-RELIABILITY-RICH-PREVIEW-001`

## 1. Objective

Improve the existing native ChatGPT completion notification without creating a second completion, unread, Tab, or Runtime authority.

Required product behavior:

```text
valid hidden ChatGPT completion
→ durable unread becomes .marked
→ derive one bounded notification preview from the completed assistant response
→ submit one native macOS notification
   title = target Slot/Web App name
   body  = bounded assistant-response preview when available
→ notification tap routes the exact persistent Slot UUID
→ existing presentation / Runtime restore path opens that Slot
```

The notification must remain compatible with the lightweight hidden-generation policy already merged in Phase 8.

## 2. Verified baseline

### 2.1 Trigger ownership already exists

Production currently notifies only after a valid hidden completion produces durable unread `.marked` in `PanelController`. Visible completions, invalid/stray finishes and already-handled duplicates do not produce the notification projection callback.

This trigger contract remains unchanged.

### 2.2 Exact-Slot routing already exists

`ChatGPTCompletionNotificationPayload` stores only a persistent Slot UUID plus schema version/kind. Default-action handling routes that UUID through `PanelController.presentSlotFromCompletionNotification(...)`, which selects the exact Slot and reuses existing presentation/materialization ownership.

This route must be preserved, not redesigned.

### 2.3 Current notification content is intentionally generic

The delivered Phase 3 contract froze:

```text
title = FloatTabs
body  = A ChatGPT response is ready.
```

and explicitly prohibited prompt/response content in the notification body.

The user has now changed that product requirement: the notification should identify the target Tab/Slot and show a short assistant-response preview.

This contract supersedes the old Phase 3 generic-content restriction only for the notification title/body projection. The routing payload privacy boundary remains unchanged.

### 2.4 Current delivery diagnostics overstate what is proven

`UNUserNotificationCenter.add(...)` success proves that the system accepted the request. It does **not** prove that macOS visibly displayed a banner. Alert style, Notification Center visibility, preview policy and Focus/system policy can affect what the user sees.

Public `UNNotificationSettings` exposes authorization status, alert setting/style, Notification Center setting and preview setting. FloatTabs can record those bounded settings facts. FloatTabs must not claim it can prove current Focus suppression through a public API when it cannot.

## 3. Frozen ownership

### 3.1 Completion / unread truth

Unchanged:

- `ChatGPTAttentionBridge` / `WebAttentionCoordinator` own generation/Attention sensing;
- `ChatGPTUnreadResponseCoordinator` / `UnreadResponseStore` own durable unread truth;
- `PanelController` owns completion handoff and presentation facts.

No notification code may become a second completion or unread writer.

### 3.2 Response preview extraction

`ChatGPTResponseExtraction` remains the semantic DOM-selection source for identifying the latest assistant response root.

`ChatGPTResponseBridge` may add one bounded **one-shot preview snapshot** API. It may evaluate a script in its existing isolated content world and must retain its existing current-WebView/current-document invalidation checks.

The preview API is projection support only. It must not:

- persist response text;
- start periodic preview polling;
- become unread truth;
- become generation truth;
- retain response body after the projection request is formed.

Keep preview extraction separate from the existing `snapshotLatestResponseStatus(...)` contract so ordinary status/acknowledgement snapshots do not begin carrying response body text.

### 3.3 Native notification projection

`ChatGPTCompletionNotificationCoordinator` remains the only owner of `UNUserNotificationCenter` integration, authorization/settings preflight, request construction, system submission, replacement/withdrawal and notification-specific diagnostics.

It may receive bounded projection input:

```text
slot_id
slot_display_name
assistant_preview?  // ephemeral, bounded, optional
```

It must never resolve WebView/Tab/Profile state itself.

### 3.4 App / presentation composition

`AppCoordinator` remains composition only.

`PanelController` may resolve the current Slot display name and request a one-shot preview when a hidden completion is newly `.marked`, then hand the bounded projection input to App composition.

The existing exact-Slot notification activation route remains the only navigation path.

## 4. Notification content contract

### 4.1 Title

Use the persistent Slot/Web App display name as the notification title.

Normalization:

- trim surrounding whitespace;
- collapse pathological internal whitespace only if needed for a stable title;
- cap at 80 user-perceived characters;
- if the normalized Slot name is empty, fall back to `ChatGPT`.

The system already displays the application identity/header; do not duplicate `FloatTabs` into the title unless required by a fallback.

### 4.2 Body preview

The body is a bounded plain-text preview of the latest completed assistant response.

Extraction rules:

- use the same assistant-root semantics already owned by `ChatGPTResponseExtraction`;
- include assistant response content only;
- exclude prompt/user text, composer text, buttons/toolbars/action labels, hidden content and script/style/noscript content;
- normalize line/whitespace runs to readable single-spacing where appropriate;
- preserve Unicode safely;
- cap at 240 user-perceived characters;
- do not append raw HTML or Markdown source;
- if no trustworthy non-empty preview is available, use `A ChatGPT response is ready.`.

Preview extraction is best-effort. Failure, navigation replacement, Runtime replacement, document mismatch, no assistant root, or an untrustworthy/malformed result must fall back to the generic body rather than block the notification.

### 4.3 Routing payload remains privacy-bounded

`userInfo` remains exactly:

```text
version
kind
slot_id
```

Do **not** add Slot name, response preview, prompt, URL, Browser Profile identity, cookies/session data, document token, response identity or Runtime identity to the routing payload.

### 4.4 No FloatTabs persistence/logging of preview text

FloatTabs must not write Slot name or response preview into diagnostics, unread persistence, preferences, backup, Runtime snapshots or any new app-owned notification history.

The notification title/body is necessarily handed to the macOS notification subsystem for native display/history. FloatTabs adds no parallel persistent copy.

## 5. Reliability / system-settings contract

### 5.1 Settings preflight

Before submission, the notification backend/coordinator must obtain the current `UNNotificationSettings` through the injected system seam.

Normalize and expose only bounded enum facts required for diagnostics/decision-making:

- authorization status;
- alert setting;
- alert style;
- Notification Center setting;
- show-previews setting.

No private API or Focus/DND inspection is authorized.

### 5.2 Authorization flow

Use current settings as the source of truth.

```text
notDetermined
→ contextually request alert authorization
→ reread settings

authorized / provisional (where supported)
→ submit notification

denied / unavailable
→ skip system submission only
→ durable unread / sound / Runtime / user data remain unchanged
```

Do not repeatedly request authorization on every already-authorized completion.

An authorized app with alerts disabled may still submit the notification so Notification Center can apply the user’s chosen policy; diagnostics must make clear that a banner is not expected from FloatTabs’ perspective.

### 5.3 Submission semantics

Successful `UNUserNotificationCenter.add(...)` means **submitted/accepted by the system**, not “banner visibly displayed”.

Notification diagnostics must use semantics that preserve this distinction. Existing historical `notification.delivered` records remain historical evidence; new code should record a submission-success event/field that does not overclaim visible presentation.

### 5.4 Foreground presentation

Recognized FloatTabs completion notifications continue to request:

```text
.banner + .list
```

with no native notification sound. Existing FloatTabs completion sound remains independent.

### 5.5 Focus/system suppression

FloatTabs may state only what public settings prove. If submission succeeds and configured alert settings look enabled but no banner is observed, Focus or another system policy may be a possibility; diagnostics must not declare it as proven root cause.

## 6. Background-efficiency compatibility

The Phase 8 hidden-generation policy remains unchanged:

```text
hidden generation <30s    → 2s fallback watchdog
hidden generation 30–120s → 5s fallback watchdog
hidden generation >=120s  → 10s fallback watchdog
```

Event-driven completion remains primary.

Generating Runtime remains hard-protected. The notification task must not deep-freeze, release or recreate a generating Runtime.

The one-shot preview request happens only after a newly hidden completion becomes `.marked`. It must not create periodic polling or a new long-lived Runtime protection. If lifecycle reclaim races the preview snapshot, generic fallback notification is correct.

After completion, existing lifecycle policy may reclaim the Runtime. A later notification tap must continue to restore/materialize through existing ownership.

## 7. Expected product component boundaries

Expected production paths:

1. `FloatTabs/App/ChatGPTCompletionNotificationCoordinator.swift`
2. `FloatTabs/App/AppCoordinator.swift`
3. `FloatTabs/Panel/PanelController.swift`
4. `FloatTabs/Web/ChatGPTResponseBridge.swift`
5. `FloatTabs/Web/ChatGPTResponseExtraction.swift`

`FloatTabs/Web/WebViewPool.swift` may change only if a minimal read-only response-bridge projection seam is genuinely missing; no Runtime lifecycle semantics may change.

Additional touchpoints require a demonstrated product dependency; this contract does not grant or restrict repository write permission.

## 8. Relevant product test owners

Expected focused tests:

1. `FloatTabsTests/ChatGPTCompletionNotificationTests.swift`
2. `FloatTabsTests/ChatGPTResponseExtractionTests.swift`
3. `FloatTabsTests/ChatGPTResponseBridgeTests.swift`
4. `FloatTabsTests/WebAttentionCrossFeatureTests.swift`
5. a narrowly necessary diagnostics/privacy test only if new diagnostics fields require it.

## 9. Product regression scenarios

### Scenario N1 — preview extraction

Prove:

1. latest assistant response produces bounded plain text;
2. user/prompt/composer/action/hidden content is excluded;
3. whitespace and Unicode normalization are safe;
4. preview length is capped at 240 user-perceived characters;
5. missing/untrustworthy/generating/mismatched document state returns no trusted preview;
6. runtime/navigation invalidation prevents stale preview completion from being admitted;
7. status snapshots remain body-free.

### Scenario N2 — notification content + settings

Prove:

1. Slot name becomes the title;
2. trusted assistant preview becomes the body;
3. missing preview falls back to the generic body;
4. routing payload still contains only version/kind/slot_id;
5. current notification settings are read through the injected backend;
6. authorization is requested only from notDetermined and settings are reread afterward;
7. denied/unavailable state skips submission without mutating product truth;
8. authorized state submits even when macOS alert policy may suppress the banner;
9. same-Slot replacement semantics remain deterministic;
10. foreground recognized notification remains banner/list without notification sound;
11. diagnostics contain no Slot name or response preview text.

### Scenario N3 — production composition / routing

Prove:

1. hidden valid `.marked` completion emits exactly one projection attempt;
2. visible completion emits none;
3. invalid/duplicate completion emits none;
4. preview failure still emits one generic notification attempt;
5. default-action tap routes the exact Slot;
6. stale/deleted Slot never falls back to current Slot;
7. non-resident target restores through existing Runtime ownership;
8. unread acknowledgement remains presentation-aware and is not cleared merely by system submission;
9. existing completion sound semantics remain unchanged.

### Scenario N4 — background/lifecycle regression

Prove:

- hidden-generation 2s/5s/10s watchdog behavior is unchanged;
- generating Runtime protection is unchanged;
- healthy lifecycle target=2 and 30s grace are unchanged;
- pressure-ladder semantics are unchanged;
- no notification-specific polling, second lifecycle writer or persistent response-content store is added.

The scenario coverage above defines notification-specific correctness and privacy expectations. Full-suite selection, build/CI invocation, independent review and merge gates are not defined by this technical contract.

## 10. Human acceptance

This task changes real notification content and click interaction, so final product acceptance remains human-owned.

After machine gates and independent review, stop for human validation of at least:

1. FloatTabs hidden, ChatGPT completes → notification appears when macOS alert settings allow it;
2. notification shows the correct Slot name;
3. notification shows a sensible assistant-response preview when macOS preview policy allows it;
4. clicking the notification opens the exact Slot;
5. clicking a notification for a Runtime reclaimed after completion still restores the exact Slot;
6. disabling macOS notification previews can hide the body without being treated as an app failure;
7. disabling alert banners is reflected by diagnostics rather than misreported as successful visible presentation.

These real-Mac observations are required product evidence; this document does not set or imply a human-acceptance verdict.

## 11. Explicit non-scope

Do not add:

- a new FloatTabs notification preference/settings screen;
- notification sound changes;
- Time Sensitive / Critical Alert escalation;
- Focus/DND bypass;
- remote push notifications;
- service-worker/Web Notification API emulation;
- persisted notification history;
- persisted response text;
- prompt text in notifications;
- URLs, Browser Profile or session identity in notification content/payload;
- lifecycle-policy changes;
- aggregate memory-budget work;
- Browser Profile/session/cache resets.

## 12. Product design incompatibilities

The following behaviors are outside this product contract and require a separate technical decision:

- a second completion/unread/Tab/Runtime writer;
- periodic response-preview polling;
- changing ChatGPT generation detection semantics merely to obtain preview text;
- storing response preview in app persistence/diagnostics/backup;
- adding preview/name to routing `userInfo`;
- delaying notification on an unbounded WebKit callback;
- keeping a completed Runtime resident solely for notification preview;
- private APIs or an unsupported Focus-state claim;
- changing lifecycle timers, pressure ordering or generation protection;
- destructive user/session data mutation;

## 13. Technical dependency order

Notification content depends on a one-shot, current-document assistant-preview snapshot; the native projection then combines it with exact Slot identity, current macOS notification settings, and the existing hidden `.marked` completion route. Exact-Slot tap routing and durable-unread acknowledgement remain independent. No notification preview is persisted or logged.

This dependency description is not a Git branch, PR, CI, audit or release workflow.

## 14. Historical design context

The user changed the earlier Phase 3 generic notification-content requirement to allow a bounded assistant-response preview and target Slot name, while retaining the existing privacy and exact-Slot routing restrictions. This records the product decision only; no present task approval or change permission is created.
