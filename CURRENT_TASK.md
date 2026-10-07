# FloatTabs Current Task

**Task ID:** FT-SPEECH-001
**Title:** Positive Response Ownership Fix V2
**Status:** `ACTIVE — POSITIVE_RESPONSE_OWNERSHIP_FIX_V2`
**Mode:** `TEST_FIRST_MINIMAL_PRODUCTION_FIX`

## Objective

Fix `Read Latest Response` so user-owned input cannot be spoken as part of the latest ChatGPT assistant response.

The cancelled topology-probe phase produced one unique local commit. Preserve it as historical evidence, realign to the current remote V2 control state, then continue the test-first V2 fix. Do not merge topology instrumentation into V2.

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

## Root-cause contract

```text
ROOT_CAUSE_CONFIRMED=YES
CAUSE_LAYER=CHATGPT_RESPONSE_EXTRACTION_ROOT_OWNERSHIP_CONTRACT
TTS_CAUSAL=NO
SPEECH_QUEUE_CAUSAL=NO
CONTENT_CLEANER_CAUSAL=NO
```

Fallback must use positive semantic response ownership, not arbitrary ancestor heuristics.

## Baseline

- Repository: `Lost0rz/FloatTabs`
- Worktree identity: `floattabs-main-production`
- Branch: `fix/chatgpt-speech-response-ownership`
- Upstream: `origin/fix/chatgpt-speech-response-ownership`
- Accepted main base: `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- PR #102 is separate and must remain unchanged.

## Gate 0A — Preserve superseded local topology work

Known local-only commit:

```text
SUPERSEDED_LOCAL_COMMIT=0a3588bf6e4675d897aa02b336c1349ef090b692
SUPERSEDED_PARENT=777fa7a9390236c14f2ee1a5266818b592eb451c
DISPOSITION=SUPERSEDED_BY_WEB_CODE_AUDIT
```

Do not test, amend, cherry-pick, merge, or continue this commit.

First verify the local commit still exists and is the current divergent local HEAD. If it differs, STOP.

Create and verify a recoverable archive tag:

```text
archive/ft-speech-001-topology-probe-superseded-20261007
```

pointing exactly to `0a3588bf6e4675d897aa02b336c1349ef090b692`, then push only that tag to origin. Verify the remote tag resolves to the exact commit. Do not push the implementation branch while it points to the superseded commit.

## Gate 0B — Realign implementation branch

After archive verification:

1. `git fetch origin --prune`
2. verify the implementation worktree is clean;
3. move the local implementation branch to the exact freshly fetched `origin/fix/chatgpt-speech-response-ownership` state;
4. this destructive branch realignment is explicitly authorized **only because** the unique local commit was preserved and verified by the archive tag;
5. do not force-push the implementation branch;
6. require local HEAD == upstream and clean tree;
7. re-read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md` after realignment.

If the remote branch advances again after fetch, STOP rather than guessing.

## Gate 1 — V2 formal RED

Modify tests first. Do not touch production code before observed RED.

Add the smallest fixture representing the first-fix blind spot:

- no explicit assistant/user author-role markers;
- one semantic Regenerate response action;
- a generic ancestor has only one direct content-bearing child, so the V1 direct-child guard permits it;
- inside that nested branch are unrelated predecessor text and intended response text;
- no generic semantic conversation-turn boundary positively owns the Regenerate action.

Required contract:

> A generic ancestor without a positive semantic response-turn ownership boundary must never become the response payload.

Require first run RED and confirm the current fallback emits unrelated predecessor content. If not RED, STOP for Web review.

## Gate 2 — Minimal V2 production fix

After verified RED, change only fallback response-root selection in `FloatTabs/Web/ChatGPTResponseExtraction.swift`.

1. preserve explicit assistant-role selection;
2. preserve role-proven assistant conversation-turn selection;
3. Regenerate fallback may use only the nearest generic semantic conversation-turn container containing that action, using stable semantic selectors already present in the codebase;
4. accept it only if rendered, response-bearing, exactly one applicable Regenerate action, and no explicit user/composer/status/alert/live ownership marker;
5. if no qualifying semantic turn exists, fail closed;
6. never ascend to arbitrary generic ancestors to manufacture ownership.

Do not change `SpeechContentBlock`, cleaner, language routing, queue, playback, SpeechService, notifications, or unrelated DOM behavior.

## Gate 3 — Focused GREEN

Run at minimum:

- new V2 regression;
- all `ChatGPTResponseExtractionTests`;
- relevant `AssistantSpeechCoordinatorTests`.

Preserve explicit/article behavior and prove ambiguous generic fallback fails closed.

## Gate 4 — Build/install V2 QA

After focused GREEN:

- build fresh exact-head arm64 Debug;
- replace only `/Applications/FloatTabs.app`;
- preserve Browser Profiles, Slots, cookies, WebKit state, authenticated sessions, Application Support, preferences, and diagnostic history;
- verify source provenance, version/build, architecture, signature/path, and running PID;
- stop without triggering `Read Latest Response`.

## Not authorized

```text
TOPOLOGY_PROBE_AUTHORIZED=NO
TOPOLOGY_COMMIT_IN_V2=NO
TTS_CHANGE_AUTHORIZED=NO
SPEECH_QUEUE_CHANGE_AUTHORIZED=NO
CONTENT_CLEANER_CHANGE_AUTHORIZED=NO
BROAD_DOM_REDESIGN_AUTHORIZED=NO
PR102_CHANGE_AUTHORIZED=NO
IMPLEMENTATION_PR_AUTHORIZED=NO
MERGE_AUTHORIZED=NO
FULL_FINAL_SUITE_AUTHORIZED=NO
FORCE_PUSH_IMPLEMENTATION_BRANCH=NO
```

## Acceptance

```text
FINAL_STATE=WAITING_FOR_USER_FIX_V2_ACCEPTANCE
```

Receipt:

```text
TASK_ID:
START_HEAD:
SUPERSEDED_LOCAL_COMMIT:
ARCHIVE_TAG:
ARCHIVE_REMOTE_VERIFIED:
REALIGNED_CONTROL_HEAD:
LOCAL_REMOTE_MATCH_AFTER_REALIGN:
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
TOPOLOGY_COMMIT_MERGED:NO
TTS_OR_QUEUE_CHANGED:NO
PR102_UNCHANGED:
REMOTE_SYNC:
WORKTREE_STATUS:
FINAL_STATE=WAITING_FOR_USER_FIX_V2_ACCEPTANCE
```
