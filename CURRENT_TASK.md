# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 4 reference-derived automatic Runtime management  
**Status:** `COMPLETE / MERGED`  
**Mode:** `CLOSEOUT`  
**Task class:** `RUNTIME LIFECYCLE POLICY / REFERENCE-DERIVED DEFAULT`  
**JSC root cause:** `UNKNOWN`

## Delivered outcome

Phase 4 is complete and merged.

```text
PR=#181
FINAL_PR_HEAD=70584485b7a0444aba3df0ea5e4613681b6e5a14
MERGE_COMMIT=c910441a954bddbaeca710395cd0d6ed89ec5e5c
REQUIRED_BUILD_AND_TEST=PASS / RUN 1283
QA_DMG=PASS / RUN 622
```

Delivered mechanism:

```text
resident/protection/recency facts
→ deterministic runtime-budget decision
→ Cold before Warm
→ LRU lastUsedAt
→ UUID deterministic tie-break
→ SlotLifecycleCoordinator sole executor
→ existing WebViewPool hibernate/restore boundary
```

Normal/warning managed target currently defaults to **3 resident Warm/Cold runtimes** as an explicitly reference-derived initial product assumption. Critical pressure targets `0` eligible inactive Warm/Cold runtimes.

Hard protection covers active/presented, fullscreen, supplemental-visible, media-playing, media-query-pending, Attention `generating`, and Hot. Ready/unread/native notification do not protect Runtime.

No Browser Profile/session/schema/reset/delete semantics changed.

## Verification

Final literal PR head passed:

- Debug arm64 build;
- Release arm64 build;
- native arm64 architecture verification;
- full existing XCTest suite;
- required `Build & Test (Apple Silicon arm64)` run `1283` on `macmini-floattabs-01`;
- QA DMG run `622`.

## Deferred tuning

Not completed or required in this task:

- Real-Mac `1 / 2 / 4 / 8` matrix;
- no-op drift baseline;
- candidate `4 → 3 → 2` tournament;
- restore/materialization median/p95;
- machine-specific performance tuning.

Future tuning direction accepted for later design: prefer a Settings-backed configuration surface with conservative defaults and per-machine/user adjustment rather than permanently hard-coding one universal performance threshold.

The exact Settings UI, allowed ranges/presets, migration/persistence behavior and any automatic machine-class policy are **not authorized in this task** and require a new design/implementation scope.

Safety protections must remain outside unsafe user override: Hot, active/presented, fullscreen, media-protected and Attention `generating` Runtime may not become automatic-eviction candidates through tuning settings.

## Delivery boundary

This task is closed at:

`COMPLETE / MERGED`

Do not begin Phase 5/6, release/version work, or performance-settings implementation without the next authorized task.
