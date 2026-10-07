# FloatTabs Current Task

**Task ID:** FT-SPEECH-001
**Title:** Web-Audited Assistant Content Unit Ownership V4
**Status:** `ACTIVE — WEB_AUDITED_ASSISTANT_CONTENT_UNIT_FIX_V4`
**Mode:** `EXACT_IMPLEMENTATION_AND_VALIDATION_ONLY`

## Objective

Fix `Read Latest Response` so it reads the latest assistant response on the current ChatGPT renderer and never admits the user's prompt into speech.

The Web control-plane audit is complete. Local execution must implement the contract below; it is not responsible for another open-ended root-cause investigation.

## Canonical live evidence

```text
V1_HUMAN_RESULT=user_message_then_assistant_response
V2_HUMAN_RESULT=no_speech
V3_HUMAN_RESULT=no_speech
V3_IMPLEMENTATION_HEAD=976b6816c84fdf5e03ae5d089d402927c16626c3
```

## Authoritative Web code-audit verdict

```text
ROOT_CAUSE_CONFIRMED=YES
CAUSE_LAYER=ChatGPTResponseExtraction response-root ownership
TTS_CAUSAL=NO
SPEECH_QUEUE_CAUSAL=NO
CONTENT_CLEANER_CAUSAL=NO
LOCAL_ROOT_CAUSE_AUDIT_REQUIRED=NO
```

The actual production path is:

```text
Read Latest Response
→ ChatGPTResponseBridge.extractLatest
→ latestAssistantResponseRoot
→ assistantResponseRoots
→ structuredBlocks(root)
→ payload.blocks
→ SpeechLanguageRouter.utteranceRequests
→ playback
```

`structuredBlocks(root)` recursively extracts the supplied root. The coordinator then routes all resulting blocks to speech. Therefore **the response root is the author-ownership boundary**. If it contains user + assistant material, the original defect is inevitable; if it is too narrow/hidden, speech is empty.

## Audited current-renderer boundary

A current grouped renderer may look like:

```html
<div data-turn-key="turn-1">
  <div data-content-search-unit-key="turn-1:0:user">
    <div data-user-message-bubble>
      <p>User prompt must not be spoken.</p>
    </div>
  </div>

  <div data-content-search-unit-key="turn-1:1:assistant">
    <h4 class="sr-only" data-conversation-role="assistant">ChatGPT said:</h4>
    <div data-markdown-text-style="assistant-message">
      <p>Assistant answer only.</p>
    </div>
  </div>

  <div class="turn-action-controls">
    <button data-testid="copy-turn-action-button">Copy</button>
  </div>
</div>
```

Important conclusions:

- `[data-conversation-role="assistant"]` can be a hidden semantic marker, so it must **not** itself be assumed to contain the readable answer.
- The safe root is its nearest rendered `[data-content-search-unit-key]` content unit that contains response content and no user marker.
- The outer `[data-turn-key]` group is forbidden as a speech root because it can contain both user and assistant material.
- A classic semantic turn `[data-testid*="conversation-turn"][data-turn="assistant"]` is also a positive assistant root and does not require Regenerate.
- Legacy explicit assistant roots remain supported.
- Regenerate discovery is legacy fallback only.

## Baseline

- Repository: `Lost0rz/FloatTabs`
- Branch: `fix/chatgpt-speech-response-ownership`
- Upstream: `origin/fix/chatgpt-speech-response-ownership`
- Accepted main base: `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- PR #102 is separate and must remain unchanged

Gate 0: fetch/prune; require exact local/upstream HEAD, clean worktree, accepted merge-base; re-read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`. Stop on actual mismatch only.

## Gate 1 — exact RED fixtures

Tests first. These tests are specified by Web; Local must not replace them with a different exploratory diagnosis.

### RED A — grouped renderer assistant content unit

Add a fixture matching the grouped DOM above.

Required behavior:

```text
payload.kind=response
payload.blocks=["Assistant answer only."]
"User prompt must not be spoken." absent
no Regenerate control present
```

Against unchanged V3 product, first run must be RED, expected as nil/no response. If it unexpectedly passes, STOP and return only that contradiction to Web.

### RED B — classic data-turn assistant

```html
<section data-testid="conversation-turn-42" data-turn="assistant">
  <div><p>Assistant turn answer.</p></div>
</section>
```

No Regenerate control.

Required:

```text
payload.blocks=["Assistant turn answer."]
```

### RED C — mixed renderer ordering

Use an older legacy assistant response before a newer grouped-renderer assistant unit:

```html
<div data-message-author-role="assistant">
  <p>Older assistant answer.</p>
</div>
<div data-turn-key="new-turn">
  <div data-content-search-unit-key="new-turn:0:user">
    <div data-user-message-bubble><p>Newest user prompt.</p></div>
  </div>
  <div data-content-search-unit-key="new-turn:1:assistant">
    <h4 class="sr-only" data-conversation-role="assistant">ChatGPT said:</h4>
    <div data-markdown-text-style="assistant-message">
      <p>Newest assistant answer.</p>
    </div>
  </div>
</div>
```

Required:

```text
latest payload.blocks=["Newest assistant answer."]
older assistant not selected
user prompt absent
```

This proves latest selection works across renderer generations instead of returning early from the first selector family.

Retain existing regressions proving generic unowned ancestor fails closed and explicit legacy assistant extraction remains green.

## Gate 2 — exact production contract

Modify only:

```text
FloatTabs/Web/ChatGPTResponseExtraction.swift
```

Tests may change only in `FloatTabsTests/ChatGPTResponseExtractionTests.swift` for the specified regressions.

