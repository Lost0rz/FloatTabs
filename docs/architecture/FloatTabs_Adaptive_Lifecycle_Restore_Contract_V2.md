# FloatTabs Adaptive Lifecycle + Restore Performance Contract V2

**Status:** `ACCEPTED / WP1 FROZEN / WP2–WP4 BLOCKED`  
**Task:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Date:** `2026-11-02`  
**Baseline:** `main@7e179aaf4dbf0c538c7c2221101fc74d16e49b98`  
**Evidence head before reconciliation:** `0cc2c2a11a59200645380ae3f477d3803e67e6ab`  
**Scope:** cold-restore presentation, restore latency evidence, healthy-state lifecycle direction  
**Mutation state:** `WP1 PRESENTATION CORRECTIVE AUTHORIZED / WP2–WP4 NOT AUTHORIZED`

## 1. Why V2 exists

V1 intentionally stopped product mutation until controlled restore evidence could establish where FloatTabs was losing time and why the user saw blank restore states.

The controlled real-Mac evidence now answers the restore-presentation question strongly enough to authorize a bounded correction without pretending the broader resource-policy work is complete.

V2 therefore separates two decisions:

1. **Restore presentation is sufficiently diagnosed and WP1 may proceed.**
2. **Healthy-state retention/background-resource policy remains only partially evidenced and WP2–WP4 stay blocked.**

V2 supersedes V1 as the current durable design contract for this task.

## 2. Preserved product invariants

1. Persistent Slot configuration is independent from live `WKWebView` lifetime.
2. Browser Profile identity, cookies, login/session state and website data survive Runtime reclaim.
3. Runtime resource management never clears Browser Profile/session/configuration as an ordinary recovery action.
4. `SlotLifecycleCoordinator` remains the sole lifecycle policy/reclaim writer.
5. `WebViewPool` remains Runtime create/reuse/hibernate/restore/release mechanism owner.
6. `PanelController` remains the canonical selected-Slot presentation/materialization coordinator.
7. `WebPanelContainerView` remains the native Web/restoring-surface mechanism owner.
8. `WebAttentionCoordinator` remains generation/Attention protection authority.
9. `TabStore` remains persistent Slot selection/configuration owner and does not become a Runtime/presentation policy writer.
10. warning/critical macOS pressure reclaim remains operational and progressive.
11. generating Runtime remains hard-protected from destructive normal reclaim.
12. no private WebKit SPI, WebKit helper killing, reload/reset/restart workaround or destructive session clearing is authorized.
13. diagnostics remain evidence only.
14. memory claims remain bounded by the accepted Phase-8 attribution feasibility result.
15. PR #193 notification content/privacy/exact-Slot routing semantics remain regression boundaries.

## 3. Accepted controlled evidence

### 3.1 Environment

```text
FloatTabs version = 0.5.8 (26)
source revision   = 0cc2c2a11a59200645380ae3f477d3803e67e6ab
architecture      = arm64
host              = Apple M4 Mac mini / 16 GB
macOS             = 26.6.2
```

The exact QA build contained the WP0 diagnostic-only timing seam:

- `panel.restoring_surface.window_visible`
- `panel.materialization.web_content_reveal_requested`

Runtime events already carry monotonic `uptime`, so latency comparisons use `uptime` rather than wall-clock timestamp resolution.

### 3.2 Resident quick revisit

A short hide/reopen with the selected Runtime still resident completed presentation in roughly **35 ms** with no new Runtime creation.

Accepted fact:

```text
RESIDENT_REVISIT=EFFECTIVELY_IMMEDIATE
```

This proves the general presentation/focus path is not inherently multi-second when the Runtime remains resident.

### 3.3 Normal cold summon after Automatic hibernate

The selected Automatic Runtime was hibernated after `automatic_grace_expired` and later summoned.

Controlled materialization generation:

```text
materialization.deferred                  0 ms
web_runtime.create.begin                ~12 ms
web_runtime.created                     ~63 ms
panel.materialization.attached          ~64 ms
web_content_reveal_requested          ~3123 ms
source.order_front                    ~3127 ms
readiness_completed                   ~3132 ms
```

