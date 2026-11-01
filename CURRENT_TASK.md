# FloatTabs Current Task

**Task ID:** `FT-RUNTIME-LIFECYCLE-MEMORY-001`  
**Title:** Runtime Lifecycle / Memory redesign — Phase 4 reference-derived automatic Runtime management  
**Status:** `ACTIVE / PHASE 4 IMPLEMENTATION AUTHORIZED — RECONCILED`  
**Mode:** `EXECUTE`  
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

## Reference-derived mechanism

Use mature Chromium lifecycle principles as mechanism reference, adapted to FloatTabs ownership:

1. protect foreground/selected work;
2. protect explicit pinning and active media/work;
3. rank inactive discard candidates by importance/recency;
4. reclaim proactively before the system becomes unusable;
5. react more aggressively to critical memory pressure;
6. restore/materialize discarded content on activation;
7. do not make persistence/session deletion part of Runtime reclamation.

Do not copy Chromium renderer/process architecture or private APIs.

## Required FloatTabs semantics

### Ownership

```text
read-only resident/protection/recency facts
→ pure deterministic budget decision
→ SlotLifecycleCoordinator sole executor
→ existing WebViewPool hibernate boundary
```

No second Runtime lifecycle writer.

### Managed target

Initial normal managed target: **3 resident Warm/Cold runtimes**.

This value is a conservative product default for the current Web App switcher and is explicitly **not empirical truth**. It may be tuned later without changing the ownership model.

- normal: target 3;
- warning memory pressure: enforce/evaluate target 3, no invented tighter threshold;
- critical memory pressure: target 0 for eligible inactive Warm/Cold runtimes.

### Ranking

When managed resident count exceeds the target, evict eligible inactive candidates in this exact order:

```text
Cold before Warm
→ older lastUsedAt before newer
→ UUID lexical tie-break
```

### Hard protection

Never budget-evict:

- active / actually presented Slot;
- fullscreen source;
- supplemental visible surface;
- media-protected Runtime;
- Attention `generating` Runtime;
- Hot residency policy.

These do not protect Runtime:

- Attention `ready`;
- durable unread;
- native notification presence.

If protected/Hot runtimes exceed the managed target, report oversubscription and keep them resident.

### Timers

Existing Warm/Cold timers remain maximum normal retention boundaries. Automatic budget enforcement may reclaim eligible inactive Warm/Cold earlier.

### Data safety

Do not modify Browser Profile datastore/session semantics, cookies, website data, Slot/Profile persistence schema, or use reset/delete as ordinary reclamation.

## Authorized source scope

Preferred minimal implementation:

- `FloatTabs/Web/SlotLifecycleCoordinator.swift`;
- `FloatTabs/Tabs/WebAppProfile.swift` for truthful user-facing residency copy if needed;
- adjacent composition/UI copy only when required to keep behavior truthful.

A separate policy file may be added only if it materially improves ownership clarity. `WebViewPool.swift` hibernate/restore semantics are not authorized to change unless implementation proves the current mechanism insufficient, in which case STOP/reconcile.

## Verification / merge gate

The user has deferred Phase 4 empirical tuning tests. Do not create the previous benchmark harness as a blocker.

Before merge still require:

- static/diff review for ownership and data safety;
- existing repository-required `Build & Test (Apple Silicon arm64)` on `macmini-floattabs-01` for the literal PR head;
- PR mergeable / no required host blocker.

No additional Phase 4 tuning benchmark, human UI acceptance, release, or version bump is required in this task.

## STOP conditions

STOP/reconcile if implementation would require:

- a second Runtime lifecycle writer;
- automatic Hot eviction;
- eviction of visible/fullscreen/media/generating Runtime;
- `WebViewPool` contract redesign;
- persistence/session/schema changes;
- private WebKit API;
- user-data deletion/reset;
- Phase 5/6 work.

## Delivery boundary

Implement on one branch, push one Phase 4 implementation PR, let required repository CI run, and stop at:

`WAITING_FOR_PHASE_4_MERGE_GATE`

Do not merge, release, bump version or begin Phase 5.