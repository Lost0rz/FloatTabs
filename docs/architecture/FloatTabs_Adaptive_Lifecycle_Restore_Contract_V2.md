# FloatTabs Adaptive Lifecycle + Restore Performance Contract V2

**Status:** `ACCEPTED / WP1 CORRECTIVE-002 FROZEN / WP2–WP4 BLOCKED`  
**Task:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Date:** `2026-11-02`  
**Baseline:** `main@7e179aaf4dbf0c538c7c2221101fc74d16e49b98`  
**WP0 evidence head:** `0cc2c2a11a59200645380ae3f477d3803e67e6ab`  
**Latest WP1 implementation/audit evidence head:** `1a457adccf10fce3631963caad8aa5cfb30f4561`  
**Scope:** cold-restore presentation, exact-Runtime presentation readiness, restore latency evidence, healthy-state lifecycle direction  
**Mutation state:** `WP1 PRESENTATION CORRECTIVE AUTHORIZED / WP2–WP4 NOT AUTHORIZED`

> This revision consolidates the already accepted V2 design after the second WP1 audit. It does not change the accepted WP0 restore measurements, lifecycle ownership, data-safety boundary, or WP2–WP4 block. It adds one durable presentation-readiness invariant required by the observed A→B→A race.

## 1. Why V2 exists

V1 stopped product mutation until controlled real-Mac evidence identified the cold-restore failure layer. That evidence established enough to authorize a bounded presentation correction without pretending the broader resource-policy work is complete.

V2 keeps two decisions separate:

1. restore presentation is sufficiently diagnosed for WP1 corrective work;
2. healthy-state retention/background-resource policy remains partially evidenced and WP2–WP4 stay blocked.

V1 remains superseded.

## 2. Non-negotiable product and ownership invariants

1. Persistent Slot configuration is independent from live `WKWebView` lifetime.
2. Browser Profile identity, cookies, login/session state and website data survive Runtime reclaim.
3. Runtime resource management never clears Browser Profile/session/configuration as an ordinary recovery action.
4. `SlotLifecycleCoordinator` remains the sole lifecycle policy/reclaim writer.
5. `WebViewPool` remains Runtime create/reuse/hibernate/restore/release and exact Runtime identity mechanism owner.
6. `PanelController` remains the canonical selected-Slot presentation/materialization/readiness coordinator.
7. `WebPanelContainerView` remains the native Web/restoring/error-surface mechanism owner.
8. `WebAttentionCoordinator` remains generation/Attention protection authority.
9. `TabStore` remains persistent Slot selection/configuration owner and does not become a Runtime/presentation policy writer.
10. Diagnostics records evidence only and does not define product truth.
11. warning/critical memory-pressure reclaim remains operational and progressive.
12. generating Runtime remains hard-protected from destructive normal reclaim.
13. no private WebKit SPI, helper killing, reload/reset/restart workaround, or destructive session clearing is authorized.
14. memory claims remain bounded by the accepted Phase-8 attribution-feasibility result.
15. PR #193 notification content/privacy/exact-Slot routing semantics remain regression boundaries.

## 3. Accepted controlled WP0 evidence

Controlled Release build:

```text
FloatTabs = 0.5.8 (26)
source = 0cc2c2a11a59200645380ae3f477d3803e67e6ab
architecture = arm64
host = Apple M4 Mac mini / 16 GB
macOS = 26.6.2
```

The QA build contained the diagnostic-only timing seam:

- `panel.restoring_surface.window_visible`;
- `panel.materialization.web_content_reveal_requested`.

These events use monotonic uptime and do not claim WebKit compositor first-pixel timing.

### 3.1 Resident quick revisit

A short hide/reopen with the selected Runtime still resident completed presentation in roughly **35 ms** with no new Runtime creation.

```text
RESIDENT_REVISIT=EFFECTIVELY_IMMEDIATE
```

### 3.2 Normal cold summon after Automatic hibernate

One controlled cold generation measured approximately:

```text
materialization.deferred                  0 ms
web_runtime.create.begin                ~12 ms
web_runtime.created                     ~63 ms
panel.materialization.attached          ~64 ms
web_content_reveal_requested          ~3123 ms
source.order_front                    ~3127 ms
readiness_completed                   ~3132 ms
```

A second cold materialization showed the same shape with roughly 6.04 seconds to reveal/readiness while fresh Runtime creation remained tens of milliseconds.

Accepted conclusions:

