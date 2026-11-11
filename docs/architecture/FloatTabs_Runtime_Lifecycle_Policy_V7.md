# FloatTabs Runtime Lifecycle Policy V7 — Staged Automatic Lifecycle

**Status:** ACCEPTED TECHNICAL POLICY / CURRENT APPLICABILITY CHECKED AGAINST SOURCE AND TESTS
**Date:** 2026-11-02
**Baseline:** main@2a52800f770266f7c901eb612a0b319ddca142df
**Scope:** healthy-state Automatic lifecycle and warning/critical reclaim eligibility
**Technical scope:** Automatic lifecycle and reclaim eligibility, separate from restore/presentation, scheduling, and other subsystems.

This document records the bounded FloatTabs Runtime policy and supersedes earlier conflicting Phase 8 fixed-count / Keep Loaded-critical behavior. Restore/presentation readiness remains separately defined by Adaptive Lifecycle Restore Contract V2. Task permission and delivery gates are not defined here.

## 1. Purpose and observed basis

WP1 real-Mac acceptance observed repeated normal reconciliation eviction while three Automatic Runtime instances were in use. The events reported managed_resident_count=3, target=2, and an eviction for reason=reconcile. This is a healthy-state policy defect: resident count alone can cold-restore a Slot that is part of an ordinary working set.

At the WP2 baseline, SlotLifecycleCoordinator contains a fixed normal managed-resident target, count-based budget decisions, an approximately 30-second Automatic release path, progressive pressure reclaim, and a critical-pressure fallback that may reclaim an inactive Keep Loaded Runtime. These are baseline facts, not retained WP2 policy.

The 30-second interval is retained as anti-thrash protection before the IDLE stage. It is no longer a destructive lifetime.

## 2. Authority and ownership

- SlotLifecycleCoordinator is the sole writer of inactivity plans, lifecycle stages, and reclaim decisions.
- WebViewPool remains the mechanism owner for exact Runtime identity and hibernate/release/restore operations. It does not decide policy eligibility.
- PanelController and the accepted WP1 presentation gate continue to own presentation, materialization, and exact-Runtime readiness. WP2 must not bypass or weaken that gate.
- Existing Attention, media, fullscreen, supplemental-visibility, current/visible, and in-flight restore/materialization facts remain the protection authorities. WP2 consumes them; it does not create duplicate protection state.
- Persistent Slot/Profile configuration remains separate from disposable Runtime residency. Diagnostics remain evidence-only.

No second lifecycle writer may be introduced in WebViewPool, PanelController, TabStore, notification code, or diagnostics.

## 3. Retention classes and inactivity stages

### Keep Loaded / Pinned

Keep Loaded is a hard user retention preference against FloatTabs automatic exit:

- no normal long-idle automatic hibernate;
- no warning-pressure reclaim;
- no critical-pressure reclaim;
- no reclaim merely because other Runtime instances exist.

Explicit user actions and explicit configuration/lifecycle changes retain their existing meanings. Termination by macOS outside FloatTabs policy is outside this contract.

### Automatic

Automatic Slots use an in-memory, token-bounded inactivity plan with these initial implementation defaults:

| Stage | Inactive age | Normal-pressure behavior |
| --- | --- | --- |
| RECENT | less than 30s | Keep resident; anti-thrash protection |
| IDLE | at least 30s and less than 600s | Keep resident |
| LONG_IDLE | at least 600s | May hibernate if still inactive and unprotected |

600s / 10 minutes is an initial tunable implementation default, not a permanent product invariant. Tests must inject time rather than wait in real time.

### Plan and timer ownership

For an Automatic Slot:

~~~text
inactive
→ create a new lifecycle plan token
→ RECENT
→ exact-token 30s boundary → IDLE
→ exact-token 600s boundary → LONG_IDLE / normal reclaim eligibility
~~~

The inactivity plan and timers are generation/token bounded. Reactivation, visibility/current ownership, Slot removal, or an identity-invalidating lifecycle change cancels the old plan. Every callback must validate the exact current token and current facts before changing stage or reclaiming. A stale callback is a no-op.

When generation, media, fullscreen, supplemental visibility, or another existing protection ends, SlotLifecycleCoordinator re-evaluates the current inactivity transaction. It invalidates obsolete callbacks and issues a fresh valid token/plan as needed from authoritative current inactivity and protection facts. It must not revive an obsolete timer or reclaim from stale captured facts.

A normal long-idle reclaim is at most once for the exact inactive plan. A later inactivity transaction receives a new token and may become eligible independently.

## 4. Normal-pressure policy

Normal healthy-state residency is independent of Runtime count. Reconcile, activation, deactivation, presentation, or protection events must not evict an otherwise eligible Runtime because N Runtime instances are resident.

- RECENT Automatic stays resident.
- IDLE Automatic stays resident.
- LONG_IDLE Automatic may hibernate only while it remains inactive and unprotected.
- Successful normal long-idle reclaim records release_reason=automatic_long_idle_expired.
- Keep Loaded remains resident under all normal stages.

No count or count-derived substitute may be used as a normal reclaim reason or disguised as a memory estimate.

