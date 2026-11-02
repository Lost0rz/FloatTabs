# FloatTabs — Architecture Document Status

Read [`../README.md`](../README.md) first. It is the repository-wide documentation authority/status index.

## Current active lifecycle/performance authority

Current task:

FT-ADAPTIVE-LIFECYCLE-RESTORE-001 / WP2 card FT-ADAPTIVE-LIFECYCLE-RESTORE-001-WP2-001

Current WP2 policy:

- [FloatTabs_Runtime_Lifecycle_Policy_V7.md](FloatTabs_Runtime_Lifecycle_Policy_V7.md) — FROZEN / WP2 POLICY; source follows remote control-bootstrap verification.

WP1 regression boundary:

- [FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md](FloatTabs_Adaptive_Lifecycle_Restore_Contract_V2.md) — accepted and merged WP1 presentation/readiness contract.

V1 remains historical/superseded.

Current stage:

~~~text
WP1 exact-Runtime cold-presentation gate = MERGED / COMPLETE
→ WP2 control/design bootstrap and staged Automatic lifecycle = ACTIVE
→ source mutation only after remote bootstrap verification
→ WP3 scheduling and WP4 integration remain separate
~~~

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

## Current WP2 lifecycle policy

Policy V7 owns current normal and pressure lifecycle eligibility:

- no fixed-count normal reclaim;
- Keep Loaded / Pinned is never automatically reclaimed by normal, warning, or critical FloatTabs policy;
- Automatic progresses through RECENT (<30s), IDLE (30s to <600s), and LONG_IDLE (>=600s);
- normal policy reclaims only inactive, unprotected LONG_IDLE Automatic;
- warning reclaims eligible IDLE/LONG_IDLE Automatic progressively;
- critical may bypass RECENT but still reclaims only unprotected Automatic;
- pressure candidates are processed oldest-first with fresh-fact revalidation;
- 30s is anti-thrash protection and 600s is an initial tunable default.

The V6 fixed target, Phase 7 30s destructive release, and Keep Loaded critical reclaim semantics are historical for this policy boundary. V6 remains useful for aggregate-memory feasibility and non-conflicting architecture boundaries.

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
- fixed-count healthy-state policy and 30s destructive-release semantics in V6 / Phase 7 / Phase 8 pressure documents, superseded for WP2 by V7;
- old Hot/Warm/Cold benchmark/policy documents;
- documents that present fixed target=2 or 30s destructive lifetime as permanent product truth.

Current mutation follows CURRENT_TASK.md plus Runtime Lifecycle Policy V7. WP1 presentation/readiness regressions follow Adaptive Lifecycle Restore Contract V2.
