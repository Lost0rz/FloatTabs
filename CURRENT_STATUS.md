# FloatTabs Current Status

**Status date:** 2026-10-24
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: ACTIVE CORRECTIVE — FINAL WEB/RUNTIME CORRECTIVE AUTHORIZED**

Current task: `FT-WEB-RUNTIME-RECOVERY-ATTENTION-001`

## Verified baseline

```text
MAIN=17f1bf1760625833d0b82397009223b2165521c7
LATEST_RELEASE=v0.5.6
BUILD=24
ARCH=arm64
RELEASE_COMMIT=17f1bf1760625833d0b82397009223b2165521c7
TASK_BRANCH=codex/ft-web-runtime-recovery-attention-001
TASK_PR=144_OPEN_DRAFT_UNMERGED
PREDECESSOR_PR_143=CLOSED_SUPERSEDED_UNMERGED
PRE_FINAL_CORRECTIVE_SEMANTIC_HEAD=95865a33715bde8dde9d4385a829a17ad79f2edd
PRE_FINAL_CORRECTIVE_CONTROL_HEAD=6684538d97a46e474a1a19c3e7f13044549263ae
ROOT_CAUSE=UNKNOWN
INCIDENT_STATE=FRESH_EVIDENCE_REVIEWED / STRUCTURAL_CORRECTIVES_ACCEPTED / FINAL_DIAGNOSTIC_PROJECTION_CORRECTIVE_AUTHORIZED
```

v0.5.6 remains an observation release. Repeated WebContent termination and non-termination runtime stall/near-stall remain real incident evidence; no common root cause is established.

## Independent re-audit state

The independent Web/runtime re-audit of PR #144 accepted the major implementation corrections at semantic head `95865a33715bde8dde9d4385a829a17ad79f2edd`:

```text
PHYSICAL_RUNTIME_EPOCH=PASS
OLD_CALLBACK_INVALIDATION=PASS
SAME_RUNTIME_BUDGET_BOUNDING=PASS
RECOVERY_NAVIGATION_FINISH=PASS
STALE_RECOVERY_CALLBACK=PASS
HOT_PATH_OPTIMIZATION=PASS
STANDARD_COUNTER_STORAGE=PASS
ROOT_CAUSE=UNKNOWN
```

Previous verification for that semantic head:

```text
FULL_XCTEST=1365_PASS_0_FAIL
DEBUG_ARM64=PASS
RELEASE_ARM64=PASS
LARGE_DOM_FIXTURE=PASS_LAYOUT_CHECKS_2_DETECTOR_MAX_0.1_MS
MACOS_CI_1098=SUCCESS_40082588185
QA_DMG_510=SUCCESS_40082588204
```

These receipts do not authorize merge because one diagnostics projection defect and three composed regression gaps remain.

## Remaining code defect

### Standard failure-state counter projection

The bridge already owns bounded Release-enabled native counters for:

- liveness timeout;
- liveness budget suppression;
- current-document-resync timeout;
- current-document-resync budget suppression.

The counters are correctly stored independent of normal measurement resets. The remaining defect is projection: `captureLongTermWorkloadDiagnosticFields(...)` currently receives those counters through the document-bound benchmark snapshot. If current-document resync has timed out/suppressed and the bridge remains `awaiting_authorized_resync`, there may be no active document; `captureBenchmarkSnapshot(...)` returns `document_unavailable`, and the native failure counters can be absent from the Standard periodic checkpoint exactly while the failure is active.

Required correction is narrow:

```text
ANY workload snapshot outcome
(ok / document_unavailable / timeout / stale / evaluation_failed / suppressed)
+
native bridge health counters
→
long-term diagnostic fields / Standard performance checkpoint
```

This must not require another JavaScript call and must not alter document admission, recovery, liveness cadence, or request-budget ownership.

## Remaining evidence gaps

Three composed regressions remain mandatory before independent acceptance:

1. **Liveness ordinary document replacement does not manufacture physical capacity**
   - exhaust same-process physical liveness budget with never-returning requests;
   - timeout semantically;
   - prove suppression;
   - perform ordinary document/navigation replacement;
   - prove capacity remains exhausted;
   - then perform authoritative WebContent replacement and prove fresh capacity.

2. **Deferred recovery identity chain**
   - inactive termination → deferred recovery → activation → exact recovery `WKNavigation` registration → commit → finish;
   - prove fresh generation, non-stale callbacks, and `navigation_phase=finished`.

3. **Recovered finish restores post-finish-stall eligibility**
   - termination → recovery registration → commit without provisional → finish;
   - then drive deterministic dual-world timeout evidence;
   - prove the recovered finished navigation can enter the existing post-finish-stall classification path.

These are verification/evidence gaps unless their tests expose a new production ownership defect.

## Frozen accepted areas

Do not change without a failing regression that proves necessity:

- exact `WKNavigation` recovery identity ownership;
- physical WebContent runtime epoch design;
- late old-epoch callback rejection;
- finite liveness/resync budgets;
- Attention semantic selector narrowing and predicate ordering;
- generating-path response-identity skip;
- 250-ms Attention coalescing;
- 2-second liveness cadence;
- 30-second cross-world cadence;
- WebContent reload/deferred recovery policy;
- Hot/Warm/Cold residency policy.

## Safety boundary

No authorization to:

- claim WebContent termination root cause is known;
- add reload/reset/rebuild/restart mitigation;
- clear or migrate Browser Profiles, cookies, sessions, WebsiteData, Slots, preferences, backups, or diagnostics history;
- use private WebKit APIs;
- capture prompt/response text, page content, selector text, cookies, tokens, or session values;
- broaden this task into general diagnostics compaction or general WebView lifecycle redesign.

## Repository lifecycle

- PR #143 remains `CLOSED / SUPERSEDED / UNMERGED`.
- PR #144 remains the sole write-capable workspace for this corrective.
- PR #144 must remain `OPEN / DRAFT / UNMERGED` until fresh exact-head verification and independent Web/runtime acceptance pass.

## Next milestone

Execute the final narrow corrective in PR #144:

1. always merge native health counters into long-term diagnostic fields independent of document snapshot status;
2. add the three composed regressions above;
3. run focused/full XCTest, Debug/Release arm64, deterministic large-DOM fixture, `git diff --check`;
4. push same branch;
5. obtain exact-head macOS CI and QA DMG;
6. return for independent Web/runtime re-audit;
7. do not Ready/merge/release before that acceptance.