### A. Positive root candidate families

Collect candidates from **all** supported positive schemas; do not return early after the first family:

1. legacy explicit assistant roots:
   - `[data-message-author-role="assistant"]`
   - `[data-message-role="assistant"]`
2. classic assistant turns:
   - `[data-testid*="conversation-turn"][data-turn="assistant"]`
   - existing role-proven semantic conversation-turn behavior
3. current grouped-renderer assistant content units:
   - rendered `[data-content-search-unit-key]` containing `[data-conversation-role="assistant"]`;
   - the unit must contain response content and must not contain user-owned markers.

Support `[data-chatgpt-agent-turn-start]` only when it positively identifies an assistant content unit under the same content-unit boundary; never widen to its enclosing `[data-turn-key]` group.

### B. Narrowing and ordering

After collecting positive candidates:

- deduplicate identical elements;
- if one qualifying candidate contains another qualifying content-bearing candidate, prefer the narrower candidate;
- sort remaining candidates by DOM document order;
- `latestAssistantResponseRoot()` selects the last root in document order.

This is required because old and new renderer structures can coexist in the same conversation history.

### C. User ownership rejection

Extend the existing user/non-assistant marker policy with:

```text
[data-turn="user"]
[data-conversation-role="user"]
[data-user-message-bubble]
```

The outer `[data-turn-key]` group must never qualify as a speech root merely because it contains an assistant descendant.

### D. Legacy fallback

Only when the positive-root set is empty may `latestRegenerateOwnedResponse()` run.

Preserve its current safety properties:

```text
semantic-turn bounded
no arbitrary generic ancestor
fail closed when no qualifying boundary exists
```

Do not make Regenerate a requirement for any positively assistant-owned root.

### E. Trusted assistant pointer

Use the same positive ownership policy for `assistantResponseRootFor(eventTarget)` so trusted pointer ownership cannot disagree with latest-response ownership. Walking upward from the event target may return a qualifying positive root, but must not return the `[data-turn-key]` shell.

### F. Diagnostics

Diagnostics may be adjusted in this same file only to recognize the new positive root categories. They remain observational; no production filtering belongs in diagnostics.

Do not change:

```text
SpeechContentBlock
SpeechContentCleaner
SpeechLanguageRouter
SpeechQueue/playback
SpeechService
notifications
PR #102
```

## Gate 3 — focused GREEN

Run at minimum:

- RED A grouped-renderer test;
- RED B `data-turn="assistant"` test;
- RED C mixed-renderer latest-order test;
- existing generic-ancestor fail-closed regression;
- all `ChatGPTResponseExtractionTests`;
- relevant `AssistantSpeechCoordinatorTests`.

All must pass.

Local does not perform another architectural/root-cause audit after GREEN. Return failures as evidence to Web if the exact contract cannot be implemented.

## Gate 4 — build/install QA

After focused GREEN:

- commit product/test change;
- build exact-head arm64 Debug;
- replace only `/Applications/FloatTabs.app`;
- preserve Browser Profiles, Slots, cookies, WebKit/auth state, Application Support, preferences, and diagnostics;
- verify source revision, app path, version/build, architecture, and PID;
- do not trigger `Read Latest Response` for the user.

Normal fast-forward push is allowed only after a fresh remote check. No force push.

## Not authorized

```text
LOCAL_OPEN_ENDED_ROOT_CAUSE_AUDIT=NO
TOPOLOGY_PROBE_AUTHORIZED=NO
ARBITRARY_ANCESTOR_FALLBACK=NO
GROUP_SHELL_AS_SPEECH_ROOT=NO
TTS_CHANGE_AUTHORIZED=NO
SPEECH_QUEUE_CHANGE_AUTHORIZED=NO
CONTENT_CLEANER_CHANGE_AUTHORIZED=NO
BROAD_DOM_REDESIGN_AUTHORIZED=NO
PR102_CHANGE_AUTHORIZED=NO
IMPLEMENTATION_PR_AUTHORIZED=NO
MERGE_AUTHORIZED=NO
FULL_FINAL_SUITE_AUTHORIZED=NO
```

## Acceptance

Stop after verified V4 QA installation at:

```text
FINAL_STATE=WAITING_FOR_USER_FIX_V4_ACCEPTANCE
```

Receipt:

```text
TASK_ID:
START_HEAD:
CONTROL_HEAD:
WEB_AUDIT_ACKNOWLEDGED:
V4_RED_GROUPED_UNIT_TEST:
V4_RED_DATA_TURN_TEST:
V4_RED_MIXED_RENDERER_ORDER_TEST:
FIRST_RUN_RED:
RED_ACTUAL_BEHAVIOR:
PRODUCTION_FIX_HEAD:
POSITIVE_ROOT_FAMILIES:
NARROWER_ROOT_PREFERENCE:
MIXED_RENDERER_LATEST_SELECTION:
GROUP_SHELL_NOT_SPEECH_ROOT:
GENERIC_ANCESTOR_FAIL_CLOSED_TEST:
FOCUSED_EXTRACTION_TESTS:
FOCUSED_SPEECH_TESTS:
QA_BUILD:
APP_PATH:
INSTALLED_SOURCE_HEAD:
INSTALLED_VERSION_BUILD:
INSTALLED_ARCH:
RUNNING_PID:
USER_DATA_PRESERVED:
PR102_UNCHANGED:
REMOTE_SYNC:
WORKTREE_STATUS:
FINAL_STATE=WAITING_FOR_USER_FIX_V4_ACCEPTANCE
```
