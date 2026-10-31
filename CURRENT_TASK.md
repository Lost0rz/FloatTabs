# FloatTabs Current Task

**Task ID:** `FT-JSC-MULTI-RUNTIME-002`
**Title:** Test generation-time periodic cross-world diagnostic JS suppression
**Status:** `ACTIVE / AUTHORIZED`
**Mode:** `EXECUTE`
**Task class:** `RUNTIME STABILITY / EVIDENCE-DRIVEN CORRECTIVE`
**Authorized product baseline:** `codex/ft-jsc-multi-runtime-002@b878dd7bfb9b3e437bcb96106cd6682f171c61fd`
**Active PR:** `#162` / `codex/ft-jsc-multi-runtime-002`
**JSC root cause:** `UNKNOWN`

## Purpose

Test one new, bounded hypothesis: whether FloatTabs' timer-driven cross-world diagnostic JavaScript sampling during active ChatGPT generation is a crash amplifier.

Suppress only that periodic diagnostic sampling while the canonical Attention state for the Slot is exactly `generating`, then produce a fresh exact-head QA DMG and repeat Air soak.

This task does not claim that cross-world probing, concurrent generation, memory pressure, Attention protection, or FloatTabs is the proven JSC root cause.

## Reconciliation from the previous iteration

The previous authorized intervention `WARNING_PRESSURE_EARLY_WARM_RELEASE` is complete and remains part of the branch. Its Air soak proved that warning-time early release safely reduces unnecessary inactive Warm residency:

```text
MEMORY_WARNING_COUNT=5
WARNING_DRIVEN_WARM_RELEASE_COMPLETED=8
FIRST_WARNING_RESIDENT_SLOT_COUNT=5
NEXT_WARNING_RESIDENT_SLOT_COUNT=3
ACTIVE_VISIBLE_HOT_PROTECTED_RELEASE=0
```

One active Hot ChatGPT WebContent still terminated while generating with two resident generating/protected Slots. Therefore the memory-pressure intervention is useful but not sufficient to eliminate the crash family.

User authorization on 2026-10-31 explicitly requested the next detailed plan and construction card. This reconciles the previous STOP boundary that prohibited automatically adding a second speculative mitigation.

## Evidence for the next experiment

`SlotNavigationObserver` currently runs periodic cross-world liveness sampling every 30 seconds. One periodic cycle evaluates JavaScript in:

```text
main page world
FloatTabs isolated world
```

Recent same-Slot timing observations:

```text
01:21:14Z cross-world liveness -> 01:21:15Z WebContent termination
01:25:16Z cross-world liveness -> 01:25:17Z WebContent termination
02:45:13Z cross-world liveness -> 02:45:15Z WebContent termination
```

Three of the four most recent measured terminations therefore occurred about 1–2.3 seconds after a same-Slot periodic cross-world sample. This is only a temporal correlation.

The earlier Attention watchdog `2s -> 5s` experiment did not eliminate the crash family, so do not repeat that change here.

## Selected design

### Canonical ownership

`WebAttentionCoordinator` remains the sole authoritative owner of `idle / generating / ready` state.

`SlotNavigationObserver` must not infer, retain, duplicate, or transition Attention state. It may consume only a read-only suppression decision projected from the canonical Attention owner through an existing or minimally injected composition seam.

### Authorized intervention — exactly one

Implement:

```text
GENERATING_PERIODIC_CROSS_WORLD_SUPPRESSION
```

For a ChatGPT Slot only, when the canonical Attention state is exactly `generating`:

- skip the **timer-driven periodic** cross-world liveness cycle before any main-world or isolated-world JavaScript evaluation begins;
- record a native diagnostic explaining that the periodic cycle was suppressed because the Slot was generating;
- do not synthesize a liveness result from the skipped sample;
- resume ordinary periodic sampling on later timer ticks after the Slot leaves `generating`.

### Explicitly preserved

Do not alter:

- ChatGPT page-owned MutationObserver / bridge generation observation;
- the existing 2-second Attention liveness watchdog;
- current-document resync;
- generation/Attention/Unread state transitions;
- explicit/on-demand `captureCrossWorldLivenessOnce()` calls used by incident/recovery evidence;
- renderer probes and incident health/page-app probes;
- navigation recovery semantics;
- warning-pressure early Warm release from the prior iteration;
- active / visible / Hot / media / Attention residency protection;
- Ready Alert;
- RemoteOrbit external voice focus;
- Browser Profile / cookies / sessions / website data / Slot config / preferences / backups / recovery data;
- active-visible completion red-dot semantics.

### Suppression semantics

