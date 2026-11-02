# FloatTabs Documentation Authority / Status Index

> Current document-routing index. Read this before relying on documents under `docs/` for implementation decisions.

## 1. Authority order

```text
AGENTS.md
→ CURRENT_STATUS.md
→ CURRENT_TASK.md
→ this docs/README.md routing index
→ current task design/architecture contract explicitly linked by Authority
→ docs/architecture/README.md
→ docs/architecture/DOMAIN_MAP.md for navigation only
→ current production source + regression tests + fresh runtime/repository evidence
```

Historical documents remain evidence only unless current Authority explicitly restores them.

## 2. Current active task

Current mutation authority is:

`FT-ADAPTIVE-LIFECYCLE-RESTORE-001`

Current accepted/frozen task contract:

[`architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md`](architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md)

Current stage:

```text
WP0 runtime characterization / restore-timing evidence
PRODUCT POLICY MUTATION = NOT YET AUTHORIZED
```

The task addresses three user-observed lifecycle/performance problems:

1. cold/nonresident restore can expose the shell before useful Web content for roughly one second or more;
2. the healthy-state `Automatic resident target = 2` is too rigid as final product policy;
3. hidden/inactive Runtime needs a supported lower-cost resident strategy that does not sacrifice restore speed or generation/media correctness.

## 3. Current lifecycle/runtime authority

Current task-specific authority:

- [`architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md`](architecture/FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md) — **CURRENT / ACCEPTED / FROZEN FOR WP0**.

Preserved durable/background evidence:

- [`architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md`](architecture/FloatTabs_Runtime_Lifecycle_Memory_Contract_V6.md) — accepted long-term lifecycle design evidence where not superseded by current task authority;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase8_WP0_Measurement_Feasibility_Report_V1.md) — aggregate WebContent/GPU attribution feasibility boundary;
- [`architecture/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md`](architecture/FloatTabs_Runtime_Lifecycle_Phase8_Pressure_Efficiency_Rescope_Contract_V1.md) — delivered progressive pressure ladder + background generation efficiency behavior.

Current production facts remain:

```text
Automatic normal resident target = 2
Automatic inactive release       = 30s
warning/critical pressure ladder  = progressive
Generating                        = hard-protected
```

The first two are now explicitly under review and are not accepted final product tuning.

## 4. Runtime ownership

```text
SlotLifecycleCoordinator
→ sole lifecycle policy / reclaim writer

WebViewPool
→ WKWebView create / reuse / hibernate / restore / release mechanism

WebViewFactory
→ WKWebView configuration mechanism, not lifecycle policy

PanelController + WebPanelContainerView
→ shell / selected-Slot presentation / restoring surface / readiness orchestration

WebAttentionCoordinator + ChatGPTAttentionBridge
→ generation protection facts

TabStore / WebAppProfile / Browser Profiles
→ persistent Slot/config/session identity, not Runtime lifecycle

RuntimeDiagnostics
→ evidence only
```

No task may introduce a second canonical lifecycle writer.

## 5. Current WebKit inactive-scheduling evidence

Current `WebViewFactory` does not override `WKPreferences.inactiveSchedulingPolicy`.

On macOS 14+, Apple's public API documents the default as `suspend` for a WebView that is not in a window. Idle suspended WebViews pause JavaScript execution/page layout; media/loading/other interactive activity may be exempt.

Therefore the current task must characterize actual FloatTabs behavior before adding an explicit scheduling override. Do not describe `.suspend` as a newly invented FloatTabs Frozen state.

macOS 13 compatibility remains required; the public inactive-scheduling API is unavailable there.

## 6. Aggregate-memory boundary

The prior feasibility gate remains binding:

```text
host footprint                         = measurable
FloatTabs-attributable Networking      = measurable
FloatTabs-attributable WebContent/GPU  = not deterministically attributable
```

Therefore still deferred/platform-blocked:

- production Auto / Custom / Unlimited GiB budget;
- exact aggregate FloatTabs/WebKit working-set enforcement;
- exact per-Slot memory claims.

Do not substitute Runtime count, correlation heuristics, private SPI, root-only tooling or restricted entitlements as production truth.

## 7. Current WP0 route

```text
fresh main baseline
→ measure resident quick revisit
→ measure cold/nonresident materialization timeline
→ prove first restoring/content visible boundary
→ characterize detached idle / generating / media behavior
→ compare relative resource states
→ decide whether a bounded memory-only visual snapshot is justified
→ choose healthy-state policy direction:
     A pressure-first + long-idle cleanup
     OR
     B adaptive soft warm-set
     OR narrowly evidenced hybrid
→ reconcile contract / CURRENT_TASK
→ only then authorize WP1–WP4 product behavior mutation
```

A root/sudo benchmark may be used as development evidence but never as a production dependency or policy input.

## 8. Delivered notification task

PR #193 (`FT-NOTIFICATION-RELIABILITY-RICH-PREVIEW-001`) is **MERGED / HUMAN ACCEPTED** at `main@7e179aaf...`.

Delivered behavior:

```text
valid hidden ChatGPT completion
→ durable unread .marked
→ bounded one-shot assistant preview
→ native macOS notification
→ exact persistent Slot UUID click route
→ existing Runtime materialization/restore if nonresident
```

The delivered notification contract remains bounded feature authority:

[`architecture/FloatTabs_Native_Completion_Notification_Reliability_Rich_Preview_Contract_V1.md`](architecture/FloatTabs_Native_Completion_Notification_Reliability_Rich_Preview_Contract_V1.md)

The current lifecycle task must preserve its trigger, privacy and exact-Slot routing regressions.

## 9. Other bounded current contracts

- [`design/FloatTabs_UI_Design_System_v1.3.md`](design/FloatTabs_UI_Design_System_v1.3.md) — shell/rail interaction baseline where not superseded;
- [`design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md`](design/FloatTabs_Attention_Active_Tab_Visual_Refinement_V1.md) — active-tab/unread visual refinement.

## 10. Directory routing

| Directory | Current role |
| --- | --- |
| `docs/architecture/` | Current architecture/task contracts plus historical architecture evidence |
| `docs/architecture/archive/` | Explicit historical snapshots; never current task authority |
| `docs/design/` | Current bounded UI contracts plus historical design evidence |
| `docs/product/` | Historical/accepted feature contracts and old Stage plans |
| `docs/diagnostics/` | Diagnostic evidence unless promoted by current Authority |
| `docs/performance/` | Historical/tuning evidence unless current task explicitly adopts it |
| `docs/validation/` | Historical validation evidence; never task authorization |
| `docs/release/` | Historical release evidence |
| `docs/superpowers/` | Historical plans from older workflow |
| `docs/uiux/` | Generated/reference UI material unless explicitly promoted |

## 11. Conflict rule

When historical material disagrees with current source/tests or current Authority:

1. follow `CURRENT_TASK.md` plus `FloatTabs_Adaptive_Lifecycle_Restore_Contract_V1.md` for current work;
2. preserve existing Browser Profile/session/data-safety boundaries;
3. preserve the delivered warning/critical pressure ladder unless current Authority explicitly changes it;
4. preserve the Phase 8 measurement-feasibility boundary against fake GiB budgets;
5. keep cold-restore root cause `UNKNOWN` until WP0 timing evidence proves it;
6. update this routing index when current-sounding historical wording could mislead future work.
