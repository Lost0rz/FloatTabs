# FloatTabs Current Task

**Task ID:** `FT-WEB-RUNTIME-RECOVERY-ATTENTION-001`
**Title:** Correct recovery navigation state and reduce bounded ChatGPT attention runtime overhead
**Status:** `ACTIVE — INDEPENDENT WEB/RUNTIME ACCEPTANCE PASS / FINAL MERGE AUDIT PENDING`
**Mode:** `EXECUTION`
**Task class:** `CORRECTIVE`

## Authority / baseline

```text
BASE_MAIN=17f1bf1760625833d0b82397009223b2165521c7
PUBLIC_RELEASE=v0.5.6
PUBLIC_BUILD=24
ARCH=arm64
PR=144
BRANCH=codex/ft-web-runtime-recovery-attention-001
FINAL_CORRECTIVE_SEMANTIC_HEAD=c63578e6e8163a28d210ef60987d7ccd39d51af1
PRE_ACCEPTANCE_CONTROL_HEAD=50f688f069cd14758853493d80ed9e74aa2a330b
ROOT_CAUSE=UNKNOWN
BUG_FIXED_CLAIM=NO
```

Authoritative runtime evidence remains `runtime-20261023-003.jsonl` and `runtime-20261024-001.jsonl`. They establish repeated WebContent process termination plus non-termination runtime stalls/near-stalls, but do not establish a shared causal root.

## Independent acceptance result

Fresh independent Web/runtime re-audit of final semantic head `c63578e6e8163a28d210ef60987d7ccd39d51af1` is **PASS**.

The accepted implementation contracts are:

- exact `WKNavigation` recovery identity is retained/registered before recovery commit handling;
- recovery commit without a usable provisional callback produces a fresh non-stale navigation generation;
- recovery `didFinish` restores `navigation_phase=finished`;
- old/superseded recovery callbacks cannot hijack the current ticket;
- inactive/deferred recovery uses the same exact returned `WKNavigation` identity through activation, commit, and finish;
- recovered finish restores post-finish dual-world timeout stall-candidate eligibility;
- liveness/resync request budgets are owned by an explicit physical WebContent runtime epoch;
- ordinary document/navigation replacement does not free unresolved same-process physical capacity;
- authoritative WebContent process replacement discards old-epoch markers and starts a fresh finite budget;
- late old-epoch callbacks are harmless no-ops;
- native Attention timeout/suppression health counters remain bounded, Release-enabled, content-free, and visible in Standard periodic diagnostics even when the document snapshot is unavailable or the workload capture exits early as suppressed;
- accepted Attention detector hot-path optimization and existing cadence are preserved.

## Verification evidence

```text
FOCUSED_AND_RELATED_TESTS=PASS
FULL_XCTEST=1367_PASS_0_FAIL_3_SKIPPED_OF_1370
DEBUG_ARM64=PASS
RELEASE_ARM64=PASS
LARGE_DOM_FIXTURE=PASS
GIT_DIFF_CHECK=PASS
SEMANTIC_MACOS_CI_1102=SUCCESS_40086444312
SEMANTIC_QA_DMG_514=SUCCESS_40086444322
PRE_ACCEPTANCE_CONTROL_MACOS_CI_1103=SUCCESS_40086995308
PRE_ACCEPTANCE_CONTROL_QA_DMG_515=SUCCESS_40086995311
INDEPENDENT_WEB_RUNTIME_ACCEPTANCE=PASS
```

## Merge gate

No further production/test mutation is authorized unless a new blocker appears.

Before merge:

1. confirm current PR head contains the accepted semantic head and any newer commits are control-only;
2. confirm fresh `main` has not drifted materially from `17f1bf1760625833d0b82397009223b2165521c7`;
3. require literal-final-head macOS CI success;
4. require literal-final-head QA DMG success;
5. confirm PR remains mergeable and there is no unresolved blocking review/thread;
6. perform final merge audit;
7. only then mark PR #144 Ready and merge.

A merge does not authorize a release. Release remains a separate decision.

## Safety / non-goals

Do not:

- claim WebContent termination/stall root cause is known;
- add reload/reset/rebuild/restart mitigation;
- change recovery disposition or Hot/Warm/Cold residency semantics;
- clear/migrate Browser Profiles, cookies, sessions, WebsiteData, Slots, preferences, backups, or diagnostics history;
- use private WebKit APIs;
- capture page/prompt/response content, selector text, cookies, tokens, or session values;
- broaden this task into general diagnostics compaction or general WebView lifecycle redesign.

## Delivery

```text
PR_STATE=OPEN_DRAFT_UNMERGED
ROOT_CAUSE=UNKNOWN
INDEPENDENT_WEB_RUNTIME_ACCEPTANCE=PASS
MERGE=NOT_YET_AUTHORIZED_PENDING_LITERAL_FINAL_HEAD_CHECKS
RELEASE=NOT_AUTHORIZED
NEXT=FINAL_MERGE_AUDIT_AFTER_LITERAL_FINAL_HEAD_CI_QA
```
