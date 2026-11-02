# FloatTabs Adaptive Lifecycle + Restore Performance Contract V1

**Status:** `ACCEPTED / FROZEN FOR WP0 EVIDENCE GATE`  
**Task:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Date:** `2026-11-02`  
**Baseline:** `main@7e179aaf4dbf0c538c7c2221101fc74d16e49b98`  
**Scope:** restore latency, healthy-state Runtime retention, background Runtime efficiency  
**Mutation state:** `WP0 ONLY / PRODUCT POLICY MUTATION NOT YET AUTHORIZED`

## 1. Why this contract exists

The delivered lifecycle architecture is functionally correct but the current healthy-state policy is still too coarse for the product objective.

Real-Mac acceptance after PR #193 proved all of the following:

- a hidden ChatGPT generation can continue for roughly 1m20s and complete;
- generating Attention protection prevents premature Runtime reclaim;
- a completed hidden Automatic Runtime can later hibernate;
- notification click can route the exact persistent Slot after Runtime reclaim;
- Browser Profile/session/conversation state survives the reclaim/restore path.

The same acceptance exposed a user-visible performance problem: after FloatTabs has been unused long enough for the selected Runtime to be reclaimed, summoning FloatTabs may show the shell/colored frame while useful Web content is absent for roughly one second or more.

The current production policy also retains two Phase-7 tuning constants as healthy-state product behavior:

```text
normal Automatic resident target = 2
Automatic inactive release        = 30s
```

These values are implementation facts, not trustworthy memory limits and not accepted final product policy.

This task therefore reopens lifecycle/performance design around three explicit user problems:

1. cold restore should not expose an unexplained empty Web surface;
2. healthy-state Runtime retention should not be governed by a universal fixed resident count of 2;
3. hidden/inactive Runtime should become cheaper where supported without sacrificing fast revisit, generation continuity, media/fullscreen correctness or persistent user data.

## 2. Non-negotiable product invariants

1. Persistent Slot configuration is independent from live `WKWebView` lifetime.
2. Browser Profile identity, cookies, login/session state and website data survive Runtime reclaim.
3. Runtime resource management must never use deletion/reset of Browser Profile, cookies, session data, Slot configuration, preferences or backups as an ordinary recovery mechanism.
4. `SlotLifecycleCoordinator` remains the sole canonical lifecycle decision/writer.
5. `WebViewPool` remains the Runtime mechanism owner for create/reuse/hibernate/restore/release.
6. `PanelController` and `WebPanelContainerView` remain presentation/materialization owners.
7. `WebAttentionCoordinator` remains the owner of native Attention/generation protection truth.
8. Diagnostics records evidence only and must not become policy authority.
9. warning/critical macOS memory-pressure reclaim remains operational and progressive.
10. actively generating Runtime remains hard-protected from destructive normal reclaim.
11. no private WebKit SPI is authorized.
12. reload/reset/restart is not an ordinary lifecycle optimization.
13. Website cache/storage cleanup is not Runtime cleanup.
14. a memory number that cannot be supportably attributed must not be presented as product truth.

## 3. Fresh production source audit

### 3.1 Current normal lifecycle is still count + timer driven

`FloatTabs/Web/SlotLifecycleCoordinator.swift` currently defines:

```text
RuntimeBudgetPolicy.defaultManagedResidentTarget = 2
defaultAutomaticReleaseDelay = 30s
```

Normal healthy-state budget evaluation is explicitly count-based. It counts resident `Automatic` Runtime, selects eligible inactive candidates, and hibernates enough to reach the target.

Independently, every eligible inactive Automatic Runtime receives a release timer. When its 30s grace expires and the Runtime is still invisible/unprotected, it is hibernated with `releaseReason = automatic_grace_expired`.

Therefore current normal behavior can reclaim a Runtime even when the Mac has healthy resource headroom because either:

- it became the third eligible Automatic Runtime; or
- it simply remained inactive for ~30s.

This is the key mismatch with the desired browser-like product behavior.

