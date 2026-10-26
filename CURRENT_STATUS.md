# FloatTabs Current Status

**Status date:** 2026-10-26
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: ACTIVE ENGINEERING TASK — RUNTIME INCIDENT DIAGNOSTICS**

Active task: `FT-RUNTIME-INCIDENT-DIAGNOSTICS-001`

## Current verified baseline

```text
AUTHORIZED_BASE_MAIN=547fa103536a0e33bdea7aa21c5d5e5faaaf3bb7
PUBLIC_RELEASE=v0.5.7
PUBLIC_BUILD=25
RELEASE_STATE=PUBLISHED / VERIFIED
PREVIOUS_LIFECYCLE_TASK=FT-HISTORICAL-BRANCH-CLEANUP-001 / TERMINAL
```

FloatTabs v0.5.7 / Build 25 remains the current public release. Historical branch/worktree cleanup is closed. No release/version change is authorized by the active diagnostics task.

## Current runtime evidence

The 2026-10-26 v0.5.7 runtime capture shows that the existing diagnostics can identify several failure boundaries but cannot yet prove their code-level cause:

- WebContent process termination occurred repeatedly and recovery completed;
- memory-pressure warnings occurred repeatedly, but public API evidence does not attribute child WebContent memory;
- Attention recorded an isolated liveness timeout/failure while cross-world Web runtime probes remained healthy;
- previous-application restore produced rejected activation requests in observed cases;
- the captured period did not reproduce the historical post-finish dual-world stall;
- page-app counters show substantial accumulated JavaScript/error/drop activity, but the current bounded ring and event-time semantics are insufficient for a definitive incident reconstruction.

Source audit confirms the app already contains bounded renderer, cross-world liveness, ChatGPT health, page-app, lifecycle, presentation and manual stuck-tab snapshot instrumentation. The active task therefore focuses on incident correlation, automatic capture, terminal outcomes, probe correctness and noise reduction rather than creating a new diagnostics platform.

## Active objective

Complete the diagnostic evidence for the known runtime problem classes in one bounded pass so a future real incident can be classified from one exported runtime log without another probe-only release.

The task must preserve current product behavior:

```text
NO_RECOVERY_POLICY_CHANGE=YES
NO_RESIDENCY_POLICY_CHANGE=YES
NO_ATTENTION_BUSINESS_STATE_CHANGE=YES
NO_FOCUS_POLICY_CHANGE=YES
NO_BROWSER_PROFILE_OR_SESSION_RESET=YES
NO_PRIVATE_WEBKIT_PROCESS_ATTRIBUTION=YES
NO_USER_DATA_MUTATION=YES
```

## Planned diagnostic coverage

The active task covers:

1. shared incident IDs and automatic bounded cross-domain snapshots;
2. WebContent termination → recovery disposition → commit → first healthy liveness closure;
3. post-finish/navigation stall trigger and terminal closure evidence;
4. memory-pressure candidate/skip/release reasoning;
5. Attention liveness/resync abnormal-result and late-callback evidence;
6. previous-application restore terminal outcome evidence;
7. page-app recorder age correctness, category-diverse bounded retention and privacy-safe structural classification;
8. redundant healthy/ignore-log noise reduction without reducing actual probe cadence.

Full scope, non-goals, acceptance criteria and gates are authoritative in `CURRENT_TASK.md`.

## Data safety

Browser Profiles, WebKit website data, website sessions/cookies, Slot configuration, preferences, backups and other user data are outside mutation scope. Diagnostics remain content-free and must continue through `RuntimeDiagnosticPrivacy` before persistence.

## Repository lifecycle

- Historical cleanup closeout PR #151: MERGED.
- Canonical main after closeout: `547fa103536a0e33bdea7aa21c5d5e5faaaf3bb7`.
- Active diagnostics authorization is being established through a dedicated control branch/PR before product/test mutation.
- Implementation must use a separate dedicated branch/worktree and remain Draft through final audit.

## Next

Merge the diagnostics authorization control change, then execute `FT-RUNTIME-INCIDENT-DIAGNOSTICS-001` Gate 0 → Gate 5. Do not release under this task.
