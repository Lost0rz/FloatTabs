# FloatTabs Current Task

**Task ID:** FT-LIFECYCLE-001
**Title:** Warm Memory-Warning Residency Corrective
**Status:** `ROOT_CAUSE_CONFIRMED — CORRECTIVE_IMPLEMENTATION_AUTHORIZED`
**Mode:** `TEST_DRIVEN_CORRECTIVE`

## Objective

Correct the confirmed Warm QA failure without reopening unrelated lifecycle areas.

Confirmed incident:

- Warm setting: `1800` seconds / 30 minutes;
- Warm inactive plan start: `2026-10-07T14:58:08Z`;
- memory-pressure warning: `2026-10-07T15:00:02Z`, sequence 454;
- release of the same Warm plan: `2026-10-07T15:00:02Z`, sequence 456;
- elapsed inactive lifetime: about 114 seconds;
- root-cause class: `MEMORY_PRESSURE_RELEASE`.

## Product contract

Warm retention must have stable user-visible meaning:

```text
ordinary inactivity            -> configured Warm TTL applies
memory pressure warning        -> observe/diagnose only; do not evict Warm before TTL
memory pressure critical       -> may evict inactive eligible Warm before TTL
```

Existing media, attention, and speech protection exclusions remain in force. Hot recovery behavior from the first corrective remains unchanged. Cold behavior remains unchanged. Unread/red-dot behavior remains outside this PR.

## Repository authority

- Base branch: `main`
- Accepted base: `569e43783a98c8caca681ce8139ec87dd4fa276e`
- Task branch: `fix/residency-lifecycle-semantics`
- PR: `#116` (Draft; merge blocked)
- Root-cause attribution head: `ff2cef575f6f7818e230b7568da319ebc40eb7f1`
- PR #102 remains unrelated and must not change

## Gate 0 — freshness

Before product changes:

1. fetch/prune;
2. require the task worktree to be clean;
3. require local task branch to fast-forward only to the latest remote task head;
4. reread `AGENTS.md`, `CURRENT_STATUS.md`, and this file;
5. STOP on unexplained head/worktree drift.

## Gate 1 — RED first

Add/modify focused lifecycle tests before production code.

Required RED behavior against the current production implementation:

1. create multiple inactive eligible Warm runtimes with a long Warm TTL;
2. send `.warning` memory pressure;
3. assert every eligible Warm runtime remains resident and its inactive plan remains valid;
4. this test must fail against the current warning-eviction implementation.

Also retain/confirm tests proving:

- `.critical` memory pressure releases inactive eligible Warm runtime(s) before TTL;
- media/attention/speech-protected Warm runtimes remain protected under critical pressure;
- three-or-more Warm runtimes remain resident before configured TTL during ordinary operation.

If the warning RED does not fail for the expected reason, STOP.

## Gate 2 — minimal production corrective

In `SlotLifecycleCoordinator`:

- keep the existing memory-pressure source and `slot_lifecycle.memory_pressure` diagnostic event;
- `.warning` must not call Warm eviction/release logic;
- `.critical` keeps the existing emergency Warm eviction behavior;
- do not add a second residency authority, timer, keepalive loop, or new diagnostics system;
- do not change Hot, Cold, media, attention, speech, or unread logic.

The existing `warmMemoryPressureTarget` implementation detail may be simplified only if required by compilation/tests; avoid unrelated refactoring.

## Gate 3 — wording

Update existing Settings/README/product lifecycle wording so it no longer says generic memory pressure may shorten Warm retention. The contract must state that **critical memory pressure** may shorten Warm retention.

Do not redesign Settings UI.

## Gate 4 — validation

Run focused tests covering:

- warning preserves eligible Warm runtimes;
- critical releases eligible inactive Warm;
- critical preserves protected Warm runtimes;
- ordinary >2 Warm retention before TTL;
- existing Hot recovery policy regression;
- Cold lifecycle regression.

Then run:

- full XCTest suite;
- Debug build;
- Release build;
- verify Release architecture `arm64`.

No QA reinstall in this implementation pass.

## Gate 5 — handoff

Commit only task-relevant production/test/documentation changes and control handoff updates. Push normally to the task branch.

Stop at:

`FINAL_STATE=WAITING_FOR_INDEPENDENT_WEB_AUDIT`

## Not authorized

```ini
UNREAD_BADGE_CHANGE=NO
NEW_DIAGNOSTICS_SYSTEM=NO
PROVIDER_KEEPALIVE=NO
COLD_SEMANTICS_CHANGE=NO
SPEECH_CHANGE=NO
ATTENTION_AUTHORITY_CHANGE=NO
PR102_CHANGE=NO
DIRECT_PUSH_TO_MAIN=NO
MERGE=NO
RELEASE=NO
QA_REINSTALL=NO
```

## Required receipt

```yaml
TASK_ID: FT-LIFECYCLE-001
START_HEAD:
FINAL_HEAD:
REMOTE_HEAD:
LOCAL_REMOTE_MATCH:
WARNING_RED_PROVEN:
WARNING_PRESERVES_WARM:
CRITICAL_EVICTION_PRESERVED:
PROTECTION_BEHAVIOR_PRESERVED:
WARM_GT_2_PRE_TTL:
HOT_REGRESSION:
COLD_REGRESSION:
FOCUSED_TESTS:
FULL_TEST_SUITE:
DEBUG_BUILD:
RELEASE_BUILD:
RELEASE_ARCH:
CHANGED_FILES:
PR102_UNCHANGED:
WORKING_TREE:
FINAL_STATE: WAITING_FOR_INDEPENDENT_WEB_AUDIT
```