### 3.2 Pressure path is a separate, stronger mechanism

The current coordinator also owns a supported system-memory-pressure source.

Current behavior:

```text
warning
→ progressively reclaim eligible inactive/unprotected Automatic
→ one Runtime at a time

critical
→ reclaim eligible Automatic first
→ then inactive/unprotected Keep Loaded
→ one Runtime at a time

normal
→ cancel pending pressure continuation
→ do not mass-restore reclaimed Runtime
```

This pressure ladder is not the problem identified by the user and remains a regression boundary for this task.

### 3.3 Current hibernate is a real live-Runtime teardown

`FloatTabs/Web/WebViewPool.swift` currently implements hibernate as:

```text
capture compatible opaque interactionState + URL/Profile/rendering identity
→ invalidate bridges/observers/popup ownership
→ clear delegates / stop loading
→ remove live WKWebView from pool and hierarchy
→ retain only the transient restore snapshot
```

A later revisit creates a new `WKWebView`, recreates bridge/observer ownership and applies the compatible interaction state.

Important consequence:

> `interactionState` preserves restore state but is not a retained live renderer or retained rendered surface.

A hibernated Slot therefore necessarily has a cold materialization interval on revisit.

### 3.4 Restore presentation already exists

`PanelController` already has an exact-current deferred materialization handshake. When the selected Slot has no resident WebView and presentation is requested, it starts deferred Runtime materialization.

`WebPanelContainerView` already owns a native `Restoring…` overlay with a progress indicator. The overlay is intended to remain above the newly attached WebView until exact-current Runtime readiness is observed.

The user's symptom is therefore not evidence that FloatTabs lacks a restoring state. Possible causes include presentation ordering, first-frame timing, overlay visibility/styling, delayed materialization entry, or another readiness boundary.

**Root cause remains `UNKNOWN`.** WP0 must measure the exact timeline before correcting it.

### 3.5 Current detached resident Runtime already has WebKit scheduling semantics

`WebViewFactory` currently does not override `WKPreferences.inactiveSchedulingPolicy`.

Public WebKit API evidence:

- `WKPreferences.inactiveSchedulingPolicy` is public on macOS 14+;
- Apple documents the default as `suspend` for a WebView that is not in a window;
- `.suspend` fully suspends tasks for an idle detached WebView and pauses JavaScript execution/page layout;
- `.throttle` limits processing without fully suspending;
- `.none` continues normal scheduling;
- WebViews playing media, doing media capture, loading pages or otherwise user-interactive may be exempt from idle suspension.

The current FloatTabs behavior therefore must not be described as if adding an explicit `.suspend` would create a brand-new Frozen tier. On macOS 14+ detached idle Runtime may already receive that WebKit behavior by default.

The real questions are empirical:

- when exactly does a FloatTabs Runtime become idle from WebKit's perspective?
- what happens during ChatGPT streaming generation?
- what happens during allowed background media?
- how quickly does an idle detached Runtime reattach and paint?
- what differs on macOS 13 where this public API is unavailable?

### 3.6 Aggregate GiB budget remains platform-blocked

The accepted Phase 8 measurement feasibility report proved:

- host process footprint can be measured;
- FloatTabs-attributable Networking helper can be measured via supported evidence;
- dominant WebContent/GPU helper processes cannot be deterministically attributed to FloatTabs through supported non-root production APIs;
- private WebKit process identifier SPI, root-only responsible-PID tooling and correlation heuristics are not acceptable production dependencies.

Therefore this task does **not** reopen the old Auto/Custom GiB memory-budget implementation.

A Runtime-count policy must not be relabeled as a GiB budget.

## 4. Correct conceptual lifecycle model

This contract uses observable ownership facts:

```text
ACTIVE_OR_PROTECTED
    live Runtime required for correctness / current interaction

RESIDENT_BACKGROUND
    live WKWebView still owned by WebViewPool but not currently presented
    actual WebKit scheduling behavior depends on platform/activity facts

NO_RUNTIME_WITH_RESTORE_STATE
    live WKWebView removed; transient interaction restore state may exist

RESTORING
    selected non-resident Slot is materializing a fresh Runtime
```

