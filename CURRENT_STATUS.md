# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: ADAPTIVE LIFECYCLE + RESTORE PERFORMANCE — WP0 PARTIAL / DIAGNOSTIC SEAM ADDED / REAL SCENARIOS PENDING**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001` — **ACTIVE / WP0 PARTIAL**.

Task branch:

`codex/adaptive-lifecycle-restore-001`

Draft PR:

`#194 — design: adaptive lifecycle and restore performance`

Execution baseline:

`main@7e179aaf4dbf0c538c7c2221101fc74d16e49b98`

## Repository / delivery state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
MAIN_BASELINE=7E179AAF
PR_193=MERGED
PR_193_SQUASH_MERGE=7E179AAF
NOTIFICATION_HUMAN_ACCEPTANCE=PASS
TASK=FT-ADAPTIVE-LIFECYCLE-RESTORE-001
TASK_STATE=ACTIVE_WP0_PARTIAL
PR_194=OPEN_DRAFT_UNMERGED
PRODUCT_POLICY_MUTATION=BLOCKED_PENDING_WP0
COLD_RESTORE_ROOT_CAUSE=UNKNOWN
NORMAL_FIXED_TARGET_2=CURRENT_PRODUCTION_TRUTH_NOT_FINAL_PRODUCT_TARGET
AUTOMATIC_30S_UNCONDITIONAL_RELEASE=CURRENT_PRODUCTION_TRUTH_UNDER_REVIEW
AGGREGATE_GIB_BUDGET=DEFERRED_PLATFORM_BLOCKED
PRIVATE_WEBKIT_SPI=FORBIDDEN
```

Current task contract:

`docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md`

## Fresh user-observed problems

1. **Cold restore / perceived blank interval.** After FloatTabs has been unused long enough for Runtime reclaim, summoning it can present the shell/colored border while the Web content remains visually absent for roughly one second or more before the page appears. Exact Slot/session restoration is correct, but the perceived restore path is not acceptable yet. Root cause remains `UNKNOWN` until the restore timeline is measured.
2. **Rigid healthy-state Runtime count.** Production still treats `Automatic resident target = 2` as the normal count budget. This is a tuning constant, not a trustworthy memory budget, and the user has rejected it as the final product policy.
3. **Background efficiency vs restore latency.** FloatTabs needs a supported layered strategy that reduces work/resource use for hidden/inactive Runtime without destroying fast revisit behavior, while preserving generation/media/fullscreen correctness and Browser Profile/session data.

## Fresh source audit

### Lifecycle policy

`SlotLifecycleCoordinator` is still the sole lifecycle writer. Current production behavior remains:

```text
Automatic inactive
→ create inactive plan
→ 30s grace
→ hibernate if still eligible

normal resident Automatic count > 2
→ reclaim eligible Automatic Runtime by deterministic order

warning pressure
→ progressive eligible Automatic reclaim

