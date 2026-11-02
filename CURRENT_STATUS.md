# FloatTabs Current Status

**Status date:** `2026-11-02`  
**Repository:** `Lost0rz/FloatTabs`  
**Default branch:** `main`

## Mode

**MODE: ADAPTIVE LIFECYCLE + RESTORE PERFORMANCE — WP0 RESTORE EVIDENCE RECONCILED / WP1 AUTHORIZED / WP2–WP4 BLOCKED**

Current task: `FT-ADAPTIVE-LIFECYCLE-RESTORE-001` — **ACTIVE / WP1 RESTORE-PRESENTATION CORRECTIVE AUTHORIZED**.

Task branch:

`codex/adaptive-lifecycle-restore-001`

Draft PR:

`#194 — design: adaptive lifecycle and restore performance`

Execution baseline:

`main@7e179aaf4dbf0c538c7c2221101fc74d16e49b98`

Latest reviewed evidence head before this control update:

`0cc2c2a11a59200645380ae3f477d3803e67e6ab`

## Repository / delivery state

```text
PUBLIC_RELEASE=v0.5.8
PUBLIC_BUILD=26
MAIN_BASELINE=7E179AAF
PR_193=MERGED
NOTIFICATION_HUMAN_ACCEPTANCE=PASS
TASK=FT-ADAPTIVE-LIFECYCLE-RESTORE-001
TASK_STATE=ACTIVE_WP1_AUTHORIZED
PR_194=OPEN_DRAFT_UNMERGED
WP0_RESTORE_EVIDENCE=SUFFICIENT_FOR_WP1
WP0_BACKGROUND_RESOURCE_EVIDENCE=PARTIAL
WP1_PRODUCT_MUTATION=PRESENTATION_ONLY_AUTHORIZED
WP2_POLICY_MUTATION=BLOCKED
WP3_SCHEDULING_MUTATION=BLOCKED
WP4_POLICY_INTEGRATION=BLOCKED
COLD_RESTORE_PRESENTATION_ROOT_CAUSE=KNOWN
COLD_RESTORE_LATENCY_ROOT_CAUSE=NARROWED
WEBKIT_FIRST_PIXEL=UNMEASURED
NORMAL_POLICY_RECOMMENDATION=A_FAVORED_NOT_FROZEN
SNAPSHOT_SPIKE=NOT_NEEDED_FOR_WP1
NORMAL_FIXED_TARGET_2=CURRENT_PRODUCTION_TRUTH_NOT_FINAL_PRODUCT_TARGET
AUTOMATIC_30S_UNCONDITIONAL_RELEASE=CURRENT_PRODUCTION_TRUTH_REJECTED_AS_FINAL_INVARIANT
AGGREGATE_GIB_BUDGET=DEFERRED_PLATFORM_BLOCKED
PRIVATE_WEBKIT_SPI=FORBIDDEN
```

Current durable task contract:

`docs/architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`

V1 is historical/superseded after the controlled WP0 restore evidence reconciliation.

## Controlled real-Mac restore evidence — accepted 2026-11-02

Environment:

```text
FloatTabs 0.5.8 (26)
source revision = 0cc2c2a11a59200645380ae3f477d3803e67e6ab
architecture = arm64
host = Apple M4 Mac mini / 16 GB
macOS = 26.6.2
```

### Resident quick revisit

A short hide/reopen while the Runtime remained resident completed presentation in roughly **35 ms** with no new Runtime creation.

Conclusion:

```text
RESIDENT_REVISIT=EFFECTIVELY_IMMEDIATE
```

### Normal cold summon after Automatic hibernate

The controlled Slot was hibernated by `automatic_grace_expired`, then summoned again.

Observed materialization generation:

```text
materialization.deferred                  0 ms
web_runtime.create.begin                ~12 ms
web_runtime.created                     ~63 ms
panel.materialization.attached          ~64 ms
web_content_reveal_requested          ~3123 ms
source.order_front                    ~3127 ms
readiness_completed                   ~3132 ms
```

A second controlled cold materialization showed the same shape with a longer Web-readiness interval:

```text
materialization.deferred                  0 ms
web_runtime.created                     ~48 ms
web_content_reveal_requested          ~6034 ms
readiness_completed                   ~6041 ms
```

`WKWebView` object creation is therefore not the dominant cold-restore cost. The dominant observed interval is after attach while the fresh Runtime navigates/restores toward accepted readiness.

In both cold-summon cases the existing restoring overlay had been requested, but no `panel.restoring_surface.window_visible` event occurred before readiness. The source window was ordered front only at the reveal/readiness boundary. This matches the human observation: FloatTabs shell/colored frame appeared first while the Web surface remained visually absent for roughly 2–3 seconds.

### Notification-click cold restore