The term `FROZEN` is intentionally not canonical product truth in V1.

It may be used only as a diagnostic/research shorthand when a specific public WebKit scheduling state is actually observed or deliberately configured.

## 5. Protection hierarchy

Hard-protected Runtime is not eligible for ordinary destructive reclaim while any current accepted protection is active:

- actually presented/active Slot;
- fullscreen source;
- supplemental visible Web surface;
- Attention `Generating`;
- allowed background media currently playing;
- current media-protection query/pending boundary where required;
- exact-current materialization/restoring ownership;
- any later accepted correctness-critical protection.

`Keep Loaded` remains a strong normal-operation preference. Critical system pressure may still reclaim inactive/unprotected Keep Loaded after eligible Automatic Runtime is exhausted.

## 6. Design goals

### G1 — truthful immediate restore presentation

A cold/non-resident selected Slot must not expose an unexplained blank Web area while materialization occurs.

The first visible presentation after a summon/select request must be one of:

- already-ready resident Web content; or
- an explicit native restoring surface; or
- an evidence-approved bounded visual continuity snapshot.

A stale prior Slot surface must never masquerade as the selected Slot.

### G2 — no universal healthy-state target=2

The fixed normal resident target `2` must not remain the final product invariant.

The replacement must be honest about what it knows. It may use supported resource pressure, physical-memory class, recency/revisit facts and deterministic lifecycle state, but it may not pretend those inputs are exact WebContent memory attribution.

### G3 — avoid unconditional 30s destructive reclaim

The current 30s value may remain useful as anti-thrash eligibility, but should not automatically mean every inactive Automatic Runtime is destroyed after 30s when resources are healthy.

WP0 must determine the cost/benefit of retaining recent background Runtime longer.

### G4 — cheaper background without breaking live work

Reduce unnecessary CPU/timer/layout/presentation work for inactive Runtime where public WebKit already supports it.

Do not equate scheduling suspension with memory release. Real WebContent heap release still requires hibernate/discard.

### G5 — fast revisit and bounded memory growth

A healthy Mac should be able to retain more than two recent Runtime when that materially improves revisit latency, but inactive Runtime must not accumulate indefinitely without a policy boundary.

### G6 — supported macOS 13+ behavior

The app baseline remains macOS 13+. Any macOS 14+ inactive scheduling API must be availability-gated and the macOS 13 path must remain safe and explicit.

## 7. WP0 — evidence gate

WP0 is mandatory before product lifecycle behavior changes.

### 7.1 Restore timing matrix

Measure at minimum:

| Scenario | Expected fact to establish |
| --- | --- |
| resident quick reopen | reattach/paint latency without new Runtime |
| current >30s hibernated reopen | cold create/restore/readiness timeline |
| notification-click after hibernate | exact-Slot cold route timeline |
| rapid Slot A↔B↔A | anti-thrash/revisit cost |
| long-hidden FloatTabs summon | shell/restoring/content first-frame ordering |

Correlate existing diagnostics where available:

```text
panel summon / presentation request
panel.materialization.deferred
panel.materialization.attached
web_runtime.create.begin
web_runtime.created
web_runtime.restore.completed
navigation commit / finish
panel.materialization.readiness_completed / failed
restoring surface show / hide
```

If the current log cannot prove the first native restoring frame or first Web-content frame, WP0 may add only the smallest diagnostic timing seam. Any such mutation must remain evidence-only and must not alter lifecycle policy.

### 7.2 Background scheduling matrix

Characterize on real macOS hosts:

| Runtime state | Required observation |
| --- | --- |
| visible idle | baseline |
| detached resident idle | CPU/timer/paint/revisit behavior |
| detached resident ChatGPT generation | completion continuity + scheduling behavior |
| detached resident allowed media | playback/protection behavior |
| hibernated | Runtime absence + resource/revisit behavior |
| restoring | create/readiness cost |

