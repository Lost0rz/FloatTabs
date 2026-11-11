# FloatTabs Adaptive Lifecycle + Restore Performance Contract V2

**Status:** `ACCEPTED / WP1 COMPLETE / HUMAN ACCEPTED`  
**Task:** `FT-ADAPTIVE-LIFECYCLE-RESTORE-001`  
**Date:** `2026-11-02`  
**Baseline:** `main@7e179aaf4dbf0c538c7c2221101fc74d16e49b98`  
**WP0 evidence head:** `0cc2c2a11a59200645380ae3f477d3803e67e6ab`  
**WP1 semantic implementation head:** `e187f83fd2c4198d3e2baa64ef5074037c87c410`  
**Pre-closeout branch head:** `1a77fae92c53708e2c6c373301c825187fdb1de4`  
**Scope:** canonical cold presentation, exact-Runtime presentation readiness, restore evidence  
**Mutation state:** `WP1 COMPLETE / WP2–WP4 SEPARATE`

V2 is the final durable WP1 contract. V1 remains superseded.

## 1. Final product invariants

1. Persistent Slot configuration is independent from live `WKWebView` lifetime.
2. Browser Profile identity, cookies, login/session state and website data survive Runtime reclaim.
3. Runtime recovery/lifecycle never clears Browser Profile/session/configuration as an ordinary action.
4. `SlotLifecycleCoordinator` is the sole lifecycle/reclaim policy writer.
5. `WebViewPool` owns Runtime create/reuse/hibernate/restore/release and exact Runtime identity.
6. `PanelController` owns selected-Slot presentation/materialization and exact-Runtime presentation readiness.
7. `WebPanelContainerView` owns native Web/restoring/error surfaces.
8. `WebAttentionCoordinator` owns generation/Attention protection truth.
9. `TabStore` owns persistent Slot selection/configuration and is not a Runtime policy writer.
10. Diagnostics records evidence only; it does not define product truth.
11. no private WebKit SPI, helper killing, reload/reset/restart workaround, or destructive session clearing is authorized.
12. memory claims remain bounded by the accepted Phase-8 attribution-feasibility result.
13. PR #193 notification content/privacy/exact-Slot semantics remain regression boundaries.

## 2. Accepted WP0 evidence

Controlled Release evidence established:

```text
resident revisit = tens of milliseconds
cold revisit = roughly 3–6 seconds
fresh WKWebView construction = tens of milliseconds
cold dominant interval = navigation/readiness after create/attach
WEBKIT_FIRST_PIXEL = UNMEASURED
```

The original normal cold path hid the restoring owner until readiness; the original notification cold path exposed a fresh blank WebView before navigation readiness.

Accepted classification:

```text
COLD_RESTORE_PRESENTATION_ROOT_CAUSE=KNOWN
COLD_RESTORE_LATENCY_ROOT_CAUSE=NARROWED
```

## 3. Canonical WP1 cold-presentation gate

Every selected nonresident Slot converges on one `PanelController` presentation transaction:

```text
PRESENTATION_REQUEST(nonresident Slot)
→ establish exact target / presentation generation
→ establish native Restoring ownership
→ make Restoring actually visible
→ create or reuse the exact Runtime underneath
→ attach while covered by Restoring
→ exact-current readiness validates identity
→ reveal ready Web content
→ remove Restoring
→ focus / interaction / unread acknowledgement
```

Entry paths covered:

- menu-bar summon;
- global-hotkey summon;
- explicit switch to a nonresident Slot;
- completion-notification route to an exact Slot.

Notification code remains a router/projection and does not become a Runtime owner.

## 4. Exact-Runtime presentation readiness

Durable invariant:

```text
RUNTIME_RESIDENCY != PRESENTATION_READINESS
EXISTING_WEBVIEW != READY_TO_REVEAL
```

For the exact Runtime identity, `PanelController` distinguishes at least:

```text
loading
ready
failed
```

Required semantics:

- cold attach records exact Runtime `loading`;
- navigation finish may mark the still-owned exact Runtime `ready` even if the originating presentation generation later became stale;
- navigation failure may mark the still-owned exact Runtime `failed`;
- reveal/focus/current UI mutation still requires exact current presentation ownership;
- returning to an existing loading Runtime re-enters Restoring around the same Runtime, with no duplicate Runtime creation;
- returning to an exact ready Runtime preserves the resident fast path;
- returning to an exact failed Runtime uses the truthful native bounded failure/empty surface with no Web focus;
- replacement Runtime identity never inherits old readiness.

Presentation cancellation is not lifecycle reclaim. A stale presentation generation must not release/hibernate a Runtime merely to erase a presentation race.

## 5. Focus, unread, notification and failure boundaries