- fresh `WKWebView` construction is not the multi-second bottleneck;
- most observed cold time occurs after create/attach while navigation/restore progresses toward readiness;
- the existing native restoring state was requested but its owning source window remained hidden during the wait;
- the human observation of shell/frame followed by delayed Web content matches the trace.

### 3.3 Notification-click cold restore

Hidden ChatGPT generation remained protected through the Automatic grace boundary. Completion and notification succeeded; after completion the Automatic Runtime later hibernated.

After hibernate, notification click measured approximately:

```text
notification.route.received               0 ms
web_runtime.create.begin                  ~6 ms
web_runtime.created                      ~67 ms
panel.presentation.begin                 ~70 ms
source.order_front                       ~77 ms
navigation.commit                      ~1991 ms
```

The exact target did not enter the normal deferred/restoring/reveal sequence before the fresh source WebView was exposed. Exact persistent Slot routing, Browser Profile/session/conversation restoration, generation protection and notification privacy remained correct.

## 4. Root-cause classification

```text
COLD_RESTORE_PRESENTATION_ROOT_CAUSE=KNOWN
COLD_RESTORE_LATENCY_ROOT_CAUSE=NARROWED
WEBKIT_FIRST_PIXEL=UNMEASURED
```

Normal cold summon hid the source window containing the restoring surface until readiness. Notification cold routing exposed a fresh blank WebView before readiness. The common presentation defect is the lack of one canonical gate for every selected nonresident Slot.

The measured 3–6 second cold latency is dominated by navigation/readiness after Runtime creation, not the tens-of-milliseconds `WKWebView` construction interval. V2 does not claim that navigation finish, reveal request, or window ordering equals the first useful compositor pixel.

## 5. WP1 selected design — one canonical cold-presentation gate

The selected design remains one native gate owned by `PanelController`, reusing `WebPanelContainerView` rather than adding a screenshot/snapshot layer.

```text
PRESENTATION_REQUEST(nonresident Slot)
→ exact presentation target established
→ restoring ownership established
→ native Restoring… surface actually visible
→ fresh exact Runtime creates/restores underneath
→ Runtime may attach while still covered by restoring state
→ exact-current readiness validates identity
→ ready Web surface reveal
→ restoring state removed
→ focus / interaction / unread acknowledgement
```

Mandatory ordering:

1. restoring ownership precedes exposure of unready Web content;
2. the restoring surface must be actually visible during the cold wait;
3. notification routing enters the same gate as ordinary cold summon/switch;
4. stale/foreign Runtime completion cannot reveal, focus, clear restoring, or clear unread for the current target;
5. resident **ready** Runtime preserves the fast path.

## 6. Durable Corrective-002 invariant — Runtime residency is not readiness

The second WP1 exact-diff audit identified an A→B→A race that proves the following distinction is mandatory:

```text
RUNTIME_RESIDENCY != PRESENTATION_READINESS
EXISTING_WEBVIEW != READY_TO_REVEAL
```

A Runtime may remain resident in `WebViewPool` after its originating presentation/materialization generation is cancelled. That Runtime may still be loading or may already have failed. Its existence cannot authorize user-facing reveal or focus.

### 6.1 Ownership

- `WebViewPool` owns existence and exact Runtime identity.
- `PanelController` owns presentation readiness for that exact Runtime identity.
- `SlotLifecycleCoordinator` continues to own reclaim/retention policy and is not used to solve presentation races.

### 6.2 Required exact-Runtime readiness states

The implementation must represent, at minimum, these semantics for an exact Runtime identity:

```text
loading
ready
failed
```

The concrete Swift type is not prescribed. The state must be bound to exact Runtime identity rather than Slot ID alone.

### 6.3 Readiness fact update vs presentation mutation

Navigation callbacks have two distinct responsibilities:

```text
A. update readiness fact for the exact Runtime identity
B. mutate the currently selected presentation
```

A may occur when the exact Runtime is still owned by `WebViewPool` even if the presentation generation that originally created it is stale.

B may occur only when the callback also matches the exact current selected presentation/materialization ownership.

This allows:

```text
A loading under Restoring
→ select B
→ A finishes while B remains current
→ A becomes ready as an identity fact only
→ B UI remains untouched
→ later return to A uses resident-ready fast path
```

It also prevents:

```text
old A callback
→ A Runtime replaced
→ old identity marks replacement ready
```

### 6.4 Re-entry behavior for an existing Runtime

When the selected Slot already has a resident Runtime:

- exact identity `ready` → resident fast path;
- exact identity `loading` → re-establish/continue native Restoring around the **same** Runtime; do not create a duplicate Runtime; do not expose/focus it until exact readiness;
- exact identity `failed` → truthful bounded native error/empty presentation; no Web focus;
- unknown readiness must not silently become `ready` merely because `existingWebView` is non-nil. Resolve compatibility from trustworthy provenance or stop with the concrete gap.

Identity replacement/removal invalidates stale readiness state.

### 6.5 Presentation cancellation is not lifecycle reclaim

Cancelling stale presentation ownership must not call normal `release`/`hibernate` merely to erase a loading Runtime. That would convert a presentation race into a lifecycle-policy side effect and is outside WP1 authority.

## 7. Focus, unread, notification and failure boundaries

WP1 preserves these rules:

- focus is never assigned to stale, loading, failed, or foreign Runtime content;
- unread acknowledgement occurs only when the exact Slot is actually presented and presentation-ready;
- cold explicit/notification unread intent may wait for exact-current readiness, but stale target replacement invalidates it;
- navigation failure does not promote the failed WebView to current/focus ownership and uses the existing native bounded failure/empty presentation;
- notification routing does not clear unread merely because a Runtime exists;
- generation protection remains independent from presentation correction;
- hidden generating Runtime remains protected until generation truth ends.

## 8. Rapid switching and stale ownership

For A→B→A, notification-arrives-during-restore, or selection replacement:

```text
new presentation target
→ prior presentation generation becomes stale
→ stale Runtime may remain resident and may finish internally
→ exact Runtime readiness may update if identity still matches pool ownership
→ stale presentation cannot reveal/focus/clear current restoring UI
→ returning to an existing loading Runtime re-enters Restoring on that Runtime
→ returning to an existing ready Runtime uses fast path
```

No stale Slot may flash as if it were selected, and no duplicate Runtime should be created merely because a loading resident Runtime needs a new presentation transaction.

## 9. Snapshot decision

```text
SNAPSHOT_SPIKE=NOT_NEEDED_FOR_WP1
```

The known failures are native restoring visibility, route convergence, and readiness ownership. A snapshot layer would add memory, invalidation, privacy and stale-visual complexity without addressing the canonical-state defect. Reconsider only after a corrected native gate fails explicit human acceptance.

## 10. WP1 implementation boundary

WP1 may modify only what is necessary for the unified cold-presentation/readiness gate and its regressions.

Likely affected surfaces:

- `PanelController` presentation/materialization/readiness orchestration;
- `WebPanelContainerView` native restoring/Web/error presentation mechanics only if required;
- bounded notification route adaptation only to enter the same gate;
- focused tests for cold presentation, rapid switching, failure, focus, unread and notification boundaries.

WP1 must not modify:

- fixed normal `Automatic resident target = 2`;
- 30-second Automatic reclaim semantics;
- warning/critical pressure ordering or Keep Loaded semantics;
- explicit `WKPreferences.inactiveSchedulingPolicy`;
- Browser Profile/session persistence or cache/data deletion behavior;
- adaptive warm-set/long-idle policy;
- memory-budget logic;
- notification preview/privacy payload contract;
- generation detection/protection semantics except test-preserving call adaptation required by presentation work.

## 11. WP1 verification contract

Focused tests must prove at minimum:

1. normal cold summon enters restoring before ready reveal;
2. notification cold route enters the same restoring gate;
3. restoring is actually visible during cold wait;
4. unready/failed Web content is never presented as ready;
5. resident ready Runtime keeps the fast path;
6. A loading → B → A before finish returns to Restoring on the same Runtime with no duplicate creation or focus;
7. A loading → B, then A finishes in background, does not mutate B and later returns via ready fast path;
8. old Runtime callback cannot transfer readiness to a replacement identity;
9. failed exact Runtime re-entry remains native error/empty and unfocused;
10. cold explicit/notification unread acknowledgement remains readiness-gated;
11. exact notification Slot/privacy/content semantics remain correct;
12. generation protection remains unchanged.

Machine gate before human acceptance:

- focused affected regressions;
- full XCTest;
- Debug arm64;
- Release arm64;
- native arm64 verification;
- package-lock unchanged unless reconciled;
- literal-head self-hosted macOS CI;
- QA DMG;
- fresh exact-diff/ownership/data-safety audit.

## 12. Literal-head CI evidence gate

At implementation head `1a457adccf10fce3631963caad8aa5cfb30f4561`:

