# FloatTabs Current Task

**Task ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Card ID:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001-WP2-001`  
**Title:** Replace fixed-count normal Runtime reclaim with staged Automatic lifecycle  
**Status:** **ACTIVE / WP2 CORRECTIVE AUTHORIZED**  
**Mode:** `SOURCE CORRECTIVE / EXISTING DRAFT PR / NO MERGE OR RELEASE`  
**Task class:** `WEB RUNTIME / LIFECYCLE POLICY`  
**Baseline:** `origin/main@2a52800f770266f7c901eb612a0b319ddca142df`  
**Branch:** `codex/adaptive-lifecycle-wp2-policy`  
**PR:** `#195 OPEN / DRAFT / UNMERGED`

## Authority

Durable WP2 policy: `docs/architecture/FloatTabs_Runtime_Lifecycle_Policy_V7.md`  
WP1 regression authority: `docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`

The frozen WP2 product policy remains unchanged. This corrective closes machine/audit evidence gaps only; it does not authorize a policy redesign, WP3 scheduling work, WP4 work, merge, or release.

## Verified implementation state

Implementation evidence head: `647178030b5a448916537745e7a993e4eca0a238`.

Verified results on that head:

```text
fixed normal resident-count reclaim removed = YES
Automatic RECENT / IDLE / LONG_IDLE model = IMPLEMENTED
Keep Loaded excluded from normal/warning/critical reclaim = YES
focused local tests = PASS (589 run / 4 skipped / 0 failed)
full local XCTest = PASS (1160 run / 4 skipped / 0 failed)
local Debug/Release arm64 = PASS
Package.resolved = unchanged
self-hosted exact-head macOS CI = PASS / run 41481345174
hosted exact-head QA DMG = FAIL / run 41481345149
fresh independent audit = STOP / IMPORTANT
human UI acceptance = BLOCKED / USER OWNED
```

## Corrective authorization

### A — Hosted Release compiler compatibility

Fix the exact semantic expression at `SlotLifecycleCoordinator.swift` that currently uses a locally inferred `plan.map { stage(...) }` form and fails in the hosted Xcode 26.6 Release/WMO build.

Required result:

- make the lifecycle-stage optional computation explicit and compiler-unambiguous;
- preserve the exact diagnostic semantics;
- do not suppress the QA build, change workflow/toolchain to hide the error, or weaken Release verification.

A straightforward explicit `if let` / explicitly typed optional computation is preferred over clever overload disambiguation.

### B — Progressive pressure async stale-plan recovery

The progressive pressure ladder must not stall merely because an asynchronous media-validation result returns for a captured inactive plan that became stale while pressure is still warning/critical.

Required semantics:

```text
pressure candidate selected
→ async media validation owns evaluation token
→ callback clears exact evaluation ownership
→ pressure normalized? stop
→ captured plan still current? evaluate/reclaim/protect normally
→ captured plan stale/invalid? re-enter progressive selection from fresh facts
```

Every owned async evaluation exit must leave the pressure ladder in one of two valid states:

1. pressure is normal / no continuation required; or
2. sustained pressure can continue from fresh current candidates.

Do not reclaim using stale captured facts. Do not precompute a batch. Do not introduce a second pressure/lifecycle writer.

The exact-head `isPlaying == true` path already marks media protection and schedules a pressure continuation; preserve that behavior. Add regression specifically proving that a stale async plan callback cannot strand another eligible Automatic Runtime.

### C — Deterministic lifecycle-time tests

Policy V7 requires lifecycle-stage tests to inject time instead of sleeping in wall/real time.

Add the smallest bounded monotonic-time/test-scheduling seam owned by `SlotLifecycleCoordinator` that allows deterministic testing of:

```text
RECENT (<30s)
→ IDLE (>=30s)
→ LONG_IDLE (>=600s)
```

Production defaults must still use monotonic system uptime and normal main-queue scheduling. Test-only/fake time must not become persisted product state or a second policy source.

Required result:

- no real-time sleep is required to prove RECENT → IDLE → LONG_IDLE stage boundaries;
- stale timer/token behavior remains deterministic;
- production timing values and policy are unchanged.

The concrete seam is an implementation choice. Prefer dependency injection over new public API or test-only mutation of private state.

## Frozen product policy / regression boundary

Preserve all Policy V7 decisions:

