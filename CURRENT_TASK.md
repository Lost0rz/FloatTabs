# FloatTabs Current Task

**Task ID:** FT-LIFECYCLE-001
**Title:** Warm Memory-Warning Residency Corrective
**Status:** `WAITING_FOR_INDEPENDENT_WEB_AUDIT`
**Mode:** `READ_ONLY_INDEPENDENT_REVIEW`

## Completed objective

Correct the confirmed Warm QA failure without reopening unrelated lifecycle areas.

The authorized implementation started from task-branch head
`fd987fbd193adf148c91513fce40134c701ba3c9`. Review the implementation as the
current task-branch diff from that base. Git refs are authoritative for the final
branch head; do not infer it from this file.

## Accepted product contract

```text
ordinary inactivity            -> configured Warm TTL applies
memory pressure warning        -> diagnostic only; no early Warm release
memory pressure critical       -> may release eligible inactive Warm runtimes
```

Media, attention, and speech protections remain in force. Hot recovery and Cold
semantics remain unchanged. Unread/red-dot behavior remains outside this task.

## Implementation and validation evidence

- Warning RED was proven before the production change: with three inactive,
  eligible Warm runtimes and a 600-second TTL, warning pressure left one plan and
  released two runtimes; the new assertions failed for those releases.
- The warning path still records `slot_lifecycle.memory_pressure` and no longer
  invokes Warm eviction. Critical pressure releases eligible inactive Warm
  runtimes while respecting media, attention, and speech protections.
- The obsolete `warmMemoryPressureTarget` and Warm-recency state were removed;
  critical pressure now releases every eligible Warm runtime, so LRU ordering no
  longer affects the policy.
- Focused checks passed: warning preservation, critical eviction, protected Warm
  preservation, three Warm runtimes before TTL, Hot policy and termination
  recovery, and Cold grace release.
- Full XCTest: **1303 passed, 3 skipped, 0 failed**.
- Debug arm64 build: **PASS**.
- Release build: **PASS**; executable architecture verified as **arm64**.
- No QA reinstall was performed.

## Changed task files

- `FloatTabs/Web/SlotLifecycleCoordinator.swift`
- `FloatTabsTests/WebAttentionLifecycleTests.swift`
- `FloatTabsTests/WebAttentionCrossFeatureTests.swift`
- `FloatTabsTests/WebViewPoolTests.swift`
- `FloatTabs/UI/GlobalSettingsController.swift`
- `README.md`
- `docs/product/FloatTabs_Stage_5_Residency_Policy.md`
- `docs/product/FloatTabs_Stage_5E_Resource_Lifecycle.md`
- `CURRENT_STATUS.md`
- `CURRENT_TASK.md`

## Review and stop boundary

Independent Web audit only. Do not reinstall QA, merge PR #116, push main, release,
or change unread/red-dot behavior, speech, Cold semantics, attention authority, or
PR #102.

After the review handoff, stop at:

`FINAL_STATE=WAITING_FOR_INDEPENDENT_WEB_AUDIT`

## Required receipt

```yaml
TASK_ID: FT-LIFECYCLE-001
START_HEAD: fd987fbd193adf148c91513fce40134c701ba3c9
FINAL_HEAD: <current task branch HEAD>
REMOTE_HEAD: <live task branch HEAD>
LOCAL_REMOTE_MATCH: <YES/NO>
WARNING_RED_PROVEN: YES
WARNING_PRESERVES_WARM: YES
CRITICAL_EVICTION_PRESERVED: YES
PROTECTION_BEHAVIOR_PRESERVED: YES
WARM_GT_2_PRE_TTL: YES
HOT_REGRESSION: PASS
COLD_REGRESSION: PASS
FOCUSED_TESTS: PASS
FULL_TEST_SUITE: 1303 passed, 3 skipped, 0 failed
DEBUG_BUILD: PASS
RELEASE_BUILD: PASS
RELEASE_ARCH: arm64
CHANGED_FILES: <see changed task files above>
PR102_UNCHANGED: YES
WORKING_TREE: <CLEAN/dirty>
FINAL_STATE: WAITING_FOR_INDEPENDENT_WEB_AUDIT
```
