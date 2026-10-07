# FloatTabs Current Task

**Task ID:** FT-SPEECH-001
**Title:** Tag-Agnostic Conversation Turn Fix V3
**Status:** `WAITING_FOR_USER_FIX_V3_ACCEPTANCE`
**Mode:** `QA_INSTALLED_WAITING_FOR_HUMAN_ACCEPTANCE`

## Objective

Restore `Read Latest Response` speech while preserving the V2 safety guarantee that user-owned input cannot be admitted through an arbitrary fallback ancestor.

## Canonical evidence

```text
V1_LIVE_FAILURE=user_message_then_assistant_response
V2_IMPLEMENTATION_HEAD=3e707eb4725bc4549daf991d4d08ffa9f50745b7
V2_HUMAN_ACCEPTANCE=FAIL_COMPATIBILITY
V2_LIVE_OBSERVATION=NO_SPEECH
UNSAFE_USER_TEXT_SPOKEN_AFTER_V2=NO
```

Web audit of V2 found a direct implementation mismatch:

```text
INTENDED_CONTRACT=nearest semantic conversation-turn boundary, tag-agnostic
ACTUAL_V2_SELECTOR=article[data-testid*="conversation-turn"]
```

Independent live-site evidence from 2026 confirms ChatGPT conversation turns can be `<section>` while retaining `data-testid="conversation-turn-N"` / `data-turn` semantics. The safe response is to remove the element-tag qualification, not to restore arbitrary ancestor fallback.

## Baseline

- Repository: `Lost0rz/FloatTabs`
- Branch: `fix/chatgpt-speech-response-ownership`
- Upstream: `origin/fix/chatgpt-speech-response-ownership`
- Accepted main base: `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- PR #102 is separate and must remain unchanged.

Gate 0: fresh fetch/prune, require clean checkout/worktree, exact local/upstream HEAD, correct accepted merge-base, then re-read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`. Stop on unexpected drift.

## Gate 1 — V3 formal RED

Tests first; do not edit production before observed RED.

Add the smallest fixture:

```html
<section data-testid="conversation-turn-42">
  <div><p>Latest assistant response.</p></div>
  <div role="toolbar">
    <button aria-label="Regenerate response">Regenerate</button>
  </div>
</section>
```

No explicit assistant author-role marker is required for this fallback fixture.

Required current-V2 behavior on first run:

```text
FIRST_RUN_RED=YES
ACTUAL=payload nil / no response because selector is article-qualified
EXPECTED=latest assistant response extracted from qualifying semantic turn
```

Also add/retain a safety regression proving a generic ancestor with Regenerate but no semantic conversation-turn still fails closed.

If the new `<section>` test is not RED against unchanged V2 production, STOP for Web review.

## Gate 2 — Minimal production fix

Modify only `FloatTabs/Web/ChatGPTResponseExtraction.swift`.

Change the semantic turn matching from tag-qualified:

```text
article[data-testid*="conversation-turn"]
```

to tag-agnostic:

```text
[data-testid*="conversation-turn"]
```

Apply the same semantic boundary consistently where needed for the existing conversation-turn response-root path, without broadening to generated CSS classes or generic ancestors.

Preserve all existing validation:

- rendered;
- response content present;
- exactly one applicable Regenerate response action for fallback;
- no explicit user/composer/status/alert/live marker;
- explicit assistant-role path remains preferred;
- no qualifying semantic turn => fail closed.

Do not restore arbitrary ancestor traversal as ownership proof.

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

- new V3 `<section>` regression;
- existing ambiguous-generic-fallback fail-closed regression;
- all `ChatGPTResponseExtractionTests`;
- relevant `AssistantSpeechCoordinatorTests`.

All must pass.

Do not claim live fix from synthetic GREEN alone.

## Gate 4 — Build/install V3 QA

After focused GREEN:

- commit the V3 product/test change;
- build fresh exact-head arm64 Debug;
- replace only `/Applications/FloatTabs.app`;
- preserve Browser Profiles, Slots, cookies, WebKit state, authenticated sessions, Application Support, preferences, and diagnostics;
- verify exact source revision, app path, version/build, architecture, and running PID.

Do not trigger `Read Latest Response` for the user.

Normal fast-forward push to the implementation branch is allowed only if fresh remote still matches the expected pre-push authority. No force push.

## Not authorized

```text
TOPOLOGY_PROBE_AUTHORIZED=NO
ARBITRARY_ANCESTOR_FALLBACK=NO
TTS_CHANGE_AUTHORIZED=NO
SPEECH_QUEUE_CHANGE_AUTHORIZED=NO
CONTENT_CLEANER_CHANGE_AUTHORIZED=NO
BROAD_DOM_REDESIGN_AUTHORIZED=NO
PR102_CHANGE_AUTHORIZED=NO
IMPLEMENTATION_PR_AUTHORIZED=NO
MERGE_AUTHORIZED=NO
FULL_FINAL_SUITE_AUTHORIZED=NO
```

## Execution result — 2026-10-07

```text
START_CONTROL_HEAD=e3526d1312a91cceffdf815101c6a336618a43ce
EXECUTION_BRANCH=codex/ft-speech-001-v2
V3_RED_TEST=testRegenerateFallbackAcceptsTagAgnosticSemanticConversationTurnSection
FIRST_RUN_RED=YES
RED_ACTUAL=payload nil / no response
RED_EXPECTED=Latest assistant response extracted from the section semantic turn
V3_PRODUCTION_FIX_HEAD=976b6816c84fdf5e03ae5d089d402927c16626c3
TAG_AGNOSTIC_TURN_CONTRACT=PASS
GENERIC_ANCESTOR_FAIL_CLOSED_TEST=PASS
FOCUSED_EXTRACTION_TESTS=PASS (44)
FOCUSED_SPEECH_TESTS=PASS (98)
QA_BUILD=PASS (Debug, arm64)
APP_PATH=/Applications/FloatTabs.app
INSTALLED_SOURCE_HEAD=976b6816c84fdf5e03ae5d089d402927c16626c3
INSTALLED_VERSION_BUILD=0.5.2 (20)
INSTALLED_ARCH=arm64
RUNNING_PID=45659
USER_DATA_PRESERVED=YES
READ_LATEST_RESPONSE_TRIGGERED_BY_EXECUTOR=NO
```

The pre-install inventory found 26 FloatTabs Application Support entries, 3,285 WebKit entries, 9 cookie files, and 9 diagnostic files. After installation all pre-existing paths remained; cookie files, the profiles/slots configuration, preferences, and diagnostic history were verified unchanged/preserved. No user or WebKit data was cleared or reset.

The V3 QA app is installed and running. Stop here for one human Read Latest Response acceptance; do not trigger speech, rebuild, reinstall, or start another fix before the user result is recorded.

## Acceptance

Stop after verified V3 QA installation at:

```text
FINAL_STATE=WAITING_FOR_USER_FIX_V3_ACCEPTANCE
```

Receipt:

```text
TASK_ID:
START_HEAD:
CONTROL_HEAD:
V3_RED_TEST:
FIRST_RUN_RED:
RED_ACTUAL_BEHAVIOR:
PRODUCTION_FIX_HEAD:
TAG_AGNOSTIC_TURN_CONTRACT:
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
FINAL_STATE=WAITING_FOR_USER_FIX_V3_ACCEPTANCE
```