A second cold materialization showed the same shape with a longer readiness interval:

```text
materialization.deferred                  0 ms
web_runtime.created                     ~48 ms
web_content_reveal_requested          ~6034 ms
readiness_completed                   ~6041 ms
```

Accepted facts:

- fresh `WKWebView` construction is only tens of milliseconds and is not the multi-second bottleneck;
- most observed cold time occurs after Runtime creation/attachment while Web navigation/restore proceeds toward accepted readiness;
- the existing restoring state had been requested but was not actually visible during these cold waits because its source window remained hidden until reveal/readiness;
- the human observation of shell/colored frame followed by delayed Web content matches the trace.

### 3.4 Notification-click cold restore

A hidden ChatGPT generation remained protected across the normal Automatic grace boundary.

Observed sequence:

```text
generation active
→ automatic grace boundary
→ slot_lifecycle.attention_protected
→ generation finished
→ notification submitted
→ ~31.5s
→ automatic_grace_expired hibernate
```

After hibernate, the notification click produced:

```text
notification.route.received               0 ms
web_runtime.create.begin                  ~6 ms
web_runtime.created                      ~67 ms
panel.presentation.begin                 ~70 ms
source.order_front                       ~77 ms
navigation.commit                      ~1991 ms
```

The exact target Slot did not enter the normal deferred-materialization/restoring/reveal sequence before its source window was exposed.

Accepted facts:

- exact persistent Slot routing remained correct;
- Browser Profile/session/conversation restoration remained correct;
- generation protection remained correct;
- notification content/privacy behavior remained correct;
- the source window was shown while the fresh WebView was still blank/loading;
- the human observation of a blank Web surface followed by delayed content matches the trace.

## 4. Root-cause classification

### 4.1 Presentation root cause — KNOWN

```text
COLD_RESTORE_PRESENTATION_ROOT_CAUSE=KNOWN
```

There are currently two inconsistent cold-presentation shapes:

**Normal cold summon**

```text
request restoring state
→ source window stays hidden
→ fresh Runtime materializes/navigates
→ readiness
→ source window finally ordered front
```

The user therefore sees shell/frame without the truthful restoring surface.

**Notification cold route**

```text
notification route
→ exact Slot select
→ fresh Runtime created
→ panel presentation begins
→ source window ordered front immediately
→ navigation continues afterward
```

The user therefore sees a blank fresh WebView.

Common cause:

> FloatTabs lacks one canonical presentation gate that owns every presentation request for a selected nonresident Slot before Web Runtime exposure.

### 4.2 Latency root cause — NARROWED

```text
COLD_RESTORE_LATENCY_ROOT_CAUSE=NARROWED
```

The evidence rules out fresh `WKWebView` object construction as the dominant source of 3–6 second cold waits.

The remaining dominant measured interval is Web navigation/readiness after create/attach.

The exact WebKit compositor first-useful-pixel boundary remains unmeasured:

```text
WEBKIT_FIRST_PIXEL=UNMEASURED
```

V2 therefore does not claim that `navigation_finished`, reveal request or source ordering equals first rendered pixel.

## 5. WP1 selected design

### Design question

How should FloatTabs present a selected nonresident Slot so ordinary summon, explicit switching and notification routing cannot expose either an empty shell or a blank fresh WebView?

### Selected option

**One canonical native cold-restore presentation gate owned by `PanelController`, reusing the existing `WebPanelContainerView` restoring surface.**

The existing native restoring concept is retained. WP1 corrects its visibility/order and route convergence rather than inventing a snapshot layer or a second presentation owner.

### Required state flow

```text
PRESENTATION_REQUEST(nonresident Slot)
    ↓
exact Slot becomes presentation target
    ↓
RESTORING_OWNERSHIP_ESTABLISHED
    ↓
native Restoring… surface becomes actually visible
    ↓
fresh exact Runtime create / interaction-state restore or URL load
    ↓
Runtime may attach under restoring state
    ↓
exact-current readiness validates:
    Slot ID
    + materialization generation
    + Runtime generation
    + WebView instance identity
    ↓
ready source/Web surface reveal
    ↓
restoring state removed
    ↓
focus / interaction / unread acknowledgement
```

