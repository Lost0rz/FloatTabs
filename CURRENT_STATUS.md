# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: NATIVE COMPLETION NOTIFICATION — CORRECTIVE 001 / IMPLEMENTATION EXISTS / INDEPENDENT AUDIT HOLD**

Current task: `FT-NOTIFICATION-RELIABILITY-RICH-PREVIEW-001` — **ACTIVE / CORRECTIVE 001 AUTHORIZED**.

Task branch:

`codex/notification-reliability-rich-preview-001`

Execution baseline:

`main@08831ad2cc3e7f18432b1a6ecdc983e849a992aa`

## Repository / delivery state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
MAIN_BASELINE=08831AD2
OPEN_PRS_AT_TASK_START=0
TASK=FT-NOTIFICATION-RELIABILITY-RICH-PREVIEW-001
TASK_STATE=ACTIVE_CORRECTIVE_001
IMPLEMENTATION=EXISTS_ON_PR_193
AUDITED_HEAD=18161e9b91159acd4a164aca824cdedbd10d48ce
INDEPENDENT_AUDIT=HOLD
CORRECTIVE_A=BLOCKING_TIMEOUT_AND_EXACTLY_ONCE
CORRECTIVE_B=IMPORTANT_DESCENDANT_SANITIZATION_AND_DEDUP
HUMAN_UI_ACCEPTANCE=PENDING_NOT_STARTED
MERGE_AUTHORIZED=NO
```

Current task contract:

`docs/architecture/FloatTabs_Native_Completion_Notification_Reliability_Rich_Preview_Contract_V1.md`

## Current implementation and audit baseline

```text
PR_193=OPEN_DRAFT_MERGEABLE_UNMERGED
BASE=main@08831ad2cc3e7f18432b1a6ecdc983e849a992aa
AUDITED_HEAD=18161e9b91159acd4a164aca824cdedbd10d48ce
AUDITED_HEAD_CI=PASS
AUDITED_HEAD_QA_DMG=PASS
INDEPENDENT_SEMANTIC_VERDICT=HOLD
```

The current corrective execution is limited to two independent audit findings:

1. **Blocking:** one-shot response preview has no bounded timeout/arbitration, so a suspended provider can suppress the `.marked` notification projection. Add one bounded provider-vs-timeout race; provider failure, timeout, or in-flight invalidation must settle exactly once with `nil`; late results are ignored.
2. **Important:** preview DOM projection reads `innerText` from selected nodes after checking only whether each selected node is excluded. Excluded descendants can leak into preview text and nested selected nodes can duplicate text. Sanitize descendants and deduplicate nested content while preserving the existing assistant-root and selector policy.

Fresh corrective-head verification and independent re-audit are required. Human native-notification acceptance remains `PENDING / NOT_STARTED`; merge remains unauthorized.

## Original notification baseline (`main@08831ad2`)

The following facts describe the pre-implementation baseline used to authorize the original task; they are not the current PR implementation state.

Fresh audit of the production notification path on the original main baseline established:

1. `ChatGPTCompletionNotificationCoordinator` is the sole native notification projection owner and the sole `UNUserNotificationCenter` integration.
2. Notification attempts are triggered only for a valid hidden ChatGPT completion that produces durable unread `.marked`.
3. Visible completion, invalid/stray finish and already-handled duplicate completion do not notify.
4. Current notification content is intentionally generic:

```text
title = FloatTabs
body  = A ChatGPT response is ready.
```

5. The old Phase 3 contract deliberately prohibited response text in the notification body. The user has now superseded that product requirement for native notification title/body content.
6. Routing `userInfo` currently contains only `version / kind / slot_id`; this privacy-bounded routing payload remains correct and must not expand.
7. Default-action notification click already routes the exact persistent Slot UUID through `PanelController.presentSlotFromCompletionNotification(...)` and the existing Runtime restore/materialization path.
8. Current response infrastructure identifies the latest assistant response root and status/identity but deliberately does not extract response-body text.
9. Current notification diagnostics cannot distinguish “system accepted request” from “user visibly saw a banner”, and they do not capture the current public macOS notification settings state.

## Frozen new product behavior

### Notification content

```text
Title = normalized target Slot/Web App name
        fallback ChatGPT
        max 80 user-perceived characters

Body  = latest completed assistant-response plain-text preview
        normalized whitespace
        max 240 user-perceived characters
        fallback A ChatGPT response is ready.
