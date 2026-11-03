# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Card ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001-WP2-001`  
**Title:** WP2 closeout hardening — reconcile CI/test scope before long-run diagnostics observation  
**Status:** **ACTIVE / CI-TEST BOUNDARY CORRECTIVE AUTHORIZED**  
**Mode:** `EXECUTE / TEST+CI ONLY / EXISTING DRAFT PR / NO PRODUCT MUTATION / NO MERGE OR RELEASE`  
**Task class:** `CI / TEST GOVERNANCE + WP2 CLOSEOUT`  
**Baseline:** `origin/main@2a52800f770266f7c901eb612a0b319ddca142df`  
**Branch:** `codex/adaptive-lifecycle-wp2-policy`  
**PR:** `#195 OPEN / DRAFT / UNMERGED`

## Decision

Short-run human smoke on the installed WP2 QA build has not exposed a visible product defect. Long-idle and long-duration confidence will be collected through normal-use Runtime Diagnostics rather than requiring one long blocking manual session.

Before any diagnostics augmentation, the repository must first reduce unnecessary CI/test churn and retire only evidence-proven stale test material.

## Active work package — CI / test boundary reconciliation

### Objective A — stop control-only synchronization from rerunning heavy CI

The current `pull_request` path filter is not sufficient because GitHub evaluates the PR's three-dot changed-file set. Once a PR contains engineering changes, a later control-only commit still matches those paths.

Implement a bounded synchronization classifier that distinguishes the **new PR head delta** from the accumulated PR diff.

Required behavior:

- `pull_request` `synchronize` with only control/docs delta must finish the required check without running Debug build, Release build, XCTest partitions, or QA DMG;
- engineering delta must still enter the appropriate machine gate;
- opened/reopened/final explicit verification paths must fail safe to real verification rather than silently skip;
- current required-check semantics must remain merge-safe;
- do not rely only on deleting `CURRENT_STATUS.md` / `CURRENT_TASK.md` from `paths:`.

GitHub synchronize payload `before` / `after` may be used for incremental classification. Preserve normal merge-context testing for the heavy gate; do not accidentally replace it with head-only product verification unless the difference is explicitly justified and accepted.

### Objective B — make routine Draft verification proportional

Routine Draft iteration must not execute the full expensive closeout gate on every synchronization.

Target policy:

```text
CONTROL/DOCS-ONLY SYNCHRONIZE
  -> lightweight successful scope check only

DRAFT ENGINEERING SYNCHRONIZE
  -> fast machine gate sufficient to catch compile/configuration breakage
  -> no automatic full canonical XCTest + QA DMG on every small iteration

FINAL / EXPLICIT CLOSEOUT GATE
  -> full canonical XCTest coverage using mandatory Partition A + Partition B fresh processes
  -> Debug + Release build
  -> native arm64 verification
  -> QA DMG when required

MAIN
  -> retain strong post-merge verification appropriate to release safety
```

The implementation may choose the smallest workflow structure that preserves these semantics. Avoid adding a large CI framework.

### Objective C — test inventory / stale material audit

Audit `FloatTabsTests` against current architecture/product authority and classify each removal candidate as one of:

- CURRENT_REQUIRED
- DUPLICATE_CURRENT_COVERAGE
- RETIRED_CONTRACT
- TEMPORARY_INCIDENT_HARNESS
- UNKNOWN_KEEP

Only `DUPLICATE_CURRENT_COVERAGE`, `RETIRED_CONTRACT`, or `TEMPORARY_INCIDENT_HARNESS` with concrete evidence may be removed.

Do not delete tests merely because they are old, slow, flaky, numerous, or inconvenient.

In particular preserve current coverage for:

- Browser Profile / site-data isolation and persistence;
- Slot/runtime lifecycle policy;
- data/session safety;
- focus/input;
- fullscreen/window synchronization;
- Attention/notification behavior still in product scope;
- persistence/recovery;
- current WebKit integration boundaries.

The preserved fixture-teardown experiment is still `SUPERSEDED_FOR_THIS_INCIDENT / NOT_FOR_MERGE`; do not cherry-pick it into this corrective.