### Mandatory ordering rules

1. A nonresident presentation request must establish restoring ownership before unready Web content may become user-visible.
2. `panel.restoring_surface.window_visible` must be possible during the actual wait; the restoring surface cannot live only inside a window that remains hidden until readiness.
3. A fresh source/Web window may be ordered front during materialization only while the native restoring surface truthfully covers the unready content.
4. Notification routing may not bypass deferred/materialization ownership by eagerly exposing the target WebView before the cold gate owns it.
5. Exact-current readiness is the only accepted transition out of restoring state.
6. Stale/foreign Runtime completion cannot dismiss the current restoring surface.
7. Resident ready Runtime bypasses cold materialization and keeps the existing fast path.

## 6. Entry-path convergence

WP1 must converge at minimum these entry paths:

- menu-bar summon of the selected nonresident Slot;
- global-hotkey summon of the selected nonresident Slot;
- explicit switch to a nonresident Slot while FloatTabs is visible;
- completion-notification route to an exact nonresident Slot.

The implementation should centralize the presentation transaction inside `PanelController` rather than moving presentation policy into `TabStore`, `WebViewPool` or notification code.

The notification coordinator remains a projection/router. Its exact-Slot callback must hand the target to the same presentation semantics used by ordinary cold selection.

## 7. Existing restoring surface vs snapshot

### Accepted WP1 choice

```text
SNAPSHOT_SPIKE=NOT_NEEDED_FOR_WP1
```

Reason:

- a truthful native restoring surface already exists;
- the controlled failure is visibility/ordering and path divergence;
- adding snapshots would increase memory, invalidation, privacy and stale-visual complexity without first fixing the simpler known defect.

A bounded memory-only snapshot may be reconsidered only if the corrected native restoring gate later fails explicit human acceptance.

## 8. Focus, unread and Attention boundaries

WP1 must preserve these semantics:

- focus is never assigned to a stale/non-current Runtime;
- unread acknowledgement occurs only when the exact Slot is actually presented and presentation-ready;
- notification routing does not clear unread merely because a Runtime was created;
- generation protection remains independent from presentation correction;
- hidden generating Runtime remains protected until generation truth ends;
- completion notification projection remains independent from completed Runtime residency.

The current notification trace already shows unread acknowledgement safely skipped while presentation was not ready. WP1 must preserve that protection rather than weakening it to make routing simpler.

## 9. Rapid switching and stale ownership

The cold gate must be generation-bound.

For A→B→A, notification-arrives-during-restore, or selection replacement:

```text
new presentation target
→ prior materialization generation becomes stale
→ stale Runtime may finish internally
→ stale Runtime cannot reveal, focus or clear restoring state
→ only the newest exact-current target may complete presentation
```

No prior Slot may flash as if it were the selected Slot.

## 10. WP1 implementation boundary

WP1 may modify only what is necessary to implement the unified cold-presentation gate and its regressions.

Likely affected ownership surfaces:

- `PanelController` presentation/selection/materialization orchestration;
- `WebPanelContainerView` restoring/Web-surface presentation mechanics where required;
- bounded notification-route call path only as needed to enter the same `PanelController` gate;
- focused tests for External Shell / notification route / stale materialization / focus-unread boundaries.

WP1 must **not** modify:

- fixed normal `Automatic resident target = 2`;
- 30-second Automatic reclaim semantics;
- warning/critical pressure ordering;
- explicit `WKPreferences.inactiveSchedulingPolicy`;
- Browser Profile/session persistence;
- Runtime cache/data deletion behavior;
- notification preview/privacy payload contract;
- generation detection/protection semantics except test-preserving call adaptation strictly required by presentation refactor.

## 11. WP1 verification contract

### Focused tests

Prove:

1. normal cold summon enters restoring before ready content reveal;
2. notification cold route enters the same restoring gate;
3. restoring surface is actually visible during cold wait;
4. blank/unready Web content is never presented as ready;
5. resident ready Runtime keeps the fast path;
6. stale/foreign Runtime finish cannot dismiss current restoring state;
7. rapid target replacement cancels stale ownership;
8. exact notification Slot remains correct;
9. unread acknowledgement remains presentation-ready gated;
10. generation protection remains unchanged.