critical pressure
→ Automatic first, then inactive/unprotected Keep Loaded
```

Generating/fullscreen/media/visible work remains protected.

### Runtime mechanism / restore

`WebViewPool.hibernate` captures an opaque, memory-only `interactionState` restore snapshot, then tears down the live WebView Runtime. A cold revisit creates a fresh `WKWebView` and reapplies compatible interaction state. This preserves session/navigation correctness but does not preserve a live rendered surface, so cold restore necessarily has a materialization window.

`PanelController` / `WebPanelContainerView` already own a native `Restoring…` presentation and exact-current Runtime readiness handshake. The user's visible blank-border symptom therefore requires timing/presentation evidence before changing restore mechanics; do not assume interaction-state failure.

### WebKit inactive scheduling

Current `WebViewFactory` does not override `WKPreferences.inactiveSchedulingPolicy`.

On macOS 14+, Apple's public API states the default policy is `suspend` for a WebView that is not in a window. A suspended idle WebView pauses JavaScript execution and page layout. WebViews playing media, doing media capture, loading pages, or otherwise user-interactive may be exempt. Therefore FloatTabs must not introduce an explicit `.suspend` and call it a new Frozen layer without first characterizing the actual current behavior.

macOS 13 does not expose this public API; compatibility behavior must remain evidence-driven and use no private SPI.

### Memory-budget platform boundary

The prior Phase 8 feasibility result remains authoritative: supported public production APIs cannot deterministically attribute dominant WebContent/GPU helper footprint to FloatTabs. Therefore no per-Slot or aggregate GiB limit may be implemented from guessed Runtime counts or process correlation.

## WP0 diagnostics and host characterization — 2026-11-02

The installed FloatTabs 0.5.8 build 26 identifies exact source revision
`7e179aaf4dbf0c538c7c2221101fc74d16e49b98`, matching the PR #194 execution
baseline. Existing standard diagnostics on this host recorded 31 deferred and
31 attached materializations and 21 readiness completions. In those unlabeled
observations, deferred-to-readiness spans were 1–5 seconds (median 2 seconds)
at one-second timestamp resolution. They are not controlled or scenario-labeled
WP0 measurements.

Current events cover presentation begin/completion, deferred/attached
materialization, Runtime create/restore, navigation commit, and readiness after
navigation finish. The overlay's `showRestoringState` / `hideRestoringState`
calls have no corresponding diagnostics. Standard logs also omit
`navigation.finished` because it is a debug event. The existing readiness event
marks when FloatTabs removes the overlay and permits Web content presentation;
it does not prove when WebKit's first useful pixels reach the display.

Therefore:

```text
RESTORING_SURFACE_VISIBLE_WINDOW=NOW_INSTRUMENTED_NOT_YET_OBSERVED
WEB_CONTENT_REVEAL_REQUEST=NOW_INSTRUMENTED_NOT_YET_OBSERVED
FIRST_WEB_CONTENT_PIXEL=UNOBSERVED
COLD_RESTORE_ROOT_CAUSE=UNKNOWN
```

The diagnostic-only seam is now on this task branch:

- `panel.restoring_surface.window_visible` records once per materialization
  generation when the restoring surface's actual owner window is visible. The
  bounded `surface_window_role` is `panel`, `source`, or `other`.
- `panel.materialization.web_content_reveal_requested` records the exact-current
  navigation-finished boundary immediately after FloatTabs removes the overlay.
- Both events use only Slot/materialization/Runtime identity and bounded window
  state. They contain no URL, page text, screenshot, or lifecycle decision.

These are FloatTabs/AppKit transition times, not compositor first-pixel times.
The new focused regression and `ExternalShellTests` passed (111/111).

Host: Apple M4 Mac mini, 16 GB, arm64, macOS 26.6.2. Production
`WebViewFactory` does not override `WKPreferences.inactiveSchedulingPolicy`; a
fresh public `WKWebViewConfiguration` on this host reports `.suspend`. This
confirms the current API default value, not measured detached page scheduling.
No compatible macOS 13 host is available (`NOT_TESTED`).

The app UI could not be inspected through Computer Use; binding the app timed
out with `-10005`. Existing logs do not label the requested controlled
scenarios, and WebKit helper processes cannot be deterministically attributed
to FloatTabs on this host. Therefore resident quick revisit, long-idle cold
restore, notification-click cold restore, rapid A/B/A, detached idle,
60–120-second generation, media, and per-state resource comparisons remain
uncharacterized in WP0. This is a tooling/evidence limitation, not a product
runtime failure.

## Design direction

The task will evaluate a layered runtime model using observable facts rather than fake memory attribution:

```text
ACTIVE / HARD-PROTECTED
→ RESIDENT_BACKGROUND
→ NO_RUNTIME_WITH_RESTORE_STATE
→ RESTORING
→ ACTIVE
```

`RESIDENT_BACKGROUND` is deliberately not named `FROZEN` as product truth until WebKit scheduling behavior is proven for the relevant state and macOS version.

The fixed healthy-state `target=2` must not survive as the final invariant. The exact replacement policy is gated on WP0 evidence. Two candidates remain open:

- pressure-first + long-idle cleanup;
- adaptive soft warm-set driven by machine class + recency/revisit facts, explicitly not a RAM budget.

## Work-package gates

```text
WP0 = runtime characterization + restore timing evidence
WP1 = restore first-frame continuity
WP2 = adaptive healthy-state lifecycle policy
WP3 = background resident scheduling characterization/integration
WP4 = hibernate/restore policy integration + anti-thrash
WP5 = broad machine verification + real-Mac human acceptance
```

Only WP0 is authorized now. Product lifecycle semantics must not change until WP0 evidence is reconciled into the task contract.

## Preserved invariants

- `SlotLifecycleCoordinator` remains the sole lifecycle policy writer.
- `WebViewPool` remains Runtime create/hibernate/restore/release mechanism owner.
- `PanelController` remains presentation/materialization owner.
- `WebAttentionCoordinator` remains generation/Attention authority.
- Browser Profile/cookies/session/configuration are never cleared as resource management.
- warning/critical pressure ladder remains operational.
- generating Runtime remains hard-protected unless a separately proven public scheduling behavior preserves generation continuity.
- no private WebKit SPI, process killing, reload/reset workaround, guessed RAM attribution or second lifecycle writer.

## Next gate

```text
WP0 on PR #194
→ characterize resident quick-revisit vs cold-reclaimed restore
→ measure shell/restoring/runtime/readiness timing
→ characterize detached idle / generating / media behavior
→ decide pressure-first vs adaptive-soft-warm-set normal policy
→ decide whether bounded memory-only visual snapshot is justified
→ update contract with evidence
→ only then authorize product behavior mutation
```
