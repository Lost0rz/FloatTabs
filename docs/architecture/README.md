# FloatTabs — Architecture Document Status

Read [`../README.md`](../README.md) first. It is the repository-wide documentation authority/status index.

## Current active lifecycle/performance authority

Current task:

`FT-ADAPTIVE-LIFECYCLE-RESTORE-001`

Current contract:

- [`FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md`](FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md) — **CURRENT / ACCEPTED / WP1 FROZEN / WP2–WP4 BLOCKED**.

Superseded:

- [`FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md`](FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md) — historical WP0 evidence-gate authority only.

Current stage:

```text
controlled WP0 restore evidence reconciled
→ WP1 unified cold-restore presentation gate AUTHORIZED
→ machine verification + independent audit
→ real-Mac human acceptance
→ WP2–WP4 remain separately blocked
```

## Preserved lifecycle foundations

- persistent Slot/Profile/session state is separate from disposable `WKWebView` Runtime lifetime;
- `SlotLifecycleCoordinator` is the sole lifecycle policy/reclaim writer;
- `WebViewPool` owns Runtime create/reuse/hibernate/restore/release mechanics;
- `PanelController` owns selected-Slot presentation/materialization;
- `WebPanelContainerView` owns native restoring/Web surface mechanics;
- `WebAttentionCoordinator` owns generation protection truth;
- Browser Profile/session data survives Runtime reclaim;
- notification/unread truth does not require completed Runtime residency;
- system warning/critical pressure reclaim is progressive;
- `Automatic | Keep Loaded` remains the shipped per-Slot retention preference.

## Accepted cold-restore evidence

Controlled evidence on PR #194 head `0cc2c2a1…` established:

```text
resident short revisit ≈ tens of milliseconds
cold restore observed  ≈ 3–6 seconds
fresh WKWebView create ≈ tens of milliseconds
```

Therefore fresh WKWebView object construction is not the dominant multi-second cost.

### Normal cold summon defect

Current sequence can be:

```text
shell visible
→ restoring requested inside source-owned Web surface
→ source window remains hidden
→ fresh Runtime navigates/restores for seconds
→ readiness
→ source window finally ordered front
```

Result: shell/colored frame is visible while the truthful restoring surface is not.

### Notification cold-route defect

Current sequence can be:

```text
notification exact-Slot route
→ Slot selection eagerly recreates Runtime
→ panel presentation begins
→ source window ordered front while fresh WebView is blank
→ navigation continues afterward
```

Result: blank Web page is visible before useful content.

Current classification:

```text
COLD_RESTORE_PRESENTATION_ROOT_CAUSE=KNOWN
COLD_RESTORE_LATENCY_ROOT_CAUSE=NARROWED
WEBKIT_FIRST_PIXEL=UNMEASURED
```

## WP1 accepted design

All selected nonresident presentation requests must converge on one gate:

```text
nonresident presentation request
→ exact target + restoring ownership
→ native Restoring… surface actually visible
→ fresh exact Runtime materializes/restores underneath
→ exact-current readiness
→ ready Web surface reveal
→ focus / interaction / unread acknowledgement
```

Paths that must converge:

- menu-bar summon;
- global-hotkey summon;
- explicit switch to a nonresident Slot;
- completion-notification exact-Slot route.

Resident ready Runtime keeps its existing fast path.

The existing native restoring surface is preferred. No snapshot layer is authorized in WP1.

## Current production tuning under review — unchanged during WP1

Production still implements:

```text
normal Automatic resident target = 2
Automatic inactive release       = 30s
```

Accepted design conclusions:

- fixed target `2` is not final product truth;
- `30s == mandatory destructive lifetime` is rejected as the final product invariant;
- pressure-first + bounded long-idle cleanup is currently favored but not frozen;
- WP2 lifecycle-policy implementation remains blocked.

## Public WebKit scheduling boundary

`WebViewFactory` does not currently override `WKPreferences.inactiveSchedulingPolicy`.

On macOS 14+, public WebKit documents the default policy as `suspend` for an idle detached WebView; media/loading/interactive activity may be exempt.

The M4/macOS 26 host confirms the fresh public configuration default value, but actual detached idle/generation/media resource characterization remains incomplete.

Therefore WP1 must not add scheduling overrides. macOS 13 remains `NOT_TESTED` for this evidence set.

## Aggregate-memory platform boundary

The prior measurement-feasibility result remains current:

- [`FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`](FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md) — dominant WebContent/GPU attribution to FloatTabs is not deterministic ordinary production truth.

Therefore a production GiB budget remains deferred/platform-blocked. Runtime count must not be relabeled as RAM.

Long-term design evidence:

- [`FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`](FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md).

Delivered pressure/background evidence:

- [`FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md`](FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md).

## Current conceptual lifecycle facts

```text
ACTIVE_OR_PROTECTED
RESIDENT_BACKGROUND
NO_RUNTIME_WITH_RESTORE_STATE
RESTORING
```

`RESIDENT_BACKGROUND` does not automatically mean a guaranteed product-level `FROZEN` state.

## Current ownership

- `SlotLifecycleCoordinator` — sole Runtime lifecycle decision/reclaim writer;
- `WebViewPool` — live Runtime and transient restore-state mechanism;
- `WebViewFactory` — supported WKWebView configuration mechanism;
- `PanelController` / `WebPanelContainerView` — restoring/presentation ownership;
- `TabStore` / `WebAppProfile` — persistent Slot configuration and retention preference;
- `WebAttentionCoordinator` / `ChatGPTAttentionBridge` — generation protection facts;
- Runtime Diagnostics — evidence only;
- Website Cache domain — re-downloadable cache cleanup only.

## WP1 verification route

```text
implement unified cold presentation gate
→ focused presentation/materialization/notification regressions
→ full XCTest
→ Debug + Release arm64
→ literal-head macOS CI + QA DMG
→ fresh independent exact-diff / ownership / data-safety audit
→ real-Mac human acceptance
```

Human acceptance must prove normal cold summon and notification cold route no longer expose unexplained blank states while resident quick revisit remains fast.

## Historical/deferred routing

Treat as historical/deferred unless explicitly referenced by current Authority:

- Adaptive Lifecycle Restore Contract V1 after its WP0 evidence-gate role;
- Phase 1–7 implementation contracts after delivered boundaries;
- original Phase 8 adaptive GiB-budget implementation beyond its Gate-0 evidence;
- V1–V5 lifecycle contracts;
- old Hot/Warm/Cold benchmark/policy documents;
- documents that present fixed `target=2` or 30s destructive lifetime as permanent product truth.

Current mutation follows `CURRENT_TASK.md` plus the adaptive lifecycle/restore V2 contract.