### Machine gate

Before human acceptance:

- focused affected regressions;
- full XCTest;
- Debug arm64 build;
- Release arm64 build;
- native arm64 verification;
- package-lock unchanged unless reconciled;
- literal-head self-hosted macOS CI;
- QA DMG;
- fresh exact-diff/ownership/data-safety audit.

### Human real-Mac acceptance

The user must explicitly verify the exact-head QA build:

1. resident short revisit remains effectively immediate;
2. normal cold summon shows `Restoring…` immediately instead of frame + empty center;
3. notification click after hibernate shows restoring or ready content, never a blank fresh Web page;
4. exact Slot is restored;
5. conversation/login/session remains intact;
6. rapid switching does not flash stale content;
7. hidden generation and completion notification remain correct.

`HUMAN_UI_ACCEPTANCE=PENDING` until explicit user acceptance.

## 12. Healthy-state lifecycle direction — evidence only

Current shipped policy still contains:

```text
normal Automatic resident target = 2
Automatic inactive destructive reclaim = ~30s
```

These remain implementation facts during WP1.

The controlled restore evidence establishes a large revisit-cost gap:

```text
resident revisit = tens of milliseconds
observed cold revisit = roughly 3–6 seconds
```

Accepted durable conclusions:

- universal fixed `target=2` is not final product truth;
- `30s == mandatory destructive lifetime` is rejected as the final product invariant;
- recent resident Runtime has substantial UX value;
- Runtime count must not be relabeled as RAM.

Current policy recommendation:

```text
NORMAL_POLICY_RECOMMENDATION=A_FAVORED_NOT_FROZEN
```

Option A means:

```text
normal pressure
→ retain recent eligible Automatic Runtime
→ 30s may remain minimum anti-thrash eligibility rather than mandatory destruction
→ bounded long-idle cleanup prevents indefinite accumulation

warning / critical
→ existing progressive pressure ladder remains authoritative
```

This direction is not yet implementation authority. Long-idle threshold, cleanup facts, background idle/media behavior and resource evidence remain incomplete.

WP2 stays blocked until separately reconciled.

## 13. Background scheduling boundary

Current `WebViewFactory` still does not override `WKPreferences.inactiveSchedulingPolicy`.

On macOS 14+, the public default for an idle detached WebView is documented as `.suspend`, with exemptions for loading/media/capture/interactive activity.

The M4/macOS 26 host reports the fresh public configuration default as `.suspend`, but controlled detached idle/generation/media scheduling/resource behavior remains incomplete.

Therefore WP1 may not add an explicit scheduling override.

macOS 13 remains `NOT_TESTED` for this evidence set.

## 14. Aggregate-memory boundary

The prior Phase-8 feasibility result remains binding:

- host footprint is measurable;
- some development/root-only helper attribution may be useful as benchmark evidence;
- dominant WebContent/GPU attribution is not a supported ordinary production truth;
- no production GiB budget may be reconstructed from Runtime count, root-only tooling, private SPI or correlation heuristics.

## 15. STOP conditions

STOP and reconcile if WP1 requires or introduces:

1. lifecycle reclaim/retention changes;
2. removal/change of target `2` or 30s reclaim behavior during WP1;
3. a second presentation or lifecycle writer;
4. unready WebView exposure outside restoring ownership;
5. stale Runtime reveal/focus;
6. notification privacy/exact-route regression;
7. generation-protection regression;
8. destructive Browser Profile/session mutation;
9. private WebKit SPI or helper-process killing;
10. reload/reset/restart ordinary restore behavior;
11. screenshot/snapshot persistence or unbounded visual retention;
12. required test/build/CI failure caused by the task.

## 16. Task reconciliation

```text
TASK_RECONCILIATION_REQUIRED=YES
REASON=WP0 restore evidence now authorizes bounded WP1 product-presentation mutation while WP2–WP4 remain blocked
DURABLE_DOCUMENT=docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md
```

`CURRENT_TASK.md` has been reconciled accordingly.
