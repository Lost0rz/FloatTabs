# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Card ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001-WP2-001`  
**Title:** WP2 closeout — field observation with existing Runtime Diagnostics  
**Status:** **ACTIVE / FIELD OBSERVATION**  
**Mode:** `OBSERVE / PACKAGE QA FIELD BUILD / NO PRODUCT MUTATION / NO MERGE OR RELEASE`  
**Task class:** `WEB RUNTIME / FIELD OBSERVATION / WP2 CLOSEOUT`  
**Baseline:** `origin/main@2a52800f770266f7c901eb612a0b319ddca142df`  
**Branch:** `codex/adaptive-lifecycle-wp2-policy`  
**PR:** `#195 OPEN / DRAFT / UNMERGED`

## Decision

The user has completed short-run manual use without finding a visible WP2 defect and explicitly chose normal daily use plus background diagnostics instead of a blocking long-duration manual test session.

The previous pre-observation Runtime Diagnostics coverage audit is deferred. Existing diagnostics are sufficient to begin field observation now. Any future instrumentation must be justified by an actual evidence gap found in uploaded logs.

## Current authorization

Authorized now:

1. package the current PR product state as a QA/field-observation DMG;
2. install/use that build as the user's normal FloatTabs application;
3. enable existing Runtime Diagnostics and long-term observation;
4. collect logs during ordinary use;
5. export and remotely audit JSONL after a representative observation window or immediately after a visible anomaly.

No production source mutation is authorized during observation by default.

## Observation settings

Use:

```text
Runtime Diagnostics = Verbose
Keep local diagnostic history = ON
Long-term performance observation = ON
```

Existing long-term observation runs on the production diagnostics scheduler; no separate manual timer/test loop is required.

## Observation procedure

Normal use is the test surface. The user should continue ordinary Slot switching, hide/show, Automatic/Keep Loaded use, ChatGPT generation, media/fullscreen and long idle naturally rather than staging a dedicated manual test session.

If no visible issue occurs, export Recent Diagnostics within the default 7-day retention window after representative daily use.

If an anomaly occurs, before manual reload/restart where practical:

- note approximate time;
- note Slot and Runtime Retention mode;
- export Recent Diagnostics;
- record whether reload/restart later changes the symptom.

Reload/restart recovery remains evidence of a recovery boundary only, not root-cause proof.

## Current evidence already closed

```text
CI_TEST_BOUNDARY=COMPLETE
DRAFT_ENGINEERING_FAST_GATE=PASS
CONTROL_ONLY_SCOPE_GATE=PASS
FINAL_FULL_GATE_AVAILABLE=YES
CANONICAL_TEST_COVERAGE_REDUCED=NO
CURRENT_REQUIRED_TESTS_REMOVED=NONE
HUMAN_INITIAL_SMOKE=PASS_NO_VISIBLE_ISSUE
```

## Package boundary

A QA/field-observation DMG may be built from the current PR branch/head. The product source after the machine-verified WP2 implementation has not been changed by the subsequent CI/control commits; those later commits change workflow/control state only.

The field DMG is for normal user observation before merge. It is not the final GitHub release artifact.

## Not authorized during field observation

- lifecycle-policy mutation;
- WebViewPool/runtime ownership changes;
- Browser Profile/session/cookie/site-data clearing;
- diagnostics source changes without a concrete uploaded-log evidence gap;
- timeout/retry/reset workaround;
- unsupported private WebKit SPI;
- WP3/WP4;
- merge;
- final release.

## Next decision boundary

When the user uploads a diagnostics JSONL sample:

1. audit actual lifecycle/runtime/navigation/recovery evidence remotely;
2. if logs are sufficient and show no blocking WP2 regression, proceed toward final full gate and merge closeout;
3. if a product defect is visible, reconcile a bounded corrective;
4. if the only blocker is missing evidence, authorize only the minimum diagnostics augmentation needed for that concrete question.

## Merge / release gate

```text
PR_195=OPEN_DRAFT_UNMERGED
FIELD_OBSERVATION=ACTIVE
LOG_SAMPLE_REVIEW=PENDING
MERGE_READY=NO
RELEASE_READY=NO
WP3=NOT_STARTED
WP4=NOT_STARTED
```

## Return contract after observation

```text
OBSERVATION_BUILD =
OBSERVATION_WINDOW =
VISIBLE_ISSUES =
DIAGNOSTICS_FILE =
RELOAD_REQUIRED = YES|NO|NOT_APPLICABLE
RESTART_REQUIRED = YES|NO|NOT_APPLICABLE
FIELD_OBSERVATION_RESULT = NO_BLOCKING_ISSUE | ISSUE_OBSERVED
```