```

Do not include prompt/user text, URL, Browser Profile/session identity, Runtime identity or document token.

Slot name and preview are ephemeral projection inputs only. FloatTabs must not persist or log them.

### Preview extraction

Reuse the existing assistant-root semantics in `ChatGPTResponseExtraction`.

`ChatGPTResponseBridge` may add a separate one-shot preview snapshot API with existing WebView/document invalidation guards. The existing response-status snapshot must remain body-free.

Preview extraction is best-effort and may fall back to the generic body if the Runtime/navigation changes or trustworthy content is unavailable. It must not add periodic polling or new long-lived Runtime protection.

### Notification reliability / diagnostics

Before system submission, read current public `UNNotificationSettings` through the injectable backend seam and record bounded settings facts only:

- authorization status;
- alert setting;
- alert style;
- Notification Center setting;
- show-previews setting.

If authorization is `notDetermined`, request `.alert` contextually and reread settings. Do not repeatedly request authorization for every already-authorized completion.

A successful `UNUserNotificationCenter.add(...)` proves system submission/acceptance only. It does not prove that macOS displayed a visible banner. Diagnostics must not overclaim visible delivery or claim Focus suppression as a proven root cause.

### Exact routing

Preserve:

```text
notification default action
→ persistent Slot UUID
→ exact Slot select
→ existing presentation/materialization
```

A stale/deleted Slot must remain a safe no-op with no fallback to the current Slot.

## Background / lifecycle compatibility

The merged Phase 8 background policy remains authoritative and unchanged:

```text
hidden generation <30s    → 2s fallback watchdog
hidden generation 30–120s → 5s fallback watchdog
hidden generation >=120s  → 10s fallback watchdog
```

Generating Runtime remains hard-protected. The new notification task must not change lifecycle timers, pressure ordering or generation protection.

After completion, the Runtime may be reclaimed normally. Notification click must continue to restore a non-resident target through existing lifecycle ownership.

## Expected implementation scope

Production:

- `FloatTabs/App/ChatGPTCompletionNotificationCoordinator.swift`
- `FloatTabs/App/AppCoordinator.swift`
- `FloatTabs/Panel/PanelController.swift`
- `FloatTabs/Web/ChatGPTResponseBridge.swift`
- `FloatTabs/Web/ChatGPTResponseExtraction.swift`
- `FloatTabs/Web/WebViewPool.swift` only if a minimal read-only response-bridge seam is proven necessary.

Focused tests:

- `FloatTabsTests/ChatGPTCompletionNotificationTests.swift`
- `FloatTabsTests/ChatGPTResponseExtractionTests.swift`
- `FloatTabsTests/ChatGPTResponseBridgeTests.swift`
- `FloatTabsTests/WebAttentionCrossFeatureTests.swift`
- narrowly necessary diagnostics/privacy test if needed.

## Gates

```text
N0_AUDITED_IMPLEMENTATION=EXISTS_ON_PR_193
CORRECTIVE_A_TIMEOUT_EXACTLY_ONCE=PASS_LOCAL
CORRECTIVE_B_DOM_SANITIZATION_DEDUP=PASS_LOCAL
FOCUSED_CORRECTIVE_REGRESSIONS=PASS_197_OF_197
FRESH_FULL_XCTEST=PASS_1148_OF_1148
DEBUG_ARM64_BUILD=PASS
RELEASE_ARM64_BUILD=PASS
NATIVE_ARM64=PASS
PACKAGE_LOCK=UNCHANGED
PRIVACY_OWNERSHIP_SELF_AUDIT=PASS
HOST_GATE_EVIDENCE=PR_193_CURRENT_LITERAL_HEAD_CHECKS
QA_DMG_EVIDENCE=PR_193_CURRENT_LITERAL_HEAD_IF_TRIGGERED
FRESH_INDEPENDENT_AUDIT=WAITING
HUMAN_UI_ACCEPTANCE=PENDING_NOT_STARTED
MERGE=NOT_AUTHORIZED
```

Human acceptance is required because this task changes real native notification content and interaction. AI/browser/screenshot inspection cannot self-approve that gate.

## Previous lifecycle program state

The Phase 8 pressure + efficiency task remains **CLOSED / MERGED**. Its merged behavior and platform-blocked aggregate-memory track are unchanged.

Still preserved:

- Automatic normal target=2;
- Automatic inactive release=30s;
- warning progressively reclaims eligible Automatic only;
- critical reclaims Automatic first, then inactive/unprotected Keep Loaded;
- best-effort aggregate WebContent/GPU attribution remains forbidden;
- Browser Profile/session/product data mutation remains out of scope.

The broader lifecycle-program human acceptance is still pending and may be exercised together with the final integrated notification/runtime validation, but this notification task has its own explicit native-notification acceptance gate.

## Next gate

```text
CORRECTIVE_001
→ bounded timeout/exactly-once preview arbitration
→ DOM descendant sanitization/nested-text deduplication
→ focused corrective + existing regression suites
→ full XCTest / Debug arm64 / Release arm64 / native arm64
→ verify current literal-head self-hosted CI + QA DMG when triggered
→ fresh independent exact-diff / ownership / privacy audit
→ stop at WAITING_FOR_FRESH_INDEPENDENT_WEB_AUDIT
→ human notification acceptance remains PENDING / NOT_STARTED
```
