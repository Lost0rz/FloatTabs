# FloatTabs Current Task

**Task ID:** `FT-RELEASE-V0.5.8-001`
**Title:** Publish v0.5.8 and enter runtime observation
**Status:** `ACTIVE / RELEASE PREPARATION`
**Mode:** `RELEASE`
**Task class:** `RELEASE / DOCUMENTATION / OBSERVATION`
**Authorized baseline:** `main@73eee804cbe32a32bdce9b389be98939570c097e`
**Target release:** `v0.5.8`
**Target build:** `26`
**Historical runtime root cause:** `UNKNOWN`

## Objective

Publish the diagnostics-capable post-v0.5.7 `main` as FloatTabs v0.5.8 / Build 26, align current repository documentation with the merged state, and then enter a non-mutating runtime observation period so fresh real-world incidents can be evaluated from the enhanced diagnostics.

## Authorized scope

This task may:

1. update `CURRENT_STATUS.md` and `CURRENT_TASK.md` to reflect PR #153 merged state and release lifecycle;
2. update current user-facing / architecture navigation documentation where it is materially stale;
3. add `docs/release/FloatTabs_v0.5.8.md`;
4. bump `MARKETING_VERSION` from `0.5.7` to `0.5.8` and `CURRENT_PROJECT_VERSION` from `25` to `26`;
5. create and merge the dedicated v0.5.8 release PR after required exact-head checks pass;
6. allow the existing `Publish Release` workflow to build, checksum, tag and publish the GitHub Release from merged `main`;
7. verify the published tag, target commit and release assets;
8. after release, leave the project in `WAITING / RUNTIME OBSERVATION`, where diagnostics may be collected and read without changing product behavior.

## Release content boundary

v0.5.8 contains the runtime incident diagnostics merged by PR #153 after v0.5.7. It does not claim the historical WebContent stall/termination root cause has been found or eliminated.

The accepted runtime diagnostics include shared incident correlation, bounded automatic snapshots, WebContent termination/recovery correlation, memory-pressure decision evidence, Attention abnormal-path evidence, previous-app restore terminal outcomes, page-app evidence corrections, and redundant-log reduction without reducing health-probe cadence.

## Safety boundaries

The release task must not change:

```text
RECOVERY_POLICY
RELOAD_RESET_BEHAVIOR
RESIDENCY_POLICY
FOCUS_POLICY
ATTENTION_BUSINESS_STATE
TIMEOUT_THRESHOLDS
BROWSER_PROFILES
WEBSITE_SESSIONS_DATA
PERSISTENCE
USER_DATA
```

No Browser Profile, website session, cookie, preference, backup or persisted website data may be reset or cleared as part of release or observation.

## Verification / release gates

Before merge:

1. release branch is based on fresh `main@73eee804cbe32a32bdce9b389be98939570c097e` unless `main` advances only through reconciled task-compatible changes;
2. documentation accurately records PR #153 as merged and removes stale pre-merge wording;
3. release notes exist at `docs/release/FloatTabs_v0.5.8.md`;
4. project metadata resolves exactly to `0.5.8 / 26`;
5. no runtime/product semantic source changes are included in the release PR;
6. required `Build & Test (Apple Silicon arm64)` succeeds on the literal PR head;
7. QA DMG succeeds when triggered;
8. PR is mergeable with no new blocking review finding.

After merge:

1. merged `main` is the release workflow source identity;
2. `Publish Release` completes successfully;
3. GitHub Release `v0.5.8` is public and non-prerelease;
4. tag target equals the merged release commit;
5. expected assets exist:
   - `FloatTabs-0.5.8.dmg`
   - `FloatTabs-0.5.8.dmg.sha256`
   - `FloatTabs-0.5.8.dSYM.zip`
   - `FloatTabs-0.5.8.dSYM.zip.sha256`;
6. post-release control plane records the published version/build and observation state.

## Observation mode

After successful release, the task transitions to `WAITING / RUNTIME OBSERVATION`.

During observation:

- continue normal use;
- if a fresh slowdown, stall, WebContent termination, Attention abnormality, or focus-restore anomaly occurs, preserve/export Runtime Diagnostics before reload/restart when practical;
- record approximate incident time and affected Slot/site;
- treat reload/reset/restart only as recovery evidence, not root-cause proof;
- preserve `ROOT_CAUSE=UNKNOWN` until fresh evidence proves otherwise;
- no product/runtime mutation is authorized merely because an observation exists.

Any follow-on code fix requires task reconciliation before mutation.