```text
local full XCTest = 1149 passed / 4 skipped / 0 failed
Debug/Release/native arm64 = PASS
QA DMG = PASS
literal-head self-hosted macOS CI = FAIL on repeated attempts
new corrective tests in CI = PASS
CI_ROOT_CAUSE = UNKNOWN
```

The broad failures were reported in WebKit focus/page-load/geometry areas. The evidence does not yet prove task causality or infrastructure flakiness.

After Corrective-002, run one clean literal-head CI attempt. If it passes, continue to fresh independent audit. If broad failure repeats, stop and return a bounded diagnostic package before any further rerun or product mutation:

```text
CI_RUN_ID
CI_JOB_ID
FIRST_10_FAILING_TESTS
FAILURE_SIGNATURE_GROUPS
FOCUSED_NEW_TESTS_RESULT
REPEATED_FAILURE_OVERLAP
LOCAL_FULL_XCTEST_RESULT
OBSERVABLE_RUNNER_HOST_PRECONDITIONS
TASK_CAUSALITY=PROVEN / DISPROVEN / UNKNOWN
```

Do not use destructive runner cleanup or blind rerun-until-green loops.

## 13. Human real-Mac acceptance

Human acceptance remains blocked until the literal-head machine gate is green and a fresh independent exact-diff audit returns PASS.

Once unblocked, the user must explicitly verify the exact-head QA build:

1. resident short revisit remains effectively immediate;
2. normal cold summon shows `Restoring…` rather than frame + empty center;
3. notification click after hibernate shows restoring or ready content, never blank fresh Web content;
4. exact Slot/session/conversation remains correct;
5. rapid A→B→A does not expose stale/unready content;
6. hidden generation/completion notification remains correct.

## 14. Healthy-state lifecycle direction — evidence only

Current shipped policy still contains:

```text
normal Automatic resident target = 2
Automatic inactive destructive reclaim = ~30s
```

Accepted durable conclusions remain:

- universal fixed `target=2` is not final product truth;
- `30s == mandatory destructive lifetime` is rejected as the final product invariant;
- recent resident Runtime has substantial UX value;
- Runtime count must not be relabeled as RAM.

Current recommendation:

```text
NORMAL_POLICY_RECOMMENDATION=A_FAVORED_NOT_FROZEN
```

Option A remains pressure-first + bounded long-idle cleanup, but no long-idle threshold or revised reclaim semantics are authorized in WP1. WP2 stays blocked.

## 15. Background scheduling and aggregate-memory boundary

`WebViewFactory` still does not override `WKPreferences.inactiveSchedulingPolicy`. On macOS 14+ the public default for an idle detached WebView is documented as `.suspend`, but controlled detached idle/generation/media behavior remains incomplete and macOS 13 remains `NOT_TESTED` for this evidence set. WP1 may not add an explicit scheduling override.

The Phase-8 feasibility result remains binding: dominant WebContent/GPU memory is not a supported ordinary production attribution. No production GiB budget may be reconstructed from Runtime count, root-only tooling, private SPI, or correlation heuristics.

## 16. STOP conditions

STOP and reconcile if WP1 requires or introduces:

1. Runtime release/hibernate as a presentation-race workaround;
2. lifecycle reclaim/retention changes, including target `2` or 30-second semantics;
3. a second presentation/readiness or lifecycle writer;
4. readiness keyed only by Slot when exact Runtime identity is available;
5. resident WebView existence treated as sufficient readiness;
6. unready/failed WebView exposure outside native restoring/error ownership;
7. stale Runtime reveal/focus or stale identity readiness transfer;
8. duplicate Runtime creation for an existing loading Runtime;
9. polling/timer loops for readiness/unread instead of event-driven transitions;
10. notification privacy/exact-route regression;
11. generation-protection regression;
12. destructive Browser Profile/session mutation;
13. private WebKit SPI/helper-process killing;
14. reload/reset/restart ordinary restore behavior;
15. screenshot/snapshot persistence or unbounded visual retention;
16. unexplained repeated literal-head CI failure without bounded diagnosis.

## 17. Task reconciliation

```text
TASK_RECONCILIATION_REQUIRED=YES
REASON=Fresh WP1 audit proved exact Runtime residency and presentation readiness must be distinct, and literal-head CI remains an unexplained gate blocker.
DURABLE_DOCUMENT=docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md
```

`CURRENT_STATUS.md` and `CURRENT_TASK.md` are reconciled to WP1 Corrective-002 + bounded CI diagnosis. WP2–WP4 remain blocked.
