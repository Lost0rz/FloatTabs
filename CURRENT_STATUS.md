# FloatTabs Current Status

**Status date:** 2026-10-07
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Validity

`CURRENT_STATUS.md` defines intended project state; live Git/GitHub refs define actual refs. Refresh before any PR or merge action.

## Mode

**MODE: QA_ACCEPTANCE_FAILED — WARM_PREMATURE_RELEASE_ATTRIBUTION**

## Production authority

- Live accepted `main`: `569e43783a98c8caca681ce8139ec87dd4fa276e`
- Active branch: `fix/residency-lifecycle-semantics`
- PR: `#116` (Draft; merge blocked)
- Task: `FT-LIFECYCLE-001`
- Product implementation commit: `9acd6303` (`Fix residency lifecycle semantics`)
- Independently audited implementation handoff: `94aa9bf1633ccff427d49db09e42e540b65b760e`
- QA-installed source head: `733f73fad9a955db42401abaececf9c7aeb783dc`
- QA app: `0.5.2 (20)`, arm64
- PR #102 remains unrelated MemoX Draft work and is excluded from this task

## Accepted implementation facts

The first lifecycle corrective remains code-audited as implemented:

1. ordinary two-Warm LRU eviction was removed from the normal inactive path;
2. inactive Hot WebContent recovery is residency-aware and uses the existing recovery request path;
3. no second residency authority was introduced;
4. no unread/speech/Cold product behavior was intentionally changed.

These facts are not sufficient for merge because human Warm acceptance failed.

## Human QA failure

On the QA build from `733f73f...`, the user configured four Tabs as Warm with Warm retention selected as 30 minutes. After some ordinary use, one Warm Tab's icon became gray and clicking it recreated/reloaded the runtime.

The tab-rail gray/released presentation is driven by runtime residency (`isResident == false`), so this is evidence that the `WKWebView` runtime was actually released, not merely that a live resident renderer stalled.

**Verdict:** `WARM_HUMAN_ACCEPTANCE=FAIL`.

Therefore the earlier conclusion that removing only the ordinary two-Warm LRU fully solved the user-visible Warm issue is rejected. PR #116 must not merge in its present state.

## Current attribution boundary

Root cause of this fresh QA failure is not yet confirmed. Existing code provides three relevant hypotheses that must be distinguished with existing machine-local evidence:

1. **Memory-pressure eviction:** production still listens to macOS memory pressure. Warning may reduce inactive eligible Warm runtimes toward one; critical may reduce them to zero, bypassing the configured TTL.
2. **Effective preference mismatch:** the repository maps 30 minutes to 1800 seconds, but the live stored UserDefaults value must be verified on the QA machine.
3. **Another explicit release/timer path:** an existing lifecycle release may have fired independently of the removed count-based LRU.

Do not infer memory pressure solely from the symptom. Use the existing runtime diagnostic journal to attribute the actual incident.

## Existing evidence sources

Runtime diagnostics are already written under:

`~/Library/Application Support/FloatTabs/Diagnostics/Logs/runtime-YYYYMMDD-NNN.jsonl`

Relevant existing events include:

- `slot_lifecycle.memory_pressure`
- `slot_lifecycle.release`

No new diagnostics are authorized before checking this incident.

## Next action

Perform one read-only machine-local attribution pass against the currently installed QA incident:

- verify raw stored `FloatTabs.performance.warmWebViewRetentionDelay`;
- inspect existing runtime diagnostics around the release for `slot_lifecycle.memory_pressure` and `slot_lifecycle.release`;
- determine whether the release aligns with memory pressure, a normal TTL timer, or another existing path;
- do not reproduce, modify code/tests, clear logs/data, reinstall, merge, or test Hot until this Warm incident is attributed.

Unread/red-dot behavior remains a separate deferred concern.
