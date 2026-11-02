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
WP2 implementation evidence head: `647178030b5a448916537745e7a993e4eca0a238`  
Durable policy: `docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md`

## Repository / gate state

```text
WP1=COMPLETE / HUMAN_ACCEPTED
WP2_FIXED_RESIDENT_COUNT=REMOVED
WP2_STAGED_AUTOMATIC_POLICY=IMPLEMENTED
LOCAL_FOCUSED_TESTS=PASS (589 run / 4 skipped / 0 failed)
LOCAL_FULL_XCTEST=PASS (1160 run / 4 skipped / 0 failed)
LOCAL_DEBUG_RELEASE_ARM64=PASS
PACKAGE_LOCK=UNCHANGED
EXACT_HEAD_SELF_HOSTED_CI=PASS / 41481345174
EXACT_HEAD_QA_DMG=FAIL / 41481345149
INDEPENDENT_AUDIT=STOP / IMPORTANT
HUMAN_UI_ACCEPTANCE=BLOCKED_NOT_STARTED
PR_195=OPEN_DRAFT_UNMERGED
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
```

## Verified corrective blockers

### A. Hosted QA Release compile compatibility

The exact-head hosted QA DMG build fails under Xcode 26.6 Release/WMO at `FloatTabs/Web/SlotLifecycleCoordinator.swift:1052`:

```text
let stage = plan.map { stage(forInactiveSince: $0.inactiveSinceUptime) }
```

The compiler resolves `Optional.map` through SwiftUI `Optional: Gesture` overloads and cannot infer the closure. The local and self-hosted builds passing do not transfer to this hosted Release identity. Corrective must make this expression unambiguous without changing lifecycle semantics.

### B. Progressive pressure stale-plan continuation

The async media-validation path owns `pressureReclaimEvaluationToken`, clears it on callback, then validates the captured inactive plan. If that captured plan is stale while pressure is still warning/critical, the current guard returns without restarting progressive candidate selection. Another eligible Automatic Runtime can therefore remain unreclaimed until some unrelated later lifecycle event re-enters pressure evaluation.

The exact-head `isPlaying == true` branch itself already marks media protection and schedules pressure continuation; it is **not** the remaining defect. Corrective scope is stale/invalidated async evaluation and equivalent owned-evaluation exits under sustained pressure.

### C. V7 deterministic time-test contract

Policy V7 requires lifecycle-stage tests to inject time rather than wait in real time. Production currently reads `ProcessInfo.processInfo.systemUptime` directly and at least one stage-boundary test still depends on real waiting. Machine evidence is therefore incomplete against the frozen test contract. Add a bounded monotonic-time/test scheduling seam sufficient to test RECENT → IDLE → LONG_IDLE deterministically without changing production policy timings.

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
WP2 corrective A+B+C
→ focused deterministic regressions
→ full XCTest
→ Debug/Release arm64
→ package-lock + architecture checks
→ push exact head
→ self-hosted macOS CI
→ hosted QA DMG
→ fresh independent exact-diff / ownership / data-safety audit
→ only if all PASS: user-owned Human UI acceptance
```

Do not merge PR #195, release, or begin WP3/WP4 before that gate is complete.