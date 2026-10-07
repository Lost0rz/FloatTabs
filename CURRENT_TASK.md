# FloatTabs Current Task

**Task ID:** FT-SPEECH-001
**Title:** Implementation PR and Merge Gate
**Status:** `READY_FOR_IMPLEMENTATION_PR_AND_MERGE_GATE`
**Mode:** `PR_CREATION_AND_EXACT_HEAD_CI_GATE`

## Objective

Create the implementation PR for the already human-accepted and independently audited `Read Latest Response` fix, then use GitHub's required exact-head CI as the final merge gate. Do not modify the accepted product behavior.

## Accepted implementation

```text
V4_PRODUCT_HEAD=6b5fb9a780073a26f8060e5be8baee284d511339
FINAL_TEST_CORRECTIVE=69037473ed0b2c4cb7905ecdfbfdb320d320389c
V4_HUMAN_ACCEPTANCE=PASS
FULL_FINAL_SUITE=PASS
INDEPENDENT_WEB_FINAL_AUDIT=PASS
```

Final suite:

```text
1300 passed
0 failed
2 skipped
1302 total
```

## Repository authority

- Base branch: `main`
- Live/accepted main: `2d2b733407ea57ea66ca380887dfc11b71b6e2be`
- Head branch: `fix/chatgpt-speech-response-ownership`
- PR #102 is unrelated MemoX Draft work and must remain unchanged
- Required branch-protection check: `Build & Test (Apple Silicon arm64)`

## Gate 0 — freshness

Before creating the PR:

1. fresh remote ref check;
2. require `main` still equals `2d2b733407ea57ea66ca380887dfc11b71b6e2be`, or STOP for Web reconciliation if it advanced;
3. require implementation branch head equals the freshly fetched remote head and contains the accepted V4 product commit plus the final test corrective;
4. require no unexpected product/test change after `69037473ed0b2c4cb7905ecdfbfdb320d320389c`; control-plane-only advances are allowed when authorized by Web.

## Gate 1 — implementation PR

Create one PR:

```text
base=main
head=fix/chatgpt-speech-response-ownership
```

The PR description should state:

- user-visible defect: `Read Latest Response` could admit the user's prompt;
- root cause: response-root ownership in `ChatGPTResponseExtraction`;
- final behavior: only latest positively assistant-owned response is spoken;
- human acceptance: PASS;
- final local suite: 1300 pass / 0 fail / 2 skipped;
- independent Web final audit: PASS;
- PR #102 excluded and unchanged.

Do not combine unrelated work into this PR.

## Gate 2 — exact-head CI

After PR creation, wait for GitHub's required PR check:

```text
Build & Test (Apple Silicon arm64)
```

Required before merge recommendation:

```text
PR_HEAD_UNCHANGED=YES
REQUIRED_CI=PASS
MERGEABLE=YES
MERGE_STATE=CLEAN
```

A local full-suite pass does not replace the required GitHub PR check.

If CI fails, do not modify product code automatically. Return the exact failure to Web for audit.

## Gate 3 — merge authorization boundary

Creating the PR is authorized. Merging is **not yet automatic** from this task file alone.

After the exact PR head has the required GitHub check PASS and GitHub reports the PR mergeable/clean, return the PR number, exact head, CI result, changed-file count, and merge state to Web. Web will issue the final merge authorization or STOP if anything changed.

## Not authorized

```text
PRODUCT_CHANGE=NO
NEW_TEST_CHANGE=NO
NEW_DIAGNOSTICS=NO
ROOT_CAUSE_REOPEN=NO
TOPOLOGY_PROBE=NO
PR102_CHANGE=NO
DIRECT_PUSH_TO_MAIN=NO
DIRECT_MERGE_WITHOUT_FINAL_WEB_AUTHORIZATION=NO
RELEASE=NO
```

## Acceptance

Stop after PR creation + exact-head required CI resolution at:

```text
FINAL_STATE=WAITING_FOR_FINAL_WEB_MERGE_AUTHORIZATION
```

Receipt:

```text
TASK_ID: FT-SPEECH-001
START_HEAD:
LIVE_MAIN:
PR_NUMBER:
PR_HEAD:
PR_BASE:
PR_DRAFT:
CHANGED_FILES:
REQUIRED_CI:
MERGEABLE:
MERGE_STATE:
PR102_UNCHANGED:
FINAL_STATE=WAITING_FOR_FINAL_WEB_MERGE_AUTHORIZATION
```
