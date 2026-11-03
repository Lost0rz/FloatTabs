# FloatTabs Current Status

**Status date:** 2026-11-03  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: ADAPTIVE LIFECYCLE — WP2 FIELD OBSERVATION / NORMAL DAILY USE**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001 / WP2-001` — **ACTIVE / FIELD OBSERVATION**.

Branch: `codex/adaptive-lifecycle-wp2-policy`  
Draft PR: `#195`  
Baseline: `main@2a52800f770266f7c901eb612a0b319ddca142df`  
Machine-verified WP2 implementation head: `1f33637b215cf742e20f5a8012818ac14ad459c9`  
CI/test-boundary corrective: `6c6665a7c1c91d72a103d297379fbfd54d6443b1`  
Last verified control-only head before field-observation transition: `0a28939d64deb995d555d1d1c399421f8f422788`

## Verified state

```text
WP1=COMPLETE / HUMAN_ACCEPTED
WP2_STAGED_AUTOMATIC_POLICY=IMPLEMENTED
WP2_CORRECTIVE_A/B/C=PASS
AFFECTED_LIFECYCLE_WP1_REGRESSIONS=PASS
TEST_RUNNER_PROCESS_ISOLATION=SUPPORTED_AND_IMPLEMENTED
CANONICAL_INVENTORY_COVERAGE=PASS
CI_TEST_BOUNDARY=COMPLETE
DRAFT_FAST_GATE=VERIFIED
CONTROL_ONLY_SCOPE_GATE=VERIFIED
CURRENT_REQUIRED_TESTS_REMOVED=NONE
HUMAN_INITIAL_SMOKE=PASS_NO_VISIBLE_ISSUE
PR_195=OPEN_DRAFT_UNMERGED
WP3=NOT_STARTED
WP4=NOT_STARTED
```

The installed WP2 QA build has shown no visible defect in ordinary short-run use. The user has chosen to stop treating long-duration lifecycle verification as a blocking one-shot test session. WP2 now enters normal daily field observation using the existing production Runtime Diagnostics subsystem.

## CI / test boundary — CLOSED

The CI/test-boundary corrective is complete and verified.

- Draft engineering synchronize: macOS CI run `41584306688` PASS; Debug PASS; Release/Partition A/Partition B skipped; QA DMG not triggered.
- Control-only synchronize: macOS CI runs `41585108388` and `41585642707` PASS; scope-check PASS; Xcode/Debug/Release/Partition A/Partition B skipped; QA DMG not triggered.
- Final full gate remains available for closeout and retains Debug + Release + arm64 verification + mandatory fresh-process Partition A + Partition B.
- All 38 tracked test files were audited; zero tests removed.

## Runtime Diagnostics observation baseline

No diagnostics source mutation is required before field observation.

Existing production diagnostics already provide:

- Standard / Verbose Runtime Diagnostics;
- local JSONL persistence and export;
- default 7-day bounded retention and segmented rotation;
- optional long-term performance observation on a 60-second cadence;
- `diagnostics.performance_checkpoint` sampling;
- page-app counter delta/rate tracking;
- lifecycle, memory-pressure, reclaim/protection, runtime/navigation/materialization/readiness events already present in production paths.

For this observation window, use:

```text
Runtime Diagnostics = Verbose
Keep local diagnostic history = ON
Long-term performance observation = ON
```

The app should be used normally as the user's primary FloatTabs build. No dedicated 10–20 minute blocking manual session is required.

If a visible anomaly occurs, export Recent Diagnostics before reload/restart where practical and record the approximate time/Slot/retention mode. Otherwise export after normal use within the 7-day retention window.

Diagnostics remain evidence only. Reload/reset/restart may prove a recovery boundary but never root cause.

## Current closeout sequence

1. **CI / test boundary reconciliation — COMPLETE**
2. **Normal-use field observation with existing Runtime Diagnostics — ACTIVE**
3. **Exported JSONL remote audit — PENDING USER SAMPLE**
4. **Evidence-driven bounded diagnostics/product corrective — ONLY IF LOGS JUSTIFY IT**
5. **Final literal-head full gate + exact diff → merge decision → release DMG — BLOCKED UNTIL OBSERVATION REVIEW**

A separate pre-observation diagnostics coverage audit is no longer a blocking gate. If the uploaded logs later prove an evidence gap, add only the minimum instrumentation required to answer that concrete question.

## Safety boundary

- no Browser Profile/session/cookie/site-data clearing;
- no lifecycle ownership change for observation;
- no unsupported WebContent process attribution workaround;
- no runtime-count or host-RSS substitute for aggregate WebContent working-set truth;
- Keep Loaded / Automatic policy remains unchanged;
- no WP3/WP4 during WP2 field observation.

## Merge / release gate

PR #195 remains Draft and unmerged during field observation.

Final merge/release consideration requires:

1. a representative normal-use diagnostics sample reviewed with no blocking WP2 regression, or any observed blocking regression corrected;
2. final literal-head full machine gate green;
3. fresh exact-diff/control reconciliation;
4. explicit merge decision.

The field-observation build may be packaged and installed for normal daily use before merge; that package is a QA/field build, not the final release artifact.