## 5. Memory-pressure policy

Pressure reclaim is progressive and based on current eligibility, not a precomputed purge set. After each reclaim transaction, re-read the latest pressure state, Runtime identity, inactivity/stage, preference, and protection facts before choosing another candidate. Use the existing WebViewPool reclaim boundary.

### Warning

Eligible candidates are inactive, unprotected Automatic Runtime in IDLE or LONG_IDLE.

RECENT Automatic, Keep Loaded, visible/current or otherwise protected Runtime, generating/Attention-protected Runtime, fullscreen/supplemental-visible Runtime, protected active media, and any existing restore/materialization protection are not eligible.

Reclaim eligible candidates progressively, oldest inactive first, with deterministic tie-breaking. Do not precompute a batch.

### Critical

Critical pressure may bypass the RECENT grace. Eligible candidates are inactive, unprotected Automatic Runtime at any stage. Reclaim progressively, oldest inactive first, and revalidate current facts after every step.

Keep Loaded / Pinned and all hard-protected Runtime are never automatic candidates, including at critical pressure. If only Keep Loaded or hard-protected Runtime remain, FloatTabs stops reclaiming.

### Pressure returns to normal

Cancel any not-yet-started progressive pressure continuation. Do not restore Runtime already reclaimed. Future restoration remains demand-driven through the accepted WP1 presentation/readiness gate.

## 6. Protection and identity invariants

- Generation/Attention protection remains authoritative; a generating Runtime is never reclaimed while protected.
- Existing protected active-media, fullscreen, supplemental-visible, current/visible, and restore/materialization ownership remains intact.
- Protection ending triggers fresh fact evaluation and a valid new plan token when needed.
- A callback from an old inactive token or Runtime generation can never reclaim the current Runtime.
- WP1 cold restore, A→B→A re-entry, focus, unread acknowledgement, notification exact-Slot routing, and readiness behavior remain unchanged.

## 7. Diagnostics and privacy

Remove fixed-target normal-policy truth from Runtime lifecycle diagnostics, including defaultManagedResidentTarget / managedResidentTarget projections and normal target fields. Do not emit a normal reclaim decision whose reason is resident_count > N or an equivalent count condition.

Bounded diagnostic facts may report:

- lifecycle stage transition;
- automatic_long_idle_expired;
- memory_warning / memory_critical;
- an already-useful protection block reason.

Diagnostics do not become a policy writer, a memory estimator, or a source of page content. Do not add page text, URLs, session data, or private WebKit/process attribution.

## 8. Explicit scope boundaries

WP2 may change the lifecycle policy and narrowly necessary diagnostic projection in the existing lifecycle owner and focused tests. It does not change:

- WP1 exact-Runtime presentation/readiness or WebViewPool restore/session mechanics, except call adaptation strictly required by the new lifecycle trigger;
- Browser Profile, login, cookies, website data, cache, or persisted Slot configuration;
- generation detection semantics or Attention ownership;
- notification exact-Slot routing, privacy, or content;
- WebKit inactiveSchedulingPolicy, snapshots, screenshots, or UI information architecture, except an existing label corrected for semantic accuracy;
- aggregate/per-Slot GiB budgeting or Runtime-count-derived RAM estimates;
- WebKit private SPI, helper-process termination, or reload/reset/restart workarounds.

## 9. Product-specific regression matrix

1. Five Automatic resident Runtime under normal pressure: reconcile does not hibernate because of count.
2. Automatic inactive at 29s: remains RECENT and resident.
3. Automatic crosses 30s: becomes IDLE and remains resident under normal pressure.
4. Automatic crosses the long-idle boundary: hibernates exactly once when unprotected.
5. Reactivation before long-idle: stale timer cannot reclaim the reactivated Runtime.
6. Keep Loaded crosses long-idle: remains resident.
7. Warning pressure: only eligible IDLE / LONG_IDLE Automatic candidates reclaim.
8. Warning pressure: RECENT Automatic remains protected.
9. Critical pressure: inactive unprotected Automatic may reclaim while RECENT.
10. Warning and critical: Keep Loaded is never an automatic reclaim candidate.
11. Generating/Attention protection prevents automatic reclaim.
12. Fullscreen, supplemental visibility, and protected media remain protected.
13. Pressure normalization stops pending progressive continuation.
14. Old inactive token cannot reclaim a new/current lifecycle generation.
15. WP1 cold restore, A→B→A, focus, unread, and notification regressions remain green.

## 10. Related product regressions and real-Mac observations

Relevant coverage includes lifecycle suites, `WebAttentionLifecycleTests`, `WebAttentionCrossFeatureTests`, `WebViewPool` reclaim regressions, ExternalShell/restore presentation behavior and affected diagnostic/privacy tests.

Real-Mac observations should cover frequent multi-Slot use, long-idle restore through the exact Runtime readiness boundary, Keep Loaded retention, generation protection, and intact login/session/conversation data.

This section defines product-specific behavior to preserve, **not** an instruction to run the entire XCTest suite or a CI/QA DMG workflow on every change. Task selection, test scope, approval, merge and release are owned outside the product contract.
