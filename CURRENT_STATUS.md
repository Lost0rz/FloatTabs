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
FINAL_CORRECTIVE_SEMANTIC_HEAD=c63578e6e8163a28d210ef60987d7ccd39d51af1
ROOT_CAUSE=UNKNOWN
INCIDENT_STATE=FRESH_EVIDENCE_REVIEWED / FINAL_CORRECTIVE_VERIFIED / INDEPENDENT_WEB_RUNTIME_REAUDIT_PENDING
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

Those historical receipts did not authorize merge; the final corrective now has fresh local and exact-head host verification, but independent Web/runtime acceptance is still required.

## Final corrective verification

The final corrective semantic head is `c63578e6e8163a28d210ef60987d7ccd39d51af1`.

The native health counters are now merged from a content-free native helper on every long-term workload outcome, including unavailable, timeout, stale, evaluation-failed, and suppressed paths. No additional JavaScript probe, document admission, recovery, or budget ownership change was introduced.

The three composed regressions are now present and passing:

1. same-physical-runtime liveness budget remains exhausted across ordinary document replacement and resets only on authoritative WebContent replacement;
2. deferred inactive recovery registers and finishes the exact returned `WKNavigation` without stale callbacks;
3. recovered finish restores deterministic post-finish-stall eligibility.

Final local verification:

```text
FOCUSED_AND_RELATED_TESTS=PASS
FULL_XCTEST=1367_PASS_0_FAIL_3_SKIPPED_OF_1370
DEBUG_ARM64=PASS
RELEASE_ARM64=PASS
LARGE_DOM_FIXTURE=PASS
GIT_DIFF_CHECK=PASS
MACOS_CI_1102=SUCCESS_40086444312
QA_DMG_514=SUCCESS_40086444322
PR_HEAD=c63578e6e8163a28d210ef60987d7ccd39d51af1
```

This verification does not establish the WebContent termination/stall root cause or independent runtime acceptance.

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

Return PR #144 for independent Web/runtime re-audit at the final corrective head:

1. review the content-free Standard failure-state projection;
2. review the three composed regression contracts and exact-head receipts;
3. keep PR #144 Draft and unmerged until independent acceptance passes;
4. do not Ready/merge/release before that acceptance.
