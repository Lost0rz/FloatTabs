# FloatTabs Current Status

**Status date:** 2026-11-03  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: ADAPTIVE LIFECYCLE — WP2 CORRECTIVE / MACHINE GATE**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001 / WP2-001` — **ACTIVE / CORRECTIVE AUTHORIZED**.

Branch: `codex/adaptive-lifecycle-wp2-policy`  
Draft PR: `#195`  
Baseline: `main@2a52800f770266f7c901eb612a0b319ddca142df`  
Control/design bootstrap: `e289171eff3d5045c48a86c229b7967e126ec087`  
Prior WP2 implementation evidence head: `647178030b5a448916537745e7a993e4eca0a238`
WP2 corrective base head: `f0705747c6a095f24d50c9ffdac21675a1bfc662`
WP2 corrective implementation / semantic head: `cc44537635ef451a78dc8894484c9ce9328de936`
Durable policy: `docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md`

## Repository / gate state

```text
WP1=COMPLETE / HUMAN_ACCEPTED
WP2_FIXED_RESIDENT_COUNT=REMOVED
WP2_STAGED_AUTOMATIC_POLICY=IMPLEMENTED
WP2_CORRECTIVE_A=IMPLEMENTED / HOSTED_XCODE_26.6_RELEASE_PASS
WP2_CORRECTIVE_B=IMPLEMENTED / FRESH_SELECTION_REGRESSIONS_PASS
WP2_CORRECTIVE_C=IMPLEMENTED / INJECTED_TIME_REGRESSIONS_PASS
LOCAL_FOCUSED_CORRECTIVE_TESTS=PASS (10 run / 0 failed)
LOCAL_AFFECTED_LIFECYCLE_WP1_REGRESSIONS=PASS (503 run / 0 failed)
LOCAL_FULL_XCTEST=FAIL (1,152 passed; 13 test methods / 93 assertion failures; reproduced in three full runs)
ISOLATED_RERUN_OF_FULL_SUITE_FAILURES=PASS (13 run / 0 failed)
LOCAL_DEBUG_RELEASE_ARM64=PASS
NATIVE_ARM64=PASS
PACKAGE_LOCK=UNCHANGED
GIT_DIFF_CHECK=PASS
EXACT_HEAD_SELF_HOSTED_CI=FAIL / 41554110074 (build, package-lock, architecture pass; unit tests fail)
EXACT_HEAD_QA_DMG=PASS / 41554110135 (Xcode 26.6)
INDEPENDENT_AUDIT=STOP (exact-head XCTest gate failed; no policy blocker found in corrective diff)
FULL_SUITE_FAILURE_ROOT_CAUSE=UNKNOWN
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
PR_195=OPEN_DRAFT_UNMERGED / HEAD cc44537635ef451a78dc8894484c9ce9328de936
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
```

## Corrective outcome and remaining gate

Correctives A, B, and C are implemented in the two-file corrective diff from `f0705747c6a095f24d50c9ffdac21675a1bfc662` to `cc44537635ef451a78dc8894484c9ce9328de936`:

- A uses explicit typed lifecycle-stage computation; the hosted Xcode 26.6 Release/WMO QA DMG build passed.
- B re-enters canonical pressure candidate selection from fresh facts when an owned async media result finds its captured plan stale; the old plan cannot reclaim a replacement Runtime.
- C injects monotonic time and delayed scheduling for deterministic stage-boundary and stale timer/token tests while preserving production defaults.

The exact-head macOS CI completed package-lock, Debug/Release build, and native arm64 steps, then failed in full XCTest. The same 13 failing test methods passed when run individually, but this does not clear the full-suite gate. Failures appeared in WebFocusAdapter, WebViewFactory, and WebsiteLayoutGeometryRegression tests; their cause and relation to the corrective are unverified.

The independent exact-diff audit found no policy or ownership blocker in the corrective changes, but returned `STOP` because the exact-head full XCTest gate failed. Keep the task active and Human UI acceptance blocked until the full-suite failure is resolved and the required gates are rerun.

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
diagnose or resolve the exact-head full XCTest failure
→ rerun full XCTest and exact-head self-hosted macOS CI
→ refresh independent exact-diff / ownership / data-safety audit if implementation changes
→ only if all PASS: user-owned Human UI acceptance
```

Do not merge PR #195, release, or begin WP3/WP4 before that gate is complete.