- stale/loading/failed/foreign Runtime content cannot receive Web focus as ready content;
- unread acknowledgement occurs only when the exact Slot is actually presented and presentation-ready;
- cold explicit/notification unread intent may wait for exact-current readiness; stale replacement invalidates it;
- exact-current navigation failure does not promote the failed WebView and resolves into native bounded error/empty presentation;
- notification route does not clear unread merely because a Runtime exists;
- generation protection remains independent from presentation correction;
- hidden generating Runtime remains protected until generation truth ends.

## 6. Rapid switching

For A→B→A:

```text
A loading under Restoring
→ B becomes current
→ A presentation generation becomes stale
→ A Runtime may remain resident and may finish internally
→ background A readiness may update only for exact A identity
→ B UI remains untouched
→ return to loading A: new Restoring presentation around same Runtime
→ return to ready A: resident fast path
```

No stale Slot may flash, focus, dismiss current Restoring, or transfer readiness to a replacement Runtime.

## 7. Final machine and independent evidence

At semantic implementation head `e187f83fd2c4198d3e2baa64ef5074037c87c410`:

```text
focused affected suites = PASS (381 passed / 4 skipped / 0 failed)
full XCTest = PASS (1153 passed / 4 skipped / 0 failed)
Debug arm64 = PASS
Release arm64 = PASS
native arm64 verification = PASS
package lock = unchanged
macOS CI = PASS (run 41464559708 / job 125341924174)
QA DMG = PASS (run 41464559462)
fresh independent exact-diff / ownership / data-safety audit = PASS
```

At final pre-closeout control head `1a77fae92c53708e2c6c373301c825187fdb1de4`:

```text
macOS CI = PASS (run 41466335384 / job 125348105768)
QA DMG = PASS (run 41466335512)
```

Historical broad CI failures at `1a457ad…` remain unexplained. Later passing runs do not establish their cause.

## 8. Human real-Mac acceptance — PASS

The user tested the exact WP1 build and explicitly accepted WP1 for closeout.

Acceptance log:

`FloatTabs-WP1-Human-20261102-231725.jsonl`

Observed acceptance evidence includes:

```text
panel.materialization.deferred = 23
panel.restoring_surface.window_visible = 23
panel.materialization.attached = 23
panel.materialization.readiness_failed = 0
```

Notification cold routing enters the canonical restoring/materialization path. Rapid switching exercised cancellation and re-entry without a reported blank/stale/focus regression. Session/login/conversation behavior remained acceptable to the user.

Final verdict:

```text
WP1_HUMAN_UI_ACCEPTANCE=PASS
WP1=COMPLETE
```

## 9. Separate lifecycle-policy evidence discovered during acceptance

The same run exposes a separate shipped lifecycle-policy problem:

```text
managed_resident_count = 3
target = 2
eviction_count = 1
reason = reconcile
```

Nine such reconcile evictions occurred in roughly 50 seconds during frequent three-Runtime switching. This can repeatedly hibernate an Automatic Runtime and turn legitimate working-set switching into cold-restore thrash.

This does **not** reopen WP1. It is accepted evidence for the next lifecycle-policy phase.

Durable direction requested by the user for that future phase:

```text
NO_FIXED_NORMAL_RESIDENT_COUNT
PINNED_KEEP_LOADED = NO_AUTOMATIC_EXIT
AUTOMATIC = STAGED_AUTOMATIC_LIFECYCLE
NORMAL_RECLAIM = TIME/STATE BASED, NOT TAB-COUNT BASED
MEMORY_PRESSURE = PROGRESSIVE AUTOMATIC RECLAIM SIGNAL
```

The number of resident Tabs is not itself a normal reclaim reason.

The future WP2 contract must separately define the inactivity stages, pressure behavior, pin semantics, and long-idle cleanup. Those changes are not part of V2/WP1 and must not be implemented on PR #194.

## 10. Snapshot, scheduling and memory boundaries

```text
SNAPSHOT_SPIKE=NOT_NEEDED_FOR_WP1
WEBKIT_FIRST_PIXEL=UNMEASURED
AGGREGATE_GIB_BUDGET=DEFERRED_PLATFORM_BLOCKED
```

WP1 does not add explicit `WKPreferences.inactiveSchedulingPolicy` overrides. Existing public WebKit behavior and macOS-version gating remain separate future evidence/implementation concerns.

No production aggregate/per-Slot GiB budget may be reconstructed from Runtime count, root-only development tooling, private SPI, or unsupported correlation heuristics.

## 11. Historical WP1 acceptance evidence

At the recorded WP1 revision, machine verification, an independent review, and user-owned Real-Mac interaction acceptance were reported complete. The original WP1 record contains `HUMAN_UI_ACCEPTANCE=PASS` for that **historical** product head only.

Its old PR #194 closeout and WP2 task-transition language is historical delivery evidence, not a current permission or merge instruction. Present restore behavior is established by this bounded product design together with newer contracts and actual source/tests.