On macOS 14+, include the effective/default inactive scheduling behavior.

Do not change production to `.none`, `.throttle` or `.suspend` during this characterization unless a separately bounded experiment build is explicitly isolated from production behavior.

On macOS 13, test when a compatible host is available. If not available, report `NOT_TESTED`; do not extrapolate from macOS 14+.

### 7.3 Resource evidence

Use supported app diagnostics and external development benchmark/profiling as evidence only.

The existing root/sudo benchmark may help correlate aggregate FloatTabs/WebKit memory in a controlled development environment, but it remains test tooling and may not become a production dependency or policy input.

Compare relative states, not invented per-Slot RSS:

```text
visible resident
vs detached resident idle
vs detached resident generating
vs hibernated
vs restoring
```

Record CPU/background-work reduction separately from memory reduction.

### 7.4 Restore continuity snapshot spike

If native restoring presentation alone does not meet UX needs, WP0 may spike `WKWebView.takeSnapshot` as a visual continuity technique.

Acceptance constraints for any later implementation:

- memory-only;
- bounded/downscaled;
- exact Slot + current Runtime identity scoped;
- non-interactive;
- invalidated on navigation, Browser Profile/rendering mismatch, removal, Runtime replacement or incompatible URL;
- purged immediately after true Web readiness;
- purgeable on pressure;
- no persistence, backup, diagnostics content or long-lived page image history.

The spike must measure capture cost, image memory cost, stale-image risk and perceived restore benefit. If those costs do not justify it, reject the snapshot layer and improve the native restoring surface instead.

## 8. Healthy-state policy options to decide after WP0

### Option A — pressure-first + long-idle cleanup

```text
normal system pressure
→ no count-driven target=2 eviction
→ recent background Automatic Runtime may remain resident
→ 30s becomes minimum anti-thrash eligibility, not automatic destruction
→ bounded long-idle cleanup prevents indefinite resident accumulation

warning / critical
→ existing progressive pressure ladder
```

Benefits:

- most honest use of the supported scarcity signal;
- improves revisit latency;
- avoids a new fake memory budget.

Risk:

- healthy-state memory can grow before macOS raises pressure;
- long-idle boundary still needs a tuning value and anti-thrash evidence.

### Option B — adaptive soft warm-set

```text
normal system pressure
→ derive a soft warm-set range from physical-memory class + recent-use/revisit facts
→ recent/high-value background Runtime retained
→ stale/low-value eligible Runtime reclaimed progressively
→ no claim that the range represents GiB

warning / critical
→ existing pressure ladder overrides soft warm-set
```

Benefits:

- bounds healthy-state resident growth before OS warning;
- allows larger-memory Macs to keep more recent Runtime.

Risk:

- remains heuristic;
- a count-like warm set can still mis-rank heavy/light pages;
- must not regress into a new magic `N` invariant.

### Decision rule

WP0 must recommend A, B, or a narrowly evidenced hybrid.

No product code may silently choose a replacement constant before this evidence is reviewed.

## 9. Planned work after WP0

### WP1 — restore first-frame continuity

Target:

```text
summon/select nonresident Slot
→ truthful native/snapshot restoring surface visible immediately
→ fresh exact Runtime materializes underneath
→ exact-current readiness
→ restoring surface removed
→ focus/interaction enabled
```

Tests must cover stale materialization generations and rapid Slot switching.

### WP2 — adaptive normal lifecycle policy

Remove fixed `target=2` as normal product truth and implement the WP0-selected policy.

Required properties:

- one canonical writer (`SlotLifecycleCoordinator`);
- deterministic ordering when multiple candidates are eligible;
- exact-current protection revalidation before reclaim;
- bounded anti-thrash/hysteresis;
- no precomputed mass purge from stale facts;
- pressure ladder remains independent and higher priority.

### WP3 — resident-background scheduling

Use public WebKit only.

If WP0 proves default scheduling already satisfies the product objective, keep the default and do not add code for the sake of having a feature.