The hidden ChatGPT generation remained protected through the Automatic grace boundary. Generation completed, notification submission succeeded, and the completed Automatic Runtime hibernated roughly 31.5 seconds after generation finished.

After the Runtime had been hibernated, clicking the completion notification produced:

```text
notification.route.received               0 ms
web_runtime.create.begin                  ~6 ms
web_runtime.created                      ~67 ms
panel.presentation.begin                 ~70 ms
source.order_front                       ~77 ms
navigation.commit                      ~1991 ms
```

For the notification target Slot this path did **not** emit the normal deferred-materialization sequence (`panel.materialization.deferred`, restoring-surface-visible, attached, reveal-requested, readiness-completed) before the source window was exposed.

Human observation matched the trace: the Web surface appeared first as a blank page, then loaded visible content.

Exact persistent Slot routing and eventual Browser Profile/session/conversation restoration remained correct.

## Accepted root-cause classification

```text
COLD_RESTORE_PRESENTATION_ROOT_CAUSE=KNOWN
```

The product currently has inconsistent presentation ordering for nonresident selected Slots:

1. **Normal cold summon:** deferred materialization exists, but the source window that owns the native `Restoring…` surface remains hidden until navigation readiness. The user sees shell/frame without a truthful restoring surface.
2. **Notification cold route:** exact Slot selection eagerly recreates the Runtime before the normal deferred-presentation gate owns the route, and the source window is ordered front while the fresh WebView is still blank/loading.

The common defect is therefore not missing restore-state data and not slow `WKWebView` construction. It is the absence of one canonical cold-restore presentation gate across entry paths.

```text
COLD_RESTORE_LATENCY_ROOT_CAUSE=NARROWED
```

Fresh Runtime creation is only tens of milliseconds in the controlled traces. Multi-second cold latency is dominated by Web navigation/readiness after Runtime creation/attachment. The exact WebKit compositor first-useful-pixel boundary remains unmeasured and must not be claimed.

## WP1 — authorized mutation boundary

WP1 may now change **presentation/materialization behavior only** to establish one canonical nonresident presentation gate.

Required outcome:

```text
nonresident selected Slot requested
→ native Restoring… surface is actually visible immediately
→ exact Runtime create/restore occurs underneath the restoring state
→ blank/unready Web content is not exposed
→ exact-current readiness validates Slot + materialization + Runtime identity
→ real Web surface is revealed
→ focus / interaction / unread acknowledgement proceed only for the ready exact-current Runtime
```

The following entry paths must converge on the same gate:

- normal summon of a currently selected nonresident Slot;
- global-hotkey / menu-bar presentation;
- explicit switch to a nonresident Slot while FloatTabs is presented;
- completion-notification exact-Slot route.

Preserve stale-generation cancellation and rapid-switch correctness.

### Snapshot decision

A visual snapshot layer is **not needed for WP1**. The controlled evidence shows the existing native restoring concept is sufficient in principle; the failure is visibility/ordering and route convergence. A snapshot may be reconsidered only after a corrected native restoring path fails explicit human acceptance.

## Lifecycle-policy direction — not yet authorized for implementation

The controlled evidence strengthens but does not complete the healthy-state policy decision:

```text
resident revisit ≈ tens of milliseconds
cold revisit     ≈ 3–6 seconds in observed runs
```

Therefore a universal 30-second destructive lifetime is rejected as the final product invariant, and fixed `target=2` remains rejected as final product truth.

**Option A — pressure-first + bounded long-idle cleanup is currently favored**, because it preserves recent resident Runtime without pretending Runtime count is a memory budget. However the long-idle boundary and any healthy-state cleanup semantics remain unfrozen until the remaining background/resource evidence is reconciled.

WP2 remains blocked.

## Preserved invariants

- `SlotLifecycleCoordinator` remains the sole lifecycle policy writer.
- `WebViewPool` remains Runtime create/hibernate/restore/release mechanism owner.
- `PanelController` / `WebPanelContainerView` remain presentation/materialization owners.
- `WebAttentionCoordinator` remains generation/Attention authority.
- `TabStore` owns persistent Slot selection/configuration, not Runtime lifecycle policy.
- Browser Profile/cookies/session/configuration are never cleared as resource management.
- warning/critical pressure ladder remains operational.
- generating Runtime remains hard-protected.
- no private WebKit SPI, process killing, reload/reset workaround, guessed RAM attribution or second lifecycle writer.
- notification preview/privacy/exact-Slot routing from PR #193 remains a regression boundary.

## Next gate

```text
WP1 unified cold-restore presentation gate
→ focused machine regressions
→ full XCTest + Debug/Release arm64
→ literal-head macOS CI + QA DMG
→ independent exact-diff / ownership / data-safety audit
→ real-Mac human acceptance for normal cold summon + notification cold route
→ only then consider WP1 merge readiness

WP2 / WP3 / WP4 remain blocked pending separate authority reconciliation.
```