- no fixed normal resident count;
- Keep Loaded / Pinned = no FloatTabs automatic exit under normal/warning/critical;
- Automatic RECENT `<30s`, IDLE `30s..<600s`, LONG_IDLE `>=600s`;
- warning excludes RECENT;
- critical may bypass RECENT for inactive unprotected Automatic only;
- progressive oldest-first fresh-fact reclaim;
- pressure normalization cancels pending continuation;
- SlotLifecycleCoordinator remains sole lifecycle writer;
- exact plan token + Runtime identity safety;
- WP1 cold presentation/readiness and A→B→A correctness;
- generation/Attention/media/fullscreen/supplemental visibility protection;
- notification exact-Slot/privacy behavior;
- Browser Profile/login/cookie/session/conversation data safety.

## Explicitly forbidden

- replacing removed target=2 with any other fixed Runtime count;
- changing 30s/600s product values as part of this corrective;
- automatic reclaim of Keep Loaded;
- using stale async media facts to reclaim;
- batch/purge pressure logic;
- second lifecycle/presentation writer;
- private WebKit SPI/helper killing;
- reload/reset/restart workaround;
- clearing Browser Profile/session/login/cookies/cache/conversation data;
- weakening QA workflow/toolchain to make the hosted build green;
- WP3/WP4 mutation.

## Required focused regressions

At minimum add/retain proofs for:

1. hosted-Release-compatible stage diagnostic computation;
2. media-playing candidate under pressure remains protected while another eligible Automatic candidate can progress;
3. stale async media callback re-enters fresh pressure selection under sustained pressure;
4. pressure normalization during async evaluation does not restart reclaim;
5. exact evaluation token prevents foreign/old callback mutation;
6. RECENT → IDLE → LONG_IDLE boundaries use injected monotonic time, not real sleeping;
7. reactivation/stale plan timer cannot reclaim current Runtime;
8. five resident Automatic Runtime are not count-evicted under normal pressure;
9. Keep Loaded remains unreclaimed under warning and critical;
10. WP1 presentation/A→B→A/focus/unread/notification regressions remain green;
11. generation/media/fullscreen protections remain green.

## Verification gate

After corrective implementation:

- focused lifecycle/cross-feature/pool/WP1/notification/diagnostic/privacy suites;
- full XCTest;
- Debug arm64;
- Release arm64;
- native arm64 verification;
- package-lock check;
- push exact branch head and verify remote delivery;
- exact-head self-hosted macOS CI;
- exact-head hosted QA DMG;
- fresh independent exact-diff / ownership / data-safety audit.

Only if all required machine gates and the independent audit PASS may the task move to `HUMAN_UI_ACCEPTANCE=PENDING / USER_OWNED`.

## STOP conditions

Stop if the corrective requires a policy redesign, another lifecycle writer, Keep Loaded reclaim, stale-fact reclaim, real-time-only stage verification, WP1 regression, generation/media/fullscreen regression, Browser Profile/session mutation, private SPI/helper kill/reload-reset workaround, or any required exact-head machine gate failure attributable to the corrective.

## Return contract

Return verified values for:

```text
BASELINE_IDENTITY
CORRECTIVE_BASE_HEAD
FINAL_BRANCH_HEAD
CHANGED_FILES
REMOTE_DELIVERY
HOSTED_RELEASE_COMPATIBILITY_RESULT
ASYNC_PRESSURE_STALE_PLAN_RESULT
MEDIA_PROTECTED_PRESSURE_PROGRESSION_RESULT
PRESSURE_NORMALIZATION_DURING_ASYNC_RESULT
EVALUATION_TOKEN_ISOLATION_RESULT
INJECTED_TIME_MODEL
RECENT_IDLE_LONG_IDLE_DETERMINISTIC_RESULT
STALE_TIMER_RESULT
FIXED_RESIDENT_COUNT_REGRESSION
PINNED_WARNING_CRITICAL_REGRESSION
WP1_PRESENTATION_REGRESSION
WP1_A_B_A_REGRESSION
NOTIFICATION_REGRESSION
GENERATION_PROTECTION_REGRESSION
DATA_SAFETY_RESULT
FOCUSED_TESTS
FULL_XCTEST
DEBUG_BUILD
RELEASE_BUILD
ARM64_VERIFICATION
PACKAGE_LOCK
CI_STATE
QA_DMG_STATE
INDEPENDENT_AUDIT
HUMAN_UI_ACCEPTANCE=PENDING
WP3_SCHEDULING_MUTATION=NOT_STARTED
WP4_OTHER_MUTATION=NOT_STARTED
PR_STATE
```

Do not merge PR #195. Do not release.