The suppression condition must be exact:

```text
supported ChatGPT Slot
AND canonical attention state == generating
AND invocation source == periodic timer
```

Do not suppress because a Slot is merely Attention-protected or `ready`.

If Attention state is unknown/not represented, do not guess `generating`; run the existing periodic sample.

The explicit/on-demand capture path must remain available even while generating so incident/recovery diagnostics are not blinded.

## Diagnostics

Add only the evidence needed for the experiment.

At minimum, a skipped periodic cycle must identify:

```text
slot_id
reason=chatgpt_generating
sample_source=periodic
js_evaluation_started=false
```

Prefer one event such as:

```text
web_runtime.cross_world_liveness_suppressed
```

Do not log page content.

Existing successful `web_runtime.cross_world_liveness` events remain unchanged when a sample actually runs.

## Implementation boundary

Prefer the smallest wiring that preserves ownership. A valid implementation may add a read-only query/callback from the composition owner into `WebViewPool` / `SlotNavigationObserver`, but must not create a second generating-ID set or a second Attention state machine.

Before mutation, the local executor must inspect the current construction/wiring path and confirm the chosen seam preserves canonical ownership.

If implementing suppression requires WebView ownership redesign, process-pool/data-store redesign, duplicated Attention state, or broad scheduler replacement, STOP instead of expanding scope.

## Required focused tests

At minimum cover:

1. periodic cycle + ChatGPT + `generating` => no main-world evaluator call and no isolated-world evaluator call;
2. suppression diagnostic is emitted with `reason=chatgpt_generating` and `sample_source=periodic`;
3. state `idle` => existing periodic cross-world sample still runs;
4. state `ready` => existing periodic cross-world sample still runs;
5. transition `generating -> idle` => later periodic tick resumes sampling without rebuild/reload;
6. explicit/on-demand cross-world capture still runs while generating;
7. non-ChatGPT runtime behavior is unchanged;
8. warning-pressure early Warm release regression remains green;
9. Attention generation/Ready/Unread regression coverage remains green.

## Verification gate

Before new Air soak:

1. focused tests pass;
2. full required XCTest passes;
3. Debug arm64 build passes;
4. Release arm64 build passes;
5. branch is pushed to PR #162 and remote exact head is verified;
6. exact-head CI and QA DMG workflows pass;
7. local exact-head QA DMG is produced with:
   - source revision equal to final remote branch head;
   - `FloatTabsSourceRevisionExact=true`;
   - arm64 architecture;
   - SHA256;
   - `hdiutil verify` PASS.

## Air soak comparison

The next Air soak must record:

```text
periodic cross-world suppression count
periodic cross-world successful sample count
whether any generating Slot still receives timer-driven cross-world JS
resident_attention_generating_count at each termination
resident_attention_protected_count at each termination
memory warning count
warning-driven Warm release count
resident_slot_count around warnings
WebContent termination count / timing
same-Slot timing relative to the last actual cross-world sample
clustered different-Slot termination timing
confirmed post-finish stall count
```

The key experiment assertion is:

```text
WHILE_GENERATING_PERIODIC_CROSS_WORLD_JS=0
```

for timer-driven samples only.

## Interpretation rules

```text
FEWER_CRASHES != ROOT_CAUSE_PROVEN
NO_CRASH_DURING_BOUNDED_SOAK != FIX_PROVEN
PROBE_ADJACENCY != PROBE_CAUSALITY
CRASH_AFTER_SUPPRESSION != WEBSITE_ONLY_ROOT_CAUSE_PROVEN
WARNING_RELEASE_SUCCESS != MEMORY_ROOT_CAUSE
```

## STOP conditions

STOP and report rather than broaden scope if:

- suppression cannot be implemented without duplicating Attention state ownership;
- product correctness would require disabling the page-owned generation observer or the Attention liveness watchdog;
- explicit/on-demand incident capture would have to be disabled;
- implementation requires reload/restart/reset as mitigation;
- implementation requires Browser Profile/session/user-data mutation;
- implementation requires WebView/process-pool/data-store ownership redesign;
- focused/full tests or required builds fail because of the change;
- a second behavioral mitigation would be required in the same iteration.

## Completion boundary

This iteration reaches `AIR_SOAK_READY` only after the single periodic-cross-world suppression experiment is implemented, verified, pushed, and tied to a fresh exact-head QA DMG.

Production release and merge are not authorized in this iteration.

## Separate follow-up not authorized here

Active-visible ChatGPT completion currently suppresses persistent unread/red-dot state. That remains a separate product task and must not be mixed into this runtime experiment.
