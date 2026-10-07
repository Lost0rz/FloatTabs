# FloatTabs Current Task

**Task ID:** FT-SPEECH-001
**Title:** Positive Assistant Content Ownership V4
**Status:** `ACTIVE — POSITIVE_ASSISTANT_CONTENT_OWNERSHIP_V4`
**Mode:** `TEST_FIRST_MINIMAL_PRODUCTION_FIX`

## Objective

Restore `Read Latest Response` on the current ChatGPT renderer while preserving the safety guarantee that user-owned input cannot be admitted into speech.

## Canonical live evidence

```text
V1_HUMAN_RESULT=user_message_then_assistant_response
V2_HUMAN_RESULT=no_speech
V3_HUMAN_RESULT=no_speech
V3_IMPLEMENTATION_HEAD=976b6816c84fdf5e03ae5d089d402927c16626c3
```

V3 made `conversation-turn` tag-agnostic but still produced no live speech.

## Web code-audit finding

Current production discovery still depends mainly on legacy `data-message-author-role` plus a Regenerate-based fallback.

Current ChatGPT renderer variants use additional positive semantic ownership signals, including:

```text
[data-testid^="conversation-turn-"][data-turn="assistant"]
[data-conversation-role="assistant"]
```

Newer renderer variants can group user and assistant material under one `[data-turn-key]` shell. The shell must not become the extraction root because that can reintroduce the original defect. The assistant-owned descendant itself is the safe root.

Positive assistant ownership must not require a Regenerate action. The existing Regenerate fallback remains legacy-only and fail-closed.

## Baseline

- Repository: `Lost0rz/FloatTabs`
- Branch: `fix/chatgpt-speech-response-ownership`
- Upstream: `origin/fix/chatgpt-speech-response-ownership`
- Accepted main base: `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- PR #102 is separate and must remain unchanged

Gate 0: fresh fetch/prune, exact local/upstream HEAD, clean worktree, accepted merge-base, then re-read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`. Stop only on unexpected drift/dirty state/wrong base.

## Gate 1 — V4 formal RED

Tests first. Do not edit production before observed RED.

### RED A — grouped current renderer

Add the smallest fixture equivalent to:

```html
<div data-turn-key="turn-1">
  <div data-user-message-bubble>
    <p>User prompt must not be spoken.</p>
  </div>
  <div data-conversation-role="assistant">
    <div data-markdown-text-style="assistant-message">
      <p>Assistant answer only.</p>
    </div>
  </div>
  <div class="turn-action-controls">
    <button data-testid="copy-turn-action-button">Copy</button>
  </div>
</div>
```

No Regenerate button. No `data-message-author-role` requirement.

Required contract:

```text
payload.blocks == ["Assistant answer only."]
user prompt absent
```

Against unchanged V3 production, first run must be RED / no response. If not RED, STOP for Web review.

### RED B — semantic turn role

Add a tag-agnostic fixture such as:

```html
<section data-testid="conversation-turn-42" data-turn="assistant">
  <div><p>Assistant turn answer.</p></div>
</section>
```

No Regenerate button.

Expected: assistant response extracted from the positively owned assistant turn.

Also retain existing regressions proving:

- generic ancestor without semantic ownership fails closed;
- user-owned content is never included;
- explicit assistant-role path remains green.

## Gate 2 — Minimal production fix

Modify only:

```text
FloatTabs/Web/ChatGPTResponseExtraction.swift
```

Implement one shared positive assistant-root policy used consistently by latest-response extraction and trusted assistant-pointer ownership.

Required behavior:

1. preserve existing explicit assistant selectors:
   - `[data-message-author-role="assistant"]`
   - `[data-message-role="assistant"]`
2. recognize rendered `[data-conversation-role="assistant"]` as a positive assistant content root;
3. recognize rendered semantic turns `[data-testid*="conversation-turn"][data-turn="assistant"]` as positively assistant-owned;
4. preserve existing role-proven semantic-turn behavior;
5. do NOT select an entire `[data-turn-key]` group merely because it contains an assistant marker;
6. do NOT require Regenerate for any positively assistant-owned root;
7. keep `latestRegenerateOwnedResponse()` only as the legacy last-resort path;
8. keep legacy fallback fail-closed when no qualifying semantic turn exists;
9. where fallback/user rejection is evaluated, include stable user markers such as `[data-turn="user"]`, `[data-conversation-role="user"]`, and `[data-user-message-bubble]`.

Diagnostics in this same file may be updated only as needed to classify the newly supported positive assistant roots; they must remain observational and contain no conversation text.

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

## Gate 3 — Focused GREEN

Run at minimum:

- new grouped-renderer RED regression;
- new `data-turn="assistant"` regression;
- existing generic-ancestor fail-closed regression;
- all `ChatGPTResponseExtractionTests`;
- relevant `AssistantSpeechCoordinatorTests`.

All must pass.

Do not claim live success from synthetic GREEN alone.

## Gate 4 — Build/install V4 QA

After focused GREEN:

- commit product/test change;
- build fresh exact-head arm64 Debug;
- replace only `/Applications/FloatTabs.app`;
- preserve Browser Profiles, Slots, cookies, WebKit state, authenticated sessions, Application Support, preferences, and diagnostics;
- verify exact source revision, app path, version/build, architecture, and running PID;
- do not trigger `Read Latest Response` for the user.

Normal fast-forward push to the implementation branch is allowed only if fresh remote still matches the expected pre-push authority. No force push.

## Not authorized

```text
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
V4_RED_GROUPED_TEST:
V4_RED_DATA_TURN_TEST:
FIRST_RUN_RED:
RED_ACTUAL_BEHAVIOR:
PRODUCTION_FIX_HEAD:
POSITIVE_ASSISTANT_ROOT_CONTRACT:
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
