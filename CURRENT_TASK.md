# FloatTabs Current Task

**Task ID:** FT-SPEECH-001
**Title:** Positive Response Ownership Fix V2
**Status:** `ACTIVE — POSITIVE_RESPONSE_OWNERSHIP_FIX_V2`
**Mode:** `TEST_FIRST_MINIMAL_PRODUCTION_FIX`

## Objective

Fix `Read Latest Response` so user-owned input cannot be spoken as part of the latest ChatGPT assistant response.

The previous topology-probe phase is cancelled. Web code audit has established the production defect at the response-extraction root ownership contract; no additional topology probe is required before v2.

## Canonical evidence

```text
USER_FIX_ACCEPTANCE=FAIL
FAILED_FIX_SOURCE=9c3337ed41722e259d3099cc7b6bd7787f44bf5b
POST_FIX_TRACE_ID=0CEAF62F-7F74-460C-9621-EB8DFD29C250
SELECTED_PATH=fallback
ROOT_ELEMENT=div
BLOCK_COUNT=73
UTTERANCE_COUNT=156
FIRST_FIX_DID_NOT_REJECT_LIVE_FALLBACK=YES
OBSERVED_AFTER_FIX=user_message_then_assistant_response
```

Earlier 8e evidence is historical and not current acceptance.

## Web code-audit finding

Current production flow:

```text
readLatestResponse
→ assistantResponseRoots
→ latestRegenerateOwnedResponse fallback
→ structuredBlocks(root)
→ payload.blocks
→ utteranceRequests(payload.blocks)
→ speech queue / TTS
```

Production flaw:

- fallback can accept a generic ancestor based on Regenerate + response-like content without positive assistant ownership;
- `structuredBlocks` recursively extracts all semantic content beneath that root;
- `SpeechContentBlock` does not carry production author ownership;
- downstream cleaner/router/queue therefore cannot recover author identity after the wrong root is admitted.

```text
ROOT_CAUSE_CONFIRMED=YES
CAUSE_LAYER=CHATGPT_RESPONSE_EXTRACTION_ROOT_OWNERSHIP_CONTRACT
TTS_CAUSAL=NO
SPEECH_QUEUE_CAUSAL=NO
CONTENT_CLEANER_CAUSAL=NO
FIRST_FIX_FAILURE=NEGATIVE_HEURISTICS_WITHOUT_POSITIVE_OWNERSHIP
```

## Baseline

- Repository: `Lost0rz/FloatTabs`
- Worktree identity: `floattabs-main-production`
- Branch: `fix/chatgpt-speech-response-ownership`
- Upstream: `origin/fix/chatgpt-speech-response-ownership`
- Accepted main base: `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- PR #102 is separate and must remain unchanged.

Gate 0: fetch/prune, require clean tree, exact local/upstream HEAD, correct branch/worktree, accepted merge-base, then re-read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`. Any mismatch is STOP.

## Gate 1 — V2 formal RED

Modify tests first. Do not touch production code before observed RED.

Add the smallest fixture that represents the first-fix blind spot:

- no explicit assistant/user author-role markers;
- one semantic Regenerate response action;
- a generic ancestor has only one direct content-bearing child, so the v1 direct-child fan-out guard does not reject it;
- inside that one nested content branch are unrelated predecessor text and intended response text;
- no generic semantic conversation-turn boundary positively owns the Regenerate action.

Required contract:

> A generic ancestor without a positive semantic response-turn ownership boundary must never become the response payload, even when it has one Regenerate action and one direct content-bearing child.

Require first run RED against current production. Confirm the current fallback emits unrelated predecessor content. If first run is not RED, STOP for Web review.

## Gate 2 — Minimal production fix

After verified RED, change only the fallback response-root selection in `FloatTabs/Web/ChatGPTResponseExtraction.swift`.

Production contract:

1. preserve explicit assistant-role selection;
2. preserve role-proven assistant conversation-turn selection;
3. for semantic Regenerate fallback, find the nearest generic semantic conversation-turn container containing that Regenerate action, using stable semantic selectors already present in the codebase (for example a generic `[data-testid*="conversation-turn"]` boundary; do not use generated classes);
4. accept that turn only if rendered, response-bearing, contains exactly one applicable Regenerate response action, and does not carry explicit user/composer/status/alert/live ownership markers;
5. if no qualifying semantic turn exists, fail closed / return no response;
6. do not ascend to arbitrary generic ancestors to manufacture ownership.

Correctness wins over compatibility. If no semantic ownership boundary is available, no speech is better than speaking the user's input.

Do not change `SpeechContentBlock`, `SpeechContentCleaner`, language routing, queue, playback, `SpeechService`, notifications, response text ordering, or unrelated DOM behavior.

## Gate 3 — Focused GREEN

Run at minimum:

- the new v2 RED regression;
- all `ChatGPTResponseExtractionTests`;
- relevant `AssistantSpeechCoordinatorTests`.

Also preserve existing explicit/article response extraction behavior and prove ambiguous generic fallback fails closed.

Do not call the issue fixed from synthetic GREEN alone.

## Gate 4 — Build/install v2 QA

After focused GREEN:

- build fresh exact-head arm64 Debug;
- replace only `/Applications/FloatTabs.app`;
- preserve Browser Profiles, Slots, cookies, WebKit state, authenticated sessions, Application Support, preferences, and diagnostic history;
- verify exact source provenance, version/build, architecture, signature/path, and running PID.

Then STOP. Do not trigger `Read Latest Response` for the user.

## Not authorized

```text
TOPOLOGY_PROBE_AUTHORIZED=NO
SECOND_HEURISTIC_STACKING=NO
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

Stop after exact-head v2 QA installation at:

```text
FINAL_STATE=WAITING_FOR_USER_FIX_V2_ACCEPTANCE
```

Receipt:

```text
TASK_ID:
START_HEAD:
CONTROL_HEAD:
CODE_AUDIT_ACKNOWLEDGED:
V2_RED_TEST:
FIRST_RUN_RED:
RED_ACTUAL_BEHAVIOR:
PRODUCTION_FIX_HEAD:
FALLBACK_POSITIVE_OWNERSHIP_CONTRACT:
AMBIGUOUS_GENERIC_FALLBACK_BEHAVIOR:
FOCUSED_EXTRACTION_TESTS:
FOCUSED_SPEECH_TESTS:
QA_BUILD:
APP_PATH:
INSTALLED_SOURCE_HEAD:
INSTALLED_VERSION_BUILD:
INSTALLED_ARCH:
RUNNING_PID:
USER_DATA_PRESERVED:
TOPOLOGY_PROBE_ADDED:NO
TTS_OR_QUEUE_CHANGED:NO
PR102_UNCHANGED:
REMOTE_SYNC:
WORKTREE_STATUS:
FINAL_STATE=WAITING_FOR_USER_FIX_V2_ACCEPTANCE
```