If an explicit override is justified, lifecycle intent and WebKit mechanism must remain separate:

- lifecycle coordinator owns whether a Runtime should stay resident or be reclaimed;
- WebView/WebViewFactory owns supported scheduling configuration;
- no scheduling property becomes a second lifecycle truth.

Generation/media continuity must be proven before any explicit scheduling policy is applied to those states.

### WP4 — hibernate/restore integration

Integrate normal policy, pressure escalation, restore-state lifetime, Keep Loaded and rapid revisit.

Reclaim must remain one Runtime at a time where progressive evidence is required.

### WP5 — verification and real-Mac acceptance

Machine gate:

- focused lifecycle policy tests;
- restore/materialization presentation tests;
- WebViewPool hibernate/restore tests;
- generation/Attention/background regressions;
- pressure ladder regressions;
- Browser Profile/session data-safety regressions;
- full XCTest;
- Debug arm64;
- Release arm64;
- native arm64 architecture;
- package-lock check;
- literal-head self-hosted macOS CI;
- QA DMG;
- fresh independent exact-diff/ownership/data-safety audit.

Human real-Mac acceptance:

1. resident quick revisit is effectively immediate;
2. long-idle/cold revisit never exposes an unexplained blank panel;
3. restored Slot/session/conversation is correct;
4. hidden 60–120s generation still completes and notifies correctly;
5. notification click still restores the exact nonresident Slot;
6. background idle behavior is materially cheaper without unacceptable revisit delay;
7. warning/critical reclaim remains safe;
8. Browser Profile/login/session data remains intact.

## 10. Explicit non-goals

This task does not authorize:

- a production GiB memory budget without deterministic aggregate attribution;
- exact per-Slot WebContent RSS claims;
- private WebKit freeze/process SPI;
- direct WebKit helper process killing;
- Browser Profile/session/cache reset as resource management;
- changing ChatGPT generation semantics merely to save resources;
- a general browser tab-discard framework unrelated to FloatTabs Slots;
- persisted page thumbnails/screenshot history;
- a new settings UI before the underlying policy is evidence-backed.

## 11. STOP conditions

STOP and reconcile if any implementation requires or introduces:

1. a second Runtime lifecycle writer;
2. a fixed replacement resident count presented as adaptive truth without evidence;
3. Runtime count used as a GiB proxy;
4. guessed/correlation WebContent/GPU attribution as product input;
5. private WebKit SPI;
6. root/restricted entitlement as normal app dependency;
7. destructive user/session data mutation;
8. reload/reset/restart as ordinary lifecycle management;
9. forced background scheduling for generating/media Runtime without continuity evidence;
10. unbounded or persisted visual snapshots;
11. stale visual snapshot that can remain interactive or outlive Slot/Runtime identity;
12. product behavior mutation before WP0 decision is reconciled into current Authority;
13. a required test/build/CI failure caused by the task.

## 12. WP0 return contract

WP0 must return:

```text
BASELINE_IDENTITY
RESTORE_TIMELINE_EVIDENCE
FIRST_VISIBLE_SURFACE_RESULT
BACKGROUND_IDLE_CHARACTERIZATION
BACKGROUND_GENERATION_CHARACTERIZATION
BACKGROUND_MEDIA_CHARACTERIZATION_OR_NOT_TESTED
MACOS_14_INACTIVE_SCHEDULING_RESULT
MACOS_13_RESULT_OR_NOT_TESTED
RESOURCE_STATE_COMPARISON
SNAPSHOT_SPIKE_RESULT = ACCEPT / REJECT / NOT_NEEDED
NORMAL_POLICY_RECOMMENDATION = A / B / EVIDENCED_HYBRID
COLD_RESTORE_ROOT_CAUSE = KNOWN / UNKNOWN
PRODUCT_MUTATION = NOT_STARTED
```

Only after web/independent review of this evidence may `CURRENT_TASK.md` authorize WP1–WP4 product behavior changes.
