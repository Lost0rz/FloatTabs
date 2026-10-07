# FloatTabs Current Task

**Task ID:** FT-SPEECH-001
**Title:** Positive Response Ownership Fix V2
**Status:** `WAITING_FOR_USER_FIX_V2_ACCEPTANCE`
**Mode:** `QA_INSTALLED_WAITING_FOR_HUMAN_ACCEPTANCE`

## Objective

Fix `Read Latest Response` so user-owned input cannot be spoken as part of the latest ChatGPT assistant response.

The cancelled topology-probe commit remains preserved and unchanged in its original checkout. V2 was executed from the exact remote control head in the explicitly user-authorized isolated worktree, then published to the implementation branch by normal fast-forward. The installed V2 QA is now awaiting human acceptance. Do not merge topology instrumentation into V2.

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
- Worktree identity: `ft-speech-001-v2-isolated`
- Branch: `fix/chatgpt-speech-response-ownership`
- Upstream: `origin/fix/chatgpt-speech-response-ownership`
- Isolated execution branch: `codex/ft-speech-001-v2`
- V2 implementation commit: `3e707eb4725bc4549daf991d4d08ffa9f50745b7` (pushed by fast-forward)
- Accepted main base: `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- PR #102 is separate and must remain unchanged.

## Gate 0 — Completed: preserve topology work and create isolated V2 worktree

Known local-only commit:

```text
SUPERSEDED_LOCAL_COMMIT=0a3588bf6e4675d897aa02b336c1349ef090b692
SUPERSEDED_PARENT=777fa7a9390236c14f2ee1a5266818b592eb451c
DISPOSITION=SUPERSEDED_BY_WEB_CODE_AUDIT
```

The original checkout remains clean at the superseded commit. The remote archive tag
is verified to point exactly at that commit. It was not reset, tested for V2,
amended, cherry-picked, merged, rebased, or used as the V2 base.

```text
archive/ft-speech-001-topology-probe-superseded-20261007
ARCHIVE_REMOTE_VERIFIED=YES
ORIGINAL_CHECKOUT_UNCHANGED=YES
```

The isolated V2 worktree started at `1e9b8780a6fd6991ab63eb5f8c34f8994308dd5c`,
with clean status and accepted main merge-base. The original topology checkout was
left untouched.

## Gate 1 — Complete: V2 formal RED

Modify tests first. Do not touch production code before observed RED.

Add the smallest fixture representing the first-fix blind spot:

- no explicit assistant/user author-role markers;
- one semantic Regenerate response action;
- a generic ancestor has only one direct content-bearing child, so the V1 direct-child guard permits it;
- inside that nested branch are unrelated predecessor text and intended response text;
- no generic semantic conversation-turn boundary positively owns the Regenerate action.

Required contract:

> A generic ancestor without a positive semantic response-turn ownership boundary must never become the response payload.

First run was RED. The unchanged fallback admitted the generic ancestor and
emitted both predecessor and intended-response blocks with unknown ownership.

## Gate 2 — Complete: minimal V2 production fix

After verified RED, change only fallback response-root selection in `FloatTabs/Web/ChatGPTResponseExtraction.swift`.

1. preserve explicit assistant-role selection;
2. preserve role-proven assistant conversation-turn selection;
3. Regenerate fallback may use only the nearest generic semantic conversation-turn container containing that action, using stable semantic selectors already present in the codebase;
4. accept it only if rendered, response-bearing, exactly one applicable Regenerate action, and no explicit user/composer/status/alert/live ownership marker;
5. if no qualifying semantic turn exists, fail closed;
6. never ascend to arbitrary generic ancestors to manufacture ownership.

Do not change `SpeechContentBlock`, cleaner, language routing, queue, playback, SpeechService, notifications, or unrelated DOM behavior.

The committed implementation only changes Regenerate fallback root selection in
`FloatTabs/Web/ChatGPTResponseExtraction.swift`: it uses the nearest semantic
conversation-turn boundary and fails closed when none qualifies.

## Gate 3 — Complete: focused GREEN

Run at minimum:

- new V2 regression;
- all `ChatGPTResponseExtractionTests`;
- relevant `AssistantSpeechCoordinatorTests`.

All 141 tests across the extraction and speech-coordinator classes passed with 0
failures. No full suite was run.

Preserve explicit/article behavior and prove ambiguous generic fallback fails closed.

## Gate 4 — Complete: build/install V2 QA

After focused GREEN:

- build fresh exact-head arm64 Debug;
- replace only `/Applications/FloatTabs.app`;
- preserve Browser Profiles, Slots, cookies, WebKit state, authenticated sessions, Application Support, preferences, and diagnostic history;
- verify source provenance, version/build, architecture, signature/path, and running PID;
- stop without triggering `Read Latest Response`.

The installed app reports source `3e707eb4725bc4549daf991d4d08ffa9f50745b7`,
version `0.5.2` build `20`, arm64, at `/Applications/FloatTabs.app`, running PID
`38242`. Profiles/Slots state and preferences were byte-identical to the
pre-install snapshot; all pre-existing WebKit paths and diagnostic-log paths
remained present. No Read Latest Response action was triggered.

After a fresh fetch confirmed the implementation branch was still at
`1e9b8780a6fd6991ab63eb5f8c34f8994308dd5c`, the V2 commit was pushed by normal
fast-forward. No force push, implementation PR, or merge occurred.

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

The only next action is human acceptance of the installed QA build. Do not trigger
speech, send ChatGPT messages, reload/reset, make another fix, rebuild/reinstall,
run the full suite, open an implementation PR, or merge before that acceptance.

Receipt:

```text
TASK_ID=FT-SPEECH-001
START_HEAD=1e9b8780a6fd6991ab63eb5f8c34f8994308dd5c
SUPERSEDED_LOCAL_COMMIT=0a3588bf6e4675d897aa02b336c1349ef090b692
ARCHIVE_TAG=archive/ft-speech-001-topology-probe-superseded-20261007
ARCHIVE_REMOTE_VERIFIED=YES
ISOLATED_WORKTREE_BASE=1e9b8780a6fd6991ab63eb5f8c34f8994308dd5c
CODE_AUDIT_ACKNOWLEDGED=YES
V2_RED_TEST=testRegenerateFallbackFailsClosedWithoutPositiveSemanticConversationTurnOwnership
FIRST_RUN_RED=YES
RED_ACTUAL_BEHAVIOR=fallback emitted predecessor and intended-response blocks with unknown ownership
PRODUCTION_FIX_HEAD=3e707eb4725bc4549daf991d4d08ffa9f50745b7
FALLBACK_POSITIVE_OWNERSHIP_CONTRACT=nearest semantic conversation-turn only; fail closed without one
AMBIGUOUS_GENERIC_FALLBACK_BEHAVIOR=no response
FOCUSED_EXTRACTION_TESTS=43 PASS
FOCUSED_SPEECH_TESTS=PASS in combined 141-test run
QA_BUILD=arm64 Debug PASS
APP_PATH=/Applications/FloatTabs.app
INSTALLED_SOURCE_HEAD=3e707eb4725bc4549daf991d4d08ffa9f50745b7
INSTALLED_VERSION_BUILD=0.5.2 (20)
INSTALLED_ARCH=arm64
RUNNING_PID=38242
USER_DATA_PRESERVED=YES
TOPOLOGY_COMMIT_MERGED:NO
TTS_OR_QUEUE_CHANGED:NO
PR102_UNCHANGED=YES
REMOTE_SYNC=PASS; normal fast-forward push completed
WORKTREE_STATUS=CLEAN
FINAL_STATE=WAITING_FOR_USER_FIX_V2_ACCEPTANCE
```
