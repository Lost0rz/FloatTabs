# FloatTabs Current Task

**Task ID:** FT-SPEECH-001
**Title:** Stale Test Contract Corrective and Final Regression
**Status:** `ACTIVE — STALE_TEST_CONTRACT_CORRECTIVE`
**Mode:** `TEST_ONLY_CORRECTIVE_NO_PRODUCT_CHANGE`

## Objective

Correct one stale source-contract assertion exposed by the full final suite, then rerun the exact final regression. Do not modify the already human-accepted V4 product behavior.

## Accepted product result

```text
V4_PRODUCT_HEAD=6b5fb9a780073a26f8060e5be8baee284d511339
V4_HUMAN_ACCEPTANCE=PASS
OBSERVED=only latest ChatGPT response was spoken
USER_PROMPT_SPOKEN=NO
```

## Web audit verdict on full-suite failure

The only failing test was:

```text
ChatGPTResponseBridgeTests/testTrustedAssistantPointerProtocolUsesFixedContentFreeContract()
FloatTabsTests/ChatGPTResponseBridgeTests.swift:735
XCTAssertTrue(source.contains("article[data-testid*=\"conversation-turn\"]"))
```

Web independently inspected the test and production source.

Verdict:

```text
FULL_SUITE_FAILURE_CLASS=STALE_TEST_EXPECTATION
PRODUCT_REGRESSION=NO
V4_PRODUCT_FIX_REOPEN=NO
```

The `<article>` requirement is obsolete. V3 intentionally made semantic-turn matching tag-agnostic, and V4 added positive assistant ownership for current renderer content units. The test's actual contract is that trusted assistant pointer ownership is semantic and content-free, not that ChatGPT uses an `article` element.

## Gate 0 — exact baseline

1. fresh `git fetch origin --prune`;
2. sync the already-authorized execution worktree to the current upstream by normal fast-forward only;
3. require clean worktree and exact local/upstream HEAD;
4. re-read `AGENTS.md`, `CURRENT_STATUS.md`, `CURRENT_TASK.md`;
5. verify accepted V4 product commit `6b5fb9a780073a26f8060e5be8baee284d511339` remains an ancestor;
6. verify no production path changed after V4 except control-plane files.

## Gate 1 — exact test-only corrective

Modify only:

```text
FloatTabsTests/ChatGPTResponseBridgeTests.swift
```

Inside `testTrustedAssistantPointerProtocolUsesFixedContentFreeContract()`, replace only the obsolete assertion:

```swift
XCTAssertTrue(source.contains("article[data-testid*=\"conversation-turn\"]"))
```

with semantic assertions equivalent to:

```swift
XCTAssertTrue(source.contains("[data-testid*=\"conversation-turn\"]"))
XCTAssertTrue(source.contains("[data-turn=\"assistant\"]"))
XCTAssertTrue(source.contains("[data-content-search-unit-key]"))
XCTAssertTrue(source.contains("[data-conversation-role=\"assistant\"]"))
XCTAssertFalse(source.contains("article[data-testid*=\"conversation-turn\"]"))
```

Preserve these existing negative assertions unchanged:

```text
buttonText
ariaLabel
responseContent
domPath
clipboard
selectionText
```

Do not change production code or any other test unless this exact edit fails to compile. If it does, return the compiler evidence to Web instead of widening scope.

## Gate 2 — focused confirmation

Run only the corrected failing test first.

Required:

```text
FOCUSED_STALE_TEST_CORRECTIVE=PASS
PRODUCT_CODE_CHANGED=NO
```

If it fails, STOP and return evidence. Do not repair beyond the authorized assertion correction.

## Gate 3 — full final regression

Rerun the same full command used in the failed run:

```text
xcodebuild -project FloatTabs.xcodeproj -scheme FloatTabs
-configuration Debug -destination 'platform=macOS,arch=arm64'
-derivedDataPath /private/tmp/ft-speech-001-final-derived-data
-clonedSourcePackagesDirPath /private/tmp/ft-speech-001-v4-source-packages
-resultBundlePath <fresh result bundle path>
CODE_SIGNING_ALLOWED=NO test
```

Requirements:

```text
FULL_FINAL_SUITE=PASS
V4_PRODUCT_HEAD_UNCHANGED=6b5fb9a780073a26f8060e5be8baee284d511339
ONLY_AUTHORIZED_TEST_CORRECTIVE_AFTER_V4=YES
```

Do not rebuild/reinstall the QA app solely for this test correction. Do not trigger `Read Latest Response` again.

## Gate 4 — publish test corrective and stop

If focused + full suite pass:

- commit only the authorized test change;
- normal fast-forward push;
- working tree clean;
- PR #102 unchanged;
- report exact local/remote HEAD and suite counts.

Do not create a PR or merge.

## Not authorized

```text
PRODUCT_CHANGE=NO
OTHER_TEST_CHANGE=NO
NEW_DIAGNOSTICS=NO
ROOT_CAUSE_REOPEN=NO
TOPOLOGY_PROBE=NO
PR102_CHANGE=NO
IMPLEMENTATION_PR_CREATE=NO
MERGE=NO
RELEASE=NO
```

## Acceptance

If focused and full regression pass, stop at:

```text
FINAL_STATE=WAITING_FOR_INDEPENDENT_WEB_FINAL_AUDIT
```

Receipt:

```text
TASK_ID: FT-SPEECH-001
START_HEAD:
REMOTE_HEAD_AFTER_FETCH:
BASELINE_GATE:
STALE_ASSERTION_REMOVED:
SEMANTIC_CONTRACT_ASSERTIONS_ADDED:
FOCUSED_STALE_TEST_RESULT:
FULL_FINAL_SUITE_RESULT:
FULL_FINAL_SUITE_COUNTS:
SKIPPED_TESTS:
V4_PRODUCT_HEAD_UNCHANGED:
AUTHORIZED_TEST_ONLY_CHANGE:
PR102_UNCHANGED:
LOCAL_FINAL_HEAD:
REMOTE_FINAL_HEAD:
LOCAL_REMOTE_MATCH:
WORKTREE_STATUS:
FINAL_STATE=WAITING_FOR_INDEPENDENT_WEB_FINAL_AUDIT
```