### Objective D — local historical artifact cleanup

After evidence needed for the current task is identified, stale `/private/tmp/FloatTabs-*` and obsolete `.xcresult`/DerivedData diagnostic artifacts may be listed for cleanup.

Do not delete the currently identified preserved evidence checkouts until their disposition is explicitly returned. Never delete Browser Profile, website session/data, preferences, backup, Application Support user data, or installed user configuration.

## Allowed mutation

- `.github/workflows/**` relevant to FloatTabs CI / QA DMG;
- small `tools/ci/**` helper if it materially reduces duplicated workflow logic;
- test project/source only for evidence-proven stale/retired test cleanup;
- CURRENT_STATUS / CURRENT_TASK final reconciliation after verification.

## Not authorized in this work package

- FloatTabs production behavior/source changes;
- Runtime lifecycle policy changes;
- WebsiteDataStore / WKProcessPool changes;
- Browser Profile/session/cookie/site-data clearing;
- assertion weakening to make tests pass;
- timeout/retry inflation;
- permanent skipping of current required coverage;
- diagnostics production mutation yet;
- WP3/WP4;
- merge or release.

If removing a candidate test requires changing current production semantics or current contract, STOP and return it as `UNKNOWN_KEEP`.

## Verification gate

The corrective is accepted only if evidence proves all of the following:

```text
CONTROL_ONLY_SYNC_HEAVY_CI=SKIPPED
CONTROL_ONLY_SYNC_REQUIRED_CHECK=PASS
DRAFT_ENGINEERING_FAST_GATE=PASS
FINAL_FULL_GATE_AVAILABLE=YES
FINAL_PARTITION_A_REQUIRED=YES
FINAL_PARTITION_B_REQUIRED=YES
FINAL_CANONICAL_COVERAGE_NOT_REDUCED=YES
QA_DMG_NOT_RUN_ON_CONTROL_ONLY_SYNC=YES
PRODUCTION_FILES_CHANGED=NONE
CURRENT_REQUIRED_TESTS_REMOVED=NONE
```

For any removed tests, return exact file/method evidence and the current authority that makes them obsolete or duplicate.

## Next work package — blocked until this one closes

`WP2 LONG-RUN DIAGNOSTICS COVERAGE AUDIT / AUGMENTATION`

Existing diagnostics already provide a 60-second long-term checkpoint, JSONL local history/export, bounded retention and several lifecycle events. The next stage must first prove what WP2 evidence is missing, then add only the minimum fields/events required to reconstruct:

```text
slot/runtime identity
runtime retention preference
Automatic stage / inactive age
protection state + reason
reclaim eligibility / reason
actual teardown/hibernate outcome
subsequent materialization/readiness outcome
manual reload/restart/recovery boundary when observed
```

Do not redesign the diagnostics subsystem if existing events can already answer the question.

## Merge / release gate

```text
PR_195=OPEN_DRAFT_UNMERGED
MERGE_READY=NO
RELEASE_READY=NO
WP3=NOT_STARTED
WP4=NOT_STARTED
```

After CI/test-boundary closeout, return to Project Governance before starting diagnostics mutation.

## Return contract

```text
START_HEAD
FINAL_HEAD
FILES_CHANGED
PRODUCTION_FILES_CHANGED

CI_TRIGGER_CLASSIFICATION_DESIGN
CONTROL_ONLY_SYNC_RESULT
DRAFT_ENGINEERING_GATE_RESULT
FINAL_FULL_GATE_RESULT
QA_DMG_TRIGGER_RESULT

TEST_INVENTORY_AUDITED
REMOVED_TESTS
REMOVAL_EVIDENCE
CURRENT_REQUIRED_TESTS_REMOVED

STALE_LOCAL_ARTIFACTS_IDENTIFIED
PRESERVED_EVIDENCE_UNCHANGED

SELF_HOSTED_RUNNER_HEAVY_WORK_FOR_CONTROL_ONLY
EXACT_DIFF_AUDIT
COMMIT
PUSH
PR_STATE
MERGE=NOT_MERGED
RELEASE=NOT_RELEASED

RECOMMENDED_NEXT_BOUNDARY
```
