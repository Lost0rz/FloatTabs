# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual refs. Refresh before any PR or merge action.

## Mode

**MODE: ROOT_CAUSE_CONFIRMED — WARM_MEMORY_WARNING_CORRECTIVE_AUTHORIZED**

## Production authority

- Live accepted `main`: `569e43783a98c8caca681ce8139ec87dd4fa276e`
- Active branch: `fix/residency-lifecycle-semantics`
- PR: `#116` (Draft; merge blocked until corrective QA passes)
- Task: `FT-LIFECYCLE-001`
- First product implementation: `9acd6303` (`Fix residency lifecycle semantics`)
- QA-installed source head: `733f73fad9a955db42401abaececf9c7aeb783dc`
- Root-cause attribution control head: `ff2cef575f6f7818e230b7568da319ebc40eb7f1`
- PR #102 remains unrelated MemoX Draft work and is excluded from this task

## Accepted implementation facts

The first lifecycle corrective remains valid in two respects:

1. ordinary two-Warm LRU eviction was removed from the normal inactive path;
2. inactive Hot WebContent recovery is residency-aware and uses the existing recovery request path without selecting/presenting/focusing the Hot Tab.

Unread/red-dot behavior remains outside this PR.

## Human QA failure and confirmed root cause

Human QA used four Warm Tabs with Warm retention set to 30 minutes. One Warm runtime became nonresident and reloaded on selection.

Machine-local attribution confirmed:

- stored Warm retention was exactly `1800` seconds (`30 minutes`);
- the affected Warm inactive plan began at `2026-10-07T14:58:08Z`;
- `slot_lifecycle.memory_pressure` level `warning` occurred at `15:00:02Z`, sequence 454;
- the same Warm plan was released at `15:00:02Z`, sequence 456;
- plan lifetime was about 114 seconds, far below the configured 1800-second TTL;
- this QA window contained one lifecycle release.

**Root cause:** `MEMORY_PRESSURE_RELEASE` caused by the existing warning-level Warm eviction policy.

Current production logic intentionally evicts inactive eligible Warm runtimes on `.warning`, reducing them toward one resident Warm. That behavior makes the user-selected Warm retention value unreliable under a non-critical memory-pressure warning.

## Product decision

Warm retention is now defined as a user-visible residency guarantee with one explicit emergency exception:

- ordinary inactivity: configured 2/5/10/30-minute Warm TTL applies;
- macOS memory-pressure **warning**: record/observe the warning but do **not** proactively release Warm runtimes before their TTL;
- macOS memory-pressure **critical**: may proactively release inactive, eligible Warm runtimes before TTL as an emergency safety valve;
- existing media / attention / speech protections remain unchanged;
- Hot semantics from the first corrective remain unchanged;
- Cold semantics remain unchanged.

This preserves a meaningful Warm setting while retaining a response to truly critical memory pressure.

## Next action

Implement the smallest test-driven corrective on PR #116:

1. prove RED that warning-level pressure currently releases an inactive eligible Warm before TTL;
2. change warning handling to diagnostic-only/no Warm eviction;
3. preserve critical-level Warm eviction and all existing protection exclusions;
4. update existing lifecycle tests and Settings/product wording to say that only **critical** memory pressure may shorten Warm retention;
5. run focused lifecycle tests, full XCTest, Debug/Release arm64 builds;
6. stop for independent Web audit before reinstalling QA.

Do not modify unread/red-dot behavior, speech, Cold semantics, PR #102, main, or release state.
