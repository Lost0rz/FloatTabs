# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual refs. Refresh before local execution. Machine-specific paths remain local-only.

## Mode

**MODE: ACTIVE — POSITIVE_RESPONSE_OWNERSHIP_FIX_V2**

## Production authority

- Worktree identity: `floattabs-main-production`
- Implementation branch: `fix/chatgpt-speech-response-ownership`
- Expected upstream: `origin/fix/chatgpt-speech-response-ownership`
- Accepted implementation base: `main` at `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- Control PR #114: merged
- PR #102: separate MemoX work; excluded and unchanged

## Canonical failed-fix evidence

```text
USER_FIX_ACCEPTANCE=FAIL
FAILED_FIX_SOURCE=9c3337ed41722e259d3099cc7b6bd7787f44bf5b
OBSERVED_AFTER_FIX=user_message_then_assistant_response
POST_FIX_TRACE_ID=0CEAF62F-7F74-460C-9621-EB8DFD29C250
SELECTED_PATH=fallback
ROOT_ELEMENT=div
BLOCK_COUNT=73
UTTERANCE_COUNT=156
FIRST_FIX_DID_NOT_REJECT_LIVE_FALLBACK=YES
```

## Web code-audit verdict

```text
ROOT_CAUSE_CONFIRMED=YES
CAUSE_LAYER=CHATGPT_RESPONSE_EXTRACTION_ROOT_OWNERSHIP_CONTRACT
TTS_CAUSAL=NO
SPEECH_QUEUE_CAUSAL=NO
CONTENT_CLEANER_CAUSAL=NO
FIRST_FIX_FAILURE=NEGATIVE_HEURISTICS_WITHOUT_POSITIVE_OWNERSHIP
```

The production path is:

```text
Read Latest Response
→ assistantResponseRoots()
→ latestRegenerateOwnedResponse() fallback
→ structuredBlocks(root)
→ payload.blocks
→ utteranceRequests(payload.blocks)
→ speech queue / TTS
```

The fallback can admit a generic ancestor without positive response ownership. `structuredBlocks` then recursively extracts all semantic content below it. Production blocks do not retain author identity, so downstream speech code cannot recover ownership after a broad root is accepted.

## Correct V2 contract

- Preserve explicit assistant-role roots.
- Preserve role-proven assistant conversation-turn roots.
- Regenerate fallback may use only the nearest qualifying semantic conversation-turn boundary containing that action.
- The turn must be rendered, response-bearing, contain exactly one applicable Regenerate action, and contain no explicit user/composer/status/alert/live ownership marker.
- If no qualifying semantic turn exists, fail closed.
- Never manufacture response ownership by ascending to an arbitrary generic ancestor.

## Superseded local topology commit disposition

A local-only commit was created from the now-cancelled topology-probe scope:

```text
LOCAL_SUPERSEDED_COMMIT=0a3588bf6e4675d897aa02b336c1349ef090b692
LOCAL_SUPERSEDED_PARENT=777fa7a9390236c14f2ee1a5266818b592eb451c
LIFECYCLE=SUPERSEDED_BY_WEB_CODE_AUDIT
PRODUCT_BEHAVIOR_CHANGE=NO
VALIDATION=NOT_FINAL; 73 focused tests passed before the final probe simplification, but this exact commit was not rerun
```

This commit must **not** be merged, cherry-picked, rebased into, or used as the base for V2. Because it is unique local work, preserve it first with a recoverable archive tag, then realign the implementation branch exactly to the current remote V2 control HEAD. After archive verification it is historical evidence only.

Authorized disposition:

```text
ARCHIVE_TAG=archive/ft-speech-001-topology-probe-superseded-20261007
ARCHIVE_TARGET=0a3588bf6e4675d897aa02b336c1349ef090b692
ARCHIVE_PUSH_AUTHORIZED=YES
BRANCH_REALIGN_TO_REMOTE_AFTER_ARCHIVE=YES
FORCE_PUSH_IMPLEMENTATION_BRANCH=NO
CHERRY_PICK_TOPOLOGY_COMMIT=NO
```

## Current authorization

The topology-probe plan is cancelled.

Authorized now:

1. preserve/archive the superseded local topology commit;
2. realign the implementation checkout to the exact remote V2 control HEAD;
3. perform formal V2 RED;
4. make the minimal fallback root-selection fix only after observed RED;
5. run focused extraction + speech tests;
6. build/install exact-head arm64 Debug QA at `/Applications/FloatTabs.app` preserving user data;
7. stop for human acceptance.

Not authorized:

```text
TOPOLOGY_PROBE_AUTHORIZED=NO
TTS_CHANGE_AUTHORIZED=NO
SPEECH_QUEUE_CHANGE_AUTHORIZED=NO
CONTENT_CLEANER_CHANGE_AUTHORIZED=NO
BROAD_DOM_REDESIGN_AUTHORIZED=NO
IMPLEMENTATION_PR_AUTHORIZED=NO
MERGE_AUTHORIZED=NO
FULL_FINAL_SUITE_AUTHORIZED=NO
```

## Required next state

After archive + branch reconciliation, execute `CURRENT_TASK.md`. After V2 focused GREEN and verified QA installation, stop at:

```text
FINAL_STATE=WAITING_FOR_USER_FIX_V2_ACCEPTANCE
```
