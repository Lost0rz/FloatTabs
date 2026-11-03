# FloatTabs Current Status

**Status date:** 2026-11-03  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: ADAPTIVE LIFECYCLE — WP2 FULL-XCTEST INCIDENT DIAGNOSIS**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001 / WP2-001` — **ACTIVE / READ-ONLY INCIDENT DIAGNOSIS**.

Branch: `codex/adaptive-lifecycle-wp2-policy`  
Draft PR: `#195`  
Baseline: `main@2a52800f770266f7c901eb612a0b319ddca142df`  
Control/design bootstrap: `e289171eff3d5045c48a86c229b7967e126ec087`  
WP2 corrective base head: `f0705747c6a095f24d50c9ffdac21675a1bfc662`  
WP2 corrective implementation / semantic head: `cc44537635ef451a78dc8894484c9ce9328de936`  
Incident-diagnosis authority commit: `d4f8e1167503d664445320942417b7a368154655`  
Durable policy: `docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md`

## Repository / gate state

```text
WP1=COMPLETE / HUMAN_ACCEPTED
WP2_FIXED_RESIDENT_COUNT=REMOVED
WP2_STAGED_AUTOMATIC_POLICY=IMPLEMENTED
WP2_CORRECTIVE_A=PASS
WP2_CORRECTIVE_B=PASS
WP2_CORRECTIVE_C=PASS
LOCAL_FOCUSED_CORRECTIVE_TESTS=PASS (10 run / 0 failed)
LOCAL_AFFECTED_LIFECYCLE_WP1_REGRESSIONS=PASS (503 run / 0 failed)
LOCAL_FULL_XCTEST=FAIL (13 test methods / 93 assertion failures; reproduced in three full runs)
ISOLATED_13_METHOD_RERUN=PASS
LOCAL_DEBUG_RELEASE_ARM64=PASS
NATIVE_ARM64=PASS
PACKAGE_LOCK=UNCHANGED
GIT_DIFF_CHECK=PASS
IMPLEMENTATION_HEAD_SELF_HOSTED_CI=FAIL / 41554110074 (Unit Tests)
IMPLEMENTATION_HEAD_QA_DMG=PASS / 41554110135
FINAL_PRE_DIAG_CONTROL_HEAD_SELF_HOSTED_CI=FAIL / 41555572505 (Unit Tests only; build/package/arm64 pass)
FINAL_PRE_DIAG_CONTROL_HEAD_QA_DMG=PASS / 41555572558
INDEPENDENT_CORRECTIVE_DIFF_AUDIT=NO_POLICY_OR_OWNERSHIP_BLOCKER / STOP_ON_XCTEST_GATE
FULL_SUITE_FAILURE_ROOT_CAUSE=UNKNOWN
CORRECTIVE_ATTRIBUTION=UNPROVEN
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
PR_195=OPEN_DRAFT_UNMERGED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
```

## Corrective outcome

Correctives A, B, and C are implemented at semantic head `cc44537635ef451a78dc8894484c9ce9328de936`:

- A: explicit compiler-unambiguous lifecycle-stage computation; hosted Xcode 26.6 QA DMG passes.
- B: stale async media-plan callbacks cannot reclaim stale Runtime and re-enter canonical pressure selection from fresh facts while pressure remains active.
- C: injected monotonic uptime and delayed scheduling make RECENT/IDLE/LONG_IDLE and stale timer/token regressions deterministic without real sleeping; production defaults remain system uptime/main-queue scheduling.

Focused/affected regressions pass and the independent corrective diff audit found no policy/ownership blocker.

## Remaining incident

The remaining blocker is the canonical full XCTest gate. Failures occur in unchanged WebFocusAdapter, WebViewFactory, and WebsiteLayoutGeometryRegression tests. The same 13 methods pass individually. Failing runs contain WebKit fixture/page-load timeouts and related WebContent/runtime errors. Current evidence does not establish whether the corrective caused the failure, exposed pre-existing shared-state/test-order contamination, or coincided with runner/WebKit host instability/resource pressure.

The self-hosted final pre-diagnosis run `41555572505` passed package resolution/lock, Debug build, Release build, and native arm64 verification; only Unit Tests failed.

## Current diagnostic gate

`CURRENT_TASK.md` now authorizes a bounded read-only incident diagnosis. Required causal comparison includes:

```text
exact failure inventory
→ 13-test same-order/reverse-order fresh-process batches
→ full-suite A/B on corrective base f0705747... vs semantic head cc445376...
→ prefix/order contamination narrowing when applicable
→ diagnostic-only serial comparison when applicable
→ bounded WebKit process/runtime observations
→ attribution/root-cause verdict
```

No production/test mutation is authorized during this stage.

Required verdicts:

```text
CORRECTIVE_ATTRIBUTION=PROVEN | DISPROVEN | UNPROVEN
FULL_SUITE_ROOT_CAUSE=KNOWN | NARROWED | UNKNOWN
```

Only evidence supporting a specific bounded mutation can authorize another EXECUTE corrective.

## Preserved WP2 policy

- normal Runtime count is never a reclaim reason;
- Keep Loaded / Pinned is never automatically reclaimed by normal, warning, or critical FloatTabs policy;
- Automatic stages remain RECENT `<30s`, IDLE `>=30s && <600s`, LONG_IDLE `>=600s`;
- 30s remains anti-thrash protection; 600s remains the initial tunable long-idle default;
- warning reclaims only eligible IDLE/LONG_IDLE Automatic progressively;
- critical may include RECENT Automatic but never Keep Loaded or hard-protected Runtime;
- pressure progression remains fresh-fact, oldest-first, one-step-at-a-time;
- WP1 presentation/readiness, generation/Attention, media/fullscreen, notification privacy/routing, and Browser Profile/session data safety remain regression boundaries.

## Next gate

```text
complete read-only full-XCTest incident diagnosis
→ if mutation is proven necessary, reconcile authority before mutation
→ rerun canonical full XCTest and exact-head self-hosted CI
→ fresh independent audit as required
→ only if all PASS: user-owned Human UI acceptance
```

Do not merge PR #195, release, or begin WP3/WP4 before that gate is complete.
