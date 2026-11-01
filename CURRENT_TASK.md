# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 4 reference-derived automatic Runtime management  
**Status:** `WAITING_FOR_PHASE_4_MERGE_GATE`  
**Mode:** `VERIFY / MERGE GATE`  
**Task class:** `RUNTIME LIFECYCLE POLICY / REFERENCE-DERIVED DEFAULT`  
**JSC root cause:** `UNKNOWN`

## User-authorized reconciliation

On 2026-11-01 the user explicitly replaced the Phase 4 tuning-first gate with implementation-first sequencing:

```text
mature-browser lifecycle reference
→ conservative FloatTabs default
→ implementation + repository correctness CI
→ merge
→ later empirical tuning if needed
```

Do not require the prior `1 / 2 / 4 / 8` benchmark, drift calculation, candidate tournament, or restore-latency statistics before this Phase 4 implementation/merge. Those are deferred tuning work.

Required CI/data-safety gates remain in force.

## Delivered implementation

Phase 4 implementation is complete on PR #181.

Implementation semantic head:

`ce0231628a976ad41afba1e78ef1b0726212f95e`

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

Normal/warning managed target is **3 resident Warm/Cold runtimes** as an explicitly reference-derived initial product assumption. Critical pressure targets `0` eligible inactive Warm/Cold runtimes.

Hard protection covers active/presented, fullscreen, supplemental-visible, media-playing or media-query-pending, Attention `generating`, and Hot. Ready/unread/native notification do not protect Runtime.

No Browser Profile/session/schema/reset/delete semantics changed.

## Verification evidence

Implementation semantic head passed:

- Debug arm64 build;
- Release arm64 build;
- native arm64 architecture verification;
- full existing XCTest suite;
- required `Build & Test (Apple Silicon arm64)` run `1282` on `macmini-floattabs-01`;
- QA DMG run `621`.

Initial CI found two stale memory-pressure diagnostic assertions; the correction preserved backward-compatible diagnostic naming while retaining the new unified budget behavior. Full XCTest then passed.

A final code audit also caught an async background-media protection race. The implementation now treats the playback-query window as protected, including the timer revalidation path, preventing budget eviction before media state is known.

## Deferred tuning

Not required for this merge:

- Real-Mac `1 / 2 / 4 / 8` matrix;
- no-op drift baseline;
- candidate `4 → 3 → 2` tournament;
- restore/materialization median/p95;
- human performance tuning.

These remain future tuning work and must not be retroactively reported as completed evidence.

## Merge gate

Before merge, confirm against the **literal current PR head**:

1. PR #181 remains open, ready and mergeable;
2. required `Build & Test (Apple Silicon arm64)` is green for the literal head;
3. changed paths remain inside the reconciled Phase 4 scope;
4. no Browser Profile/session/persistence or `WebViewPool` contract mutation was introduced;
5. no release/version/Phase 5 work is present.

This control-alignment commit is control-only drift after the verified implementation semantic head. Branch protection still governs the literal PR head; do not infer the final host gate from the older semantic-head CI.

## STOP conditions

STOP/reconcile if the final merge gate reveals:

- a second Runtime lifecycle writer;
- automatic Hot eviction;
- eviction of visible/fullscreen/media/generating Runtime;
- `WebViewPool` contract redesign;
- persistence/session/schema changes;
- private WebKit API;
- user-data deletion/reset;
- required literal-head CI failure;
- Phase 5/6 work.

## Delivery boundary

The construction phase is complete. Current terminal state is:

`WAITING_FOR_PHASE_4_MERGE_GATE`

Do not merge, release, bump version or begin Phase 5 without the next authorized merge decision.