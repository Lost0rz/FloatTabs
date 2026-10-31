# FloatTabs Current Status

**Status date:** `2026-10-31`
**Repository:** `Lost0rz/FloatTabs`
**Default branch:** `main`

## Mode

**MODE: JSC / WEBCONTENT GENERATION-TIME DIAGNOSTIC JS EXPERIMENT / WAITING FOR AIR SOAK**

Current task: `FT-JSC-MULTI-RUNTIME-002` — `ACTIVE / AIR SOAK READY`.

PR #162 remains open / draft / unmerged. JSC exact trigger and root cause remain unknown.

## Canonical / active state

```text
MAIN=26c81d83d3bdd771e98e355337b78622e2b25b17
ACTIVE_BRANCH=codex/ft-jsc-multi-runtime-002
ACTIVE_PR=#162 OPEN / DRAFT / UNMERGED
LAST_PRODUCT_HEAD=cddcbbff2b5471357688a92cb74e4bf4ac5f0021
WARNING_PRESSURE_IMPLEMENTATION=3dff7e90d23918e69e12d2820ce6c1be31805e99
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
JSC_ROOT_CAUSE=UNKNOWN
```

## Warning-pressure corrective result

The exact Air-soak artifact was:

```text
SOURCE_REVISION=b878dd7bfb9b3e437bcb96106cd6682f171c61fd
SOURCE_REVISION_EXACT=true
DMG_SHA256=dd94f546e333f9390687a2d530902b711b921337e6abbcd62dd58918de1cf641
VERSION=0.5.8
BUILD=26
ARCH=arm64
SESSION_ID=74D9AE04-8C8D-4844-A7DC-7C33C6E37A91
```

The warning-pressure intervention worked as designed:

```text
MEMORY_WARNING_COUNT=5
WARNING_DRIVEN_WARM_RELEASE_COMPLETED=8
FIRST_WARNING_RESIDENT_SLOT_COUNT=5
NEXT_WARNING_RESIDENT_SLOT_COUNT=3
ACTIVE_VISIBLE_HOT_PROTECTED_RELEASE=0
CONFIRMED_POST_FINISH_STALL=0
```

The intervention is retained as a useful residency-pressure mitigation. It does not prove memory pressure is the JSC root cause.

One WebContent termination still occurred at `2026-10-31T02:45:15Z`:

```text
slot=1FA8BE8B...
active=true
residency=hot
chatgpt_generating=true
attention_protected=true
resident_attention_generating_count=2
resident_attention_protected_count=2
```

Therefore:

```text
WARNING_PRESSURE_EARLY_WARM_RELEASE_EFFECTIVE=YES
BACKGROUND_WARM_RESIDENCY_REDUCED=YES
WEBCONTENT_CRASH_ELIMINATED=NO
JSC_ROOT_CAUSE=UNKNOWN
```

## New generation-time probe evidence

`SlotNavigationObserver` runs periodic cross-world liveness sampling every 30 seconds. Each sample executes JavaScript in both the main page world and the FloatTabs isolated world.

Recent same-Slot timing evidence:

```text
01:21:14Z cross-world liveness -> 01:21:15Z termination
01:25:16Z cross-world liveness -> 01:25:17Z termination
02:45:13Z cross-world liveness -> 02:45:15Z termination
```

Three of the four most recent measured terminations therefore occurred about 1–2.3 seconds after a same-Slot periodic cross-world liveness sample. This is correlation only. It does not prove the probe caused the JSC crash.

The previous watchdog `2s -> 5s` experiment did not eliminate the crash family, so the attention liveness watchdog itself is not being changed again in this iteration.

## Selected next experiment

```text
INTERVENTION=GENERATING_PERIODIC_CROSS_WORLD_SUPPRESSION
```

While a ChatGPT Slot's canonical Attention state is exactly `generating`, suppress only the timer-driven periodic cross-world liveness sample for that Slot. Resume ordinary periodic sampling when generation ends.

Preserve without semantic change:

- ChatGPT page-owned MutationObserver / bridge generation detection;
- the existing 2-second Attention liveness watchdog and its recovery semantics;
- current-document resync;
- explicit/on-demand renderer or incident probes;
- Attention / Unread / stable response identity;
- Ready Alert and RemoteOrbit focus paths;
- active / visible / Hot residency semantics;
- warning-pressure early Warm release already implemented;
- Browser Profiles, cookies, sessions, Slot configuration, preferences, backups and recovery data.

The periodic navigation observer must not become a second owner of Attention state. Suppression must consume a read-only projection from the canonical `WebAttentionCoordinator` through an existing or minimally injected composition seam.

## Generation-time suppression result

The authorized `GENERATING_PERIODIC_CROSS_WORLD_SUPPRESSION` experiment is implemented and verified on:

```text
IMPLEMENTATION_COMMIT=be95a36467822a22a7d6ad78b9900f50c4ca69ca
VERIFICATION_COMMIT=cddcbbff2b5471357688a92cb74e4bf4ac5f0021
CANONICAL_ATTENTION_OWNER=WebAttentionCoordinator
READ_ONLY_QUERY_PATH=PanelController -> WebViewPool -> SlotNavigationObserver
DUPLICATE_GENERATING_STATE=NO
GENERATING_PERIODIC_MAIN_WORLD_EVALUATIONS=0
GENERATING_PERIODIC_ISOLATED_WORLD_EVALUATIONS=0
GENERATING_PERIODIC_SUPPRESSION_DIAGNOSTIC=YES
GENERATING_EXPLICIT_CAPTURE=PRESERVED
IDLE_PERIODIC_SAMPLE=PASS
READY_PERIODIC_SAMPLE=PASS
GENERATING_TO_IDLE_PERIODIC_RESUME=PASS
NON_CHATGPT_PERIODIC_BEHAVIOR=UNCHANGED
WATCHDOG=2_SECONDS_UNCHANGED
JSC_ROOT_CAUSE=UNKNOWN
```

Focused tests, full XCTest, Debug arm64, Release arm64, exact-head macOS CI, and exact-head QA DMG all passed. The final control-aligned exact-head QA DMG provenance and checksum are returned in the execution receipt.

## Next gate

The single diagnostic-load change is complete. The next gate is user-owned Air soak on the exact-head QA DMG. Production release is not authorized.

Interpretation remains bounded:

```text
FEWER_CRASHES != ROOT_CAUSE_PROVEN
NO_CRASH_DURING_BOUNDED_SOAK != FIX_PROVEN
PROBE_ADJACENCY != PROBE_CAUSALITY
CRASH_AFTER_SUPPRESSION != WEBSITE_ONLY_ROOT_CAUSE_PROVEN
```

Production release is not authorized.

## Separate product follow-up

Active-visible ChatGPT completion currently intentionally suppresses persistent unread/red-dot state. That remains a separate product-semantic task and is not part of this runtime experiment.
