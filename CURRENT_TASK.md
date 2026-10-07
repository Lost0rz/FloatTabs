# FloatTabs Current Task

**Task ID:** FT-SPEECH-001
**Title:** Final Regression and Independent Web Audit
**Status:** `ACTIVE — FINAL_REGRESSION_AND_INDEPENDENT_WEB_AUDIT`
**Mode:** `VALIDATION_ONLY_NO_PRODUCT_CHANGE`

## Objective

Close the already human-accepted `Read Latest Response` fix with final regression evidence and an independent Web merge audit. Do not redesign or modify the accepted V4 product behavior.

## Accepted product result

```text
V4_PRODUCT_HEAD=6b5fb9a780073a26f8060e5be8baee284d511339
V4_HUMAN_ACCEPTANCE=PASS
OBSERVED=only latest ChatGPT response was spoken
USER_PROMPT_SPOKEN=NO
NO_SPEECH_REGRESSION=NO
```

Focused validation already accepted:

```text
ChatGPTResponseExtractionTests=47/47 PASS
AssistantSpeechCoordinatorTests=98/98 PASS
QA_BUILD=PASS arm64 Debug
INSTALLED_SOURCE=6b5fb9a780073a26f8060e5be8baee284d511339
USER_DATA_PRESERVED=YES
```

## Authority and role split

- Web has completed the causal/code audit and owns the final independent merge audit.
- Local does **not** perform another root-cause investigation or production modification.
- Local only runs the exact final regression gate and returns evidence.

## Gate 0 — exact validation baseline

1. fresh `git fetch origin --prune`;
2. require branch `fix/chatgpt-speech-response-ownership` (or the already-authorized execution worktree tracking this branch);
3. require clean working tree;
4. require local HEAD equals freshly fetched upstream after control-plane sync;
5. re-read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`;
6. verify accepted product commit `6b5fb9a780073a26f8060e5be8baee284d511339` is an ancestor of current HEAD and no product/test file changed after that commit except authorized control-plane files.

STOP only on an actual mismatch, dirty state, network inability to establish required remote freshness, or unexpected product change.

## Gate 1 — full final regression

Run the repository's normal complete automated test suite appropriate for the current macOS/Swift project, including the same build/test configuration used for merge qualification.

Requirements:

```text
FULL_FINAL_SUITE=PASS
PRODUCT_HEAD_UNCHANGED=6b5fb9a780073a26f8060e5be8baee284d511339
NO_PRODUCT_OR_TEST_CHANGES_DURING_VALIDATION=YES
```

If the full suite fails, do not repair locally. Return the exact failing test/build evidence to Web for audit.

## Gate 2 — final state evidence

After tests:

- working tree clean;
- no new production/test commit;
- PR #102 unchanged;
- report exact local and remote HEADs;
- report test command(s), passed/failed counts, and any skipped tests.

Do not rebuild/reinstall the QA app unless required solely by the repository's normal full validation command. Do not trigger `Read Latest Response` again.

## Web independent audit

Web will independently verify after the local regression receipt:

1. diff from accepted main base to the implementation branch;
2. changed-file scope;
3. V4 ownership implementation against the frozen contract;
4. preservation of legacy paths and fail-closed behavior;
5. absence of unrelated PR #102 changes;
6. full-suite evidence and branch freshness.

Local does not duplicate this audit.

## Not authorized

```text
PRODUCT_CHANGE=NO
TEST_CHANGE=NO
NEW_DIAGNOSTICS=NO
ROOT_CAUSE_REOPEN=NO
TOPOLOGY_PROBE=NO
PR102_CHANGE=NO
IMPLEMENTATION_PR_CREATE=NO
MERGE=NO
RELEASE=NO
```

## Acceptance

If the full suite passes, stop at:

```text
FINAL_STATE=WAITING_FOR_INDEPENDENT_WEB_FINAL_AUDIT
```

Receipt:

```text
TASK_ID: FT-SPEECH-001
START_HEAD:
REMOTE_HEAD_AFTER_FETCH:
BASELINE_GATE:
V4_PRODUCT_HEAD_ANCESTOR:
POST_V4_PRODUCT_PATH_CHANGES:
FULL_FINAL_SUITE_COMMAND:
FULL_FINAL_SUITE_RESULT:
FULL_FINAL_SUITE_COUNTS:
SKIPPED_TESTS:
PRODUCT_HEAD_UNCHANGED:
PR102_UNCHANGED:
LOCAL_FINAL_HEAD:
REMOTE_FINAL_HEAD:
LOCAL_REMOTE_MATCH:
WORKTREE_STATUS:
FINAL_STATE=WAITING_FOR_INDEPENDENT_WEB_FINAL_AUDIT
```